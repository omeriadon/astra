import Observation
import Sparkle

@MainActor
@Observable
final class UpdateManager: NSObject, SPUUserDriver {
	static let shared = UpdateManager()

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

	var isPresented = false
	private(set) var status: Status = .checking
	private(set) var update: UpdateDetails?
	var automaticChecks = false {
		didSet {
			if !automaticChecks {
				automaticInstalls = false
			}
			if updater.automaticallyChecksForUpdates != automaticChecks {
				updater.automaticallyChecksForUpdates = automaticChecks
			}
		}
	}

	var automaticInstalls = false {
		didSet {
			if updater.automaticallyDownloadsUpdates != automaticInstalls {
				updater.automaticallyDownloadsUpdates = automaticInstalls
			}
		}
	}

	@ObservationIgnored lazy var updater = SPUUpdater(
		hostBundle: .main,
		applicationBundle: .main,
		userDriver: self,
		delegate: nil
	)

	@ObservationIgnored private var choiceReply: ((SPUUserUpdateChoice) -> Void)?
	@ObservationIgnored private var acknowledgement: (() -> Void)?
	@ObservationIgnored private var cancellation: (() -> Void)?
	@ObservationIgnored private var started = false

	func start() {
		guard !started else { return }
		started = true

		do {
			try updater.start()
			automaticChecks = updater.automaticallyChecksForUpdates
			automaticInstalls = updater.automaticallyDownloadsUpdates
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
