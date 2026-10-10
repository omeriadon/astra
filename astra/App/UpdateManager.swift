#if os(macOS)
	import Darwin
	import Foundation
	import Observation

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
				if !automaticChecks { automaticInstalls = false }
				if !applyingRuntimeState && automaticChecks != oldValue {
					post("checks", value: automaticChecks)
				}
			}
		}
		var automaticInstalls = false {
			didSet {
				if !applyingRuntimeState && automaticInstalls != oldValue {
					post("installs", value: automaticInstalls)
				}
			}
		}

		@ObservationIgnored private var runtimeHandle: UnsafeMutableRawPointer?
		@ObservationIgnored private var runtimeEntry: (@convention(c) () -> Void)?
		@ObservationIgnored private var started = false

		override init() {
			super.init()
			NotificationCenter.default.addObserver(
				self, selector: #selector(receiveState(_:)),
				name: Notification.Name("com.omeriadon.astra.updater.state"), object: nil
			)
		}

		/// Loads only when the updater is scheduled or explicitly requested.
		func start() {
			guard !started else { return }
			let startedAt = BrowserLog.clock()
			let filename = "AstraUpdaterRuntime.framework/AstraUpdaterRuntime"
			guard let base = Bundle.main.privateFrameworksURL else {
				fail("Astra's updater framework directory is unavailable.")
				return
			}
			guard let handle = dlopen(base.appendingPathComponent(filename).path, RTLD_NOW | RTLD_LOCAL) else {
				fail("Could not load Astra's updater: " + String(cString: dlerror()))
				return
			}
			guard let symbol = dlsym(handle, "AstraUpdaterRuntimeStart") else {
				dlclose(handle)
				fail("Astra's updater framework is incompatible with this version.")
				return
			}
			runtimeHandle = handle
			runtimeEntry = unsafeBitCast(symbol, to: (@convention(c) () -> Void).self)
			started = true
			BrowserLog.duration(.lifecycle, "updater.runtime-load", since: startedAt,
			                    warnAboveMilliseconds: 200)
			runtimeEntry?()
		}

		func checkForUpdates() {
			start()
			guard started else { return }
			post("check")
		}

		func choose(_ choice: Choice) {
			post("choice", choice: choice.rawValue)
		}

		func dismiss() { post("dismiss") }

		private func post(_ command: String, value: Bool? = nil, choice: String? = nil) {
			guard started else { return }
			var payload: [String: Any] = ["command": command]
			if let value { payload["value"] = value }
			if let choice { payload["choice"] = choice }
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
			   let build = values["build"] as? String {
				update = UpdateDetails(
					version: version, build: build,
					infoURL: (values["infoURL"] as? String).flatMap(URL.init(string:)),
					isInformationOnly: values["informationOnly"] as? Bool ?? false
				)
			} else { update = nil }
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
