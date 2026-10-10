#if os(macOS)
	import Foundation
	import Sparkle

	@MainActor
	final class AstraUpdaterRuntime: NSObject, SPUUserDriver {
		static let shared = AstraUpdaterRuntime()

		struct UpdateDetails {
			let version: String
			let build: String
			let infoURL: URL?
			let isInformationOnly: Bool
		}

		enum Status {
			case checking
			case available
			case downloading
			case preparing
			case ready
			case installing
			case message(String)
		}

		var isPresented = false {
			didSet { publishState() }
		}

		private(set) var status: Status = .checking {
			didSet { publishState() }
		}

		private(set) var update: UpdateDetails? {
			didSet { publishState() }
		}

		var automaticChecks = false {
			didSet {
				if !automaticChecks {
					automaticInstalls = false
				}
				if updater.automaticallyChecksForUpdates != automaticChecks {
					updater.automaticallyChecksForUpdates = automaticChecks
				}
				publishState()
			}
		}

		var automaticInstalls = false {
			didSet {
				if updater.automaticallyDownloadsUpdates != automaticInstalls {
					updater.automaticallyDownloadsUpdates = automaticInstalls
				}
				publishState()
			}
		}

		lazy var updater = SPUUpdater(
			hostBundle: .main,
			applicationBundle: .main,
			userDriver: self,
			delegate: nil
		)

		private var choiceReply: ((SPUUserUpdateChoice) -> Void)?
		private var acknowledgement: (() -> Void)?
		private var cancellation: (() -> Void)?
		private var started = false
		private var updaterReadinessObservation: NSKeyValueObservation?

		override init() {
			super.init()
			NotificationCenter.default.addObserver(
				self, selector: #selector(receiveCommand(_:)),
				name: Notification.Name("com.omeriadon.astra.updater.command"), object: nil
			)
		}

		@objc private func receiveCommand(_ note: Notification) {
			guard let name = note.userInfo?["command"] as? String else { return }
			switch name {
				case "check":
					updater.checkForUpdates()
				case "dismiss":
					dismiss()
				case "choice":
					switch note.userInfo?["choice"] as? String {
						case "skip": choose(.skip)
						case "install": choose(.install)
						default: choose(.dismiss)
					}
				case "checks":
					if let value = note.userInfo?["value"] as? Bool {
						automaticChecks = value
					}
				case "installs":
					if let value = note.userInfo?["value"] as? Bool {
						automaticInstalls = value
					}
				default: break
			}
		}

		private func publishState() {
			let kind: String
			let message: String
			switch status {
				case .checking: kind = "checking"; message = ""
				case .available: kind = "available"; message = ""
				case .downloading: kind = "downloading"; message = ""
				case .preparing: kind = "preparing"; message = ""
				case .ready: kind = "ready"; message = ""
				case .installing: kind = "installing"; message = ""
				case let .message(value): kind = "message"; message = value
			}
			var payload: [String: Any] = [
				"status": kind, "message": message, "presented": isPresented,
				"automaticChecks": automaticChecks,
				"automaticInstalls": automaticInstalls,
				"allowsAutomaticUpdates": updater.allowsAutomaticUpdates,
				"canCheckForUpdates": updater.canCheckForUpdates,
			]
			if let update {
				payload["version"] = update.version
				payload["build"] = update.build
				payload["informationOnly"] = update.isInformationOnly
				payload["infoURL"] = update.infoURL?.absoluteString
			}
			NotificationCenter.default.post(
				name: Notification.Name("com.omeriadon.astra.updater.state"),
				object: nil, userInfo: payload
			)
		}

		func start() {
			guard !started else { return }
			started = true

			do {
				try updater.start()
				updaterReadinessObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
					Task { @MainActor [weak self] in self?.publishState() }
				}
				automaticChecks = updater.automaticallyChecksForUpdates
				automaticInstalls = updater.automaticallyDownloadsUpdates
				publishState()
			} catch {
				status = .message(error.localizedDescription)
				isPresented = true
			}
		}

		func choose(_ choice: SPUUserUpdateChoice) {
			guard let choiceReply else { return }
			self.choiceReply = nil
			if choice == .install {
				if case .ready = status {
					status = .installing
				} else {
					status = .downloading
				}
			} else {
				isPresented = false
			}
			choiceReply(choice)
		}

		func dismiss() {
			if choiceReply != nil {
				choose(.dismiss)
			} else {
				cancellation?()
				cancellation = nil
				acknowledgement?()
				acknowledgement = nil
				isPresented = false
			}
		}

		func show(
			_: SPUUpdatePermissionRequest,
			reply: @escaping (SUUpdatePermissionResponse) -> Void
		) {
			reply(SUUpdatePermissionResponse(
				automaticUpdateChecks: automaticChecks,
				automaticUpdateDownloading: NSNumber(value: automaticInstalls),
				sendSystemProfile: false
			))
		}

		func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
			self.cancellation = cancellation
			status = .checking
			isPresented = true
		}

		func showUpdateFound(
			with appcastItem: SUAppcastItem,
			state: SPUUserUpdateState,
			reply: @escaping (SPUUserUpdateChoice) -> Void
		) {
			cancellation = nil
			update = UpdateDetails(
				version: appcastItem.displayVersionString,
				build: appcastItem.versionString,
				infoURL: appcastItem.infoURL,
				isInformationOnly: appcastItem.isInformationOnlyUpdate
			)
			choiceReply = reply
			status = state.stage == .installing ? .ready : .available
			isPresented = true
		}

		func showUpdateReleaseNotes(with _: SPUDownloadData) {}

		func showUpdateReleaseNotesFailedToDownloadWithError(_: any Error) {}

		func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
			showMessage(error.localizedDescription, acknowledgement: acknowledgement)
		}

		func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
			showMessage(error.localizedDescription, acknowledgement: acknowledgement)
		}

		private func showMessage(_ message: String, acknowledgement: @escaping () -> Void) {
			cancellation = nil
			update = nil
			status = .message(message)
			self.acknowledgement = acknowledgement
			isPresented = true
		}

		func showDownloadInitiated(cancellation: @escaping () -> Void) {
			self.cancellation = cancellation
			status = .downloading
		}

		func showDownloadDidReceiveExpectedContentLength(_: UInt64) {}

		func showDownloadDidReceiveData(ofLength _: UInt64) {}

		func showDownloadDidStartExtractingUpdate() {
			cancellation = nil
			status = .preparing
		}

		func showExtractionReceivedProgress(_: Double) {}

		func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
			choiceReply = reply
			status = .ready
			isPresented = true
		}

		func showInstallingUpdate(
			withApplicationTerminated _: Bool,
			retryTerminatingApplication _: @escaping () -> Void
		) {
			status = .installing
		}

		func showUpdateInstalledAndRelaunched(
			_: Bool,
			acknowledgement: @escaping () -> Void
		) {
			acknowledgement()
			isPresented = false
		}

		func dismissUpdateInstallation() {
			choiceReply = nil
			cancellation = nil
			isPresented = false
		}

		func showUpdateInFocus() {
			isPresented = true
		}

		#if DEBUG
			func showPreview(_ status: Status) {
				update = UpdateDetails(
					version: "0.2",
					build: "2",
					infoURL: nil,
					isInformationOnly: false
				)
				self.status = status
			}
		#endif
	}

	@_cdecl("AstraUpdaterRuntimeStart")
	@MainActor
	public func astraUpdaterRuntimeStart() {
		AstraUpdaterRuntime.shared.start()
	}

#endif
