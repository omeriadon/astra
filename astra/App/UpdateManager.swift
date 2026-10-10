#if os(macOS)
	import Darwin
	import Foundation
	import Observation

	/// Transfer the completed dyld image handle to the main actor only after
	/// dlopen/dlsym have completed on a utility thread. The loader owns the
	/// handle until the application's process exits (no premature dlclose).
	private nonisolated struct DeferredUpdaterImage: @unchecked Sendable {
		let handle: UnsafeMutableRawPointer?
		let entry: UnsafeMutableRawPointer?
		let failure: String?

		nonisolated static func open(at path: String) -> Self {
			guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
				let message = dlerror().map { String(cString: $0) } ?? "Unknown dynamic-loader error"
				return Self(handle: nil, entry: nil, failure: message)
			}
			guard let entry = dlsym(handle, "AstraUpdaterRuntimeStart") else {
				dlclose(handle)
				return Self(handle: nil, entry: nil, failure: "Astra's updater runtime is incompatible.")
			}
			return Self(handle: handle, entry: entry, failure: nil)
		}
	}

	/// Browser-side observable update state. This module never imports
	/// Sparkle; only AstraUpdaterRuntime loads it after first-frame readiness.
	@MainActor
	@Observable
	final class UpdateManager: NSObject {
		static let shared = UpdateManager()

		struct UpdateDetails {
			let version: String
			let build: String
			let infoURL: URL?
			let isInformationOnly: Bool
		}

		enum Status {
			case checking, available, downloading, preparing, ready, installing
			case message(String)
		}

		enum Choice: String { case skip, dismiss, install }

		var isPresented = false
		private(set) var status: Status = .checking
		private(set) var update: UpdateDetails?
		private(set) var canCheckForUpdates = false
		private(set) var allowsAutomaticUpdates = false
		@ObservationIgnored private var applyingRuntimeState = false
		var automaticChecks = false {
			didSet {
				if !automaticChecks {
					automaticInstalls = false
				}
				if !applyingRuntimeState, automaticChecks != oldValue {
					if started {
						post("checks", value: automaticChecks)
					} else {
						pendingAutomaticChecks = automaticChecks
						start()
					}
				}
			}
		}

		var automaticInstalls = false {
			didSet {
				if !applyingRuntimeState, automaticInstalls != oldValue {
					if started {
						post("installs", value: automaticInstalls)
					} else {
						pendingAutomaticInstalls = automaticInstalls
						start()
					}
				}
			}
		}

		@ObservationIgnored private var runtimeHandle: UnsafeMutableRawPointer?
		@ObservationIgnored private var runtimeEntry: (@convention(c) () -> Void)?
		@ObservationIgnored private var started = false
		@ObservationIgnored private var libraryLoadTask: Task<Void, Never>?
		@ObservationIgnored private var queuedManualCheck = false
		@ObservationIgnored private var pendingAutomaticChecks: Bool?
		@ObservationIgnored private var pendingAutomaticInstalls: Bool?

		override init() {
			super.init()
			NotificationCenter.default.addObserver(
				self, selector: #selector(receiveState(_:)),
				name: Notification.Name("com.omeriadon.astra.updater.state"), object: nil
			)
		}

		/// Loads only when the updater is scheduled or explicitly requested.
		/// Loads the two Mach-O images off the UI thread. Their Sparkle
		/// objects and user driver are initialized on MainActor once mapped.
		func start() {
			guard !started, libraryLoadTask == nil else { return }
			let startedAt = BrowserLog.clock()
			guard let base = Bundle.main.privateFrameworksURL else {
				fail("Astra's updater framework directory is unavailable.")
				return
			}
			let path = base.appendingPathComponent("AstraUpdaterRuntime.framework/AstraUpdaterRuntime").path
			libraryLoadTask = Task { @MainActor [weak self] in
				let loaded = await Task.detached(priority: .utility) {
					DeferredUpdaterImage.open(at: path)
				}.value
				guard let self else {
					if let handle = loaded.handle {
						dlclose(handle)
					}
					return
				}
				libraryLoadTask = nil
				guard let handle = loaded.handle, let entry = loaded.entry else {
					fail("Could not load Astra's updater: " + (loaded.failure ?? "Unknown error"))
					return
				}
				runtimeHandle = handle
				runtimeEntry = unsafeBitCast(entry, to: (@convention(c) () -> Void).self)
				started = true
				BrowserLog.duration(.lifecycle, "updater.runtime-load", since: startedAt, warnAboveMilliseconds: 200)
				let initializeStartedAt = BrowserLog.clock()
				runtimeEntry?()
				BrowserLog.duration(.lifecycle, "updater.runtime-start", since: initializeStartedAt, warnAboveMilliseconds: 80)
				// State snapshots emitted during start may temporarily reset UI
				// toggles. Replay any user changes made while the dylib was loading.
				if let requested = pendingAutomaticChecks {
					pendingAutomaticChecks = nil
					post("checks", value: requested)
				}
				if let requested = pendingAutomaticInstalls {
					pendingAutomaticInstalls = nil
					post("installs", value: requested)
				}
				if queuedManualCheck {
					queuedManualCheck = false
					post("check")
				}
			}
		}

		func checkForUpdates() {
			if started {
				post("check")
				return
			}
			queuedManualCheck = true
			status = .checking
			isPresented = true
			start()
		}

		func choose(_ choice: Choice) {
			post("choice", choice: choice.rawValue)
		}

		func dismiss() {
			post("dismiss")
		}

		private func post(_ command: String, value: Bool? = nil, choice: String? = nil) {
			guard started else { return }
			var payload: [String: Any] = ["command": command]
			if let value {
				payload["value"] = value
			}
			if let choice {
				payload["choice"] = choice
			}
			NotificationCenter.default.post(
				name: Notification.Name("com.omeriadon.astra.updater.command"),
				object: nil, userInfo: payload
			)
		}

		private func fail(_ message: String) {
			status = .message(message)
			isPresented = true
			BrowserLog.error(.lifecycle, "updater.lazy-load-failed", metadata: ["error": message])
		}

		@objc private func receiveState(_ note: Notification) {
			guard let values = note.userInfo,
			      let kind = values["status"] as? String else { return }
			applyingRuntimeState = true
			defer { applyingRuntimeState = false }
			automaticChecks = values["automaticChecks"] as? Bool ?? false
			automaticInstalls = values["automaticInstalls"] as? Bool ?? false
			allowsAutomaticUpdates = values["allowsAutomaticUpdates"] as? Bool ?? false
			canCheckForUpdates = values["canCheckForUpdates"] as? Bool ?? false
			if let version = values["version"] as? String,
			   let build = values["build"] as? String
			{
				update = UpdateDetails(
					version: version, build: build,
					infoURL: (values["infoURL"] as? String).flatMap(URL.init(string:)),
					isInformationOnly: values["informationOnly"] as? Bool ?? false
				)
			} else {
				update = nil
			}
			switch kind {
				case "available": status = .available
				case "downloading": status = .downloading
				case "preparing": status = .preparing
				case "ready": status = .ready
				case "installing": status = .installing
				case "message": status = .message(values["message"] as? String ?? "Updater error")
				default: status = .checking
			}
			isPresented = values["presented"] as? Bool ?? false
		}

		#if DEBUG
			func showPreview(_ status: Status) {
				update = UpdateDetails(version: "0.2", build: "2", infoURL: nil, isInformationOnly: false)
				self.status = status
			}
		#endif
	}
#endif
