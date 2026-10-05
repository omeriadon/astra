import Foundation
import Security

nonisolated enum BrowserConnectionState: Equatable, Sendable {
	case noPage
	case navigating
	case connectionFailed
	case encrypted
	case mixedContent
	case notSecure
	case localFile
	case localContent
	case unavailable

	var title: String {
		switch self {
			case .noPage: "No Page Loaded"
			case .navigating: "Checking Connection"
			case .connectionFailed: "Connection Failed"
			case .encrypted: "Connection Encrypted"
			case .mixedContent: "Mixed Content"
			case .notSecure: "Not Secure"
			case .localFile: "Local File"
			case .localContent: "Local Content"
			case .unavailable: "Connection State Unavailable"
		}
	}

	var symbol: String {
		switch self {
			case .navigating: "arrow.triangle.2.circlepath"
			case .connectionFailed: "exclamationmark.shield"
			case .encrypted: "lock.shield"
			case .notSecure, .mixedContent: "exclamationmark.triangle"
			case .noPage, .localFile, .localContent, .unavailable: "info.circle"
		}
	}
}

nonisolated enum BrowserActiveCaptureStatus: Equatable, Sendable {
	case unavailable
	case checking
	case inactive
	case active
	case muted

	var title: String {
		switch self {
			case .unavailable: "Unavailable"
			case .checking: "Checking"
			case .inactive: "Not active"
			case .active: "Active"
			case .muted: "Muted"
		}
	}

	static func current(isActive: Bool, isMuted: Bool, sampledDocumentID: Int?, committedDocumentID: Int?) -> Self {
		guard let committedDocumentID else { return .unavailable }
		guard sampledDocumentID == committedDocumentID else { return .checking }
		if isMuted {
			return .muted
		}
		return isActive ? .active : .inactive
	}
}

nonisolated struct BrowserServerCertificateSummary: Equatable, Sendable {
	let origin: String
	let subject: String
	let notValidBefore: Date?
	let notValidAfter: Date?

	init(origin: String, subject: String, notValidBefore: Date?, notValidAfter: Date?) {
		self.origin = origin
		self.subject = subject
		self.notValidBefore = notValidBefore
		self.notValidAfter = notValidAfter
	}

	init?(trust: SecTrust, committedURL: URL) {
		guard committedURL.scheme?.lowercased() == "https",
		      let origin = BrowserSiteOrigin.canonical(for: committedURL),
		      let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
		      let leaf = certificates.first,
		      let certificateSubject = SecCertificateCopySubjectSummary(leaf) as String?
		else { return nil }

		let subject = certificateSubject.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !subject.isEmpty else { return nil }

		self.init(
			origin: origin,
			subject: String(subject.prefix(512)),
			notValidBefore: SecCertificateCopyNotValidBeforeDate(leaf) as Date?,
			notValidAfter: SecCertificateCopyNotValidAfterDate(leaf) as Date?
		)
	}
}

nonisolated struct BrowserSecurityPresentation: Equatable, Sendable {
	let committedOrigin: String?
	let committedState: BrowserConnectionState
	let isNavigating: Bool
	let isFailure: Bool
	let failedOrigin: String?
	let certificate: BrowserServerCertificateSummary?

	init(
		committedURL: URL?,
		hasOnlySecureContent: Bool?,
		isNavigating: Bool,
		isFailure: Bool,
		failedURL: URL?,
		certificate: BrowserServerCertificateSummary?
	) {
		committedOrigin = committedURL.flatMap(BrowserSiteOrigin.canonical(for:))
		self.isNavigating = isNavigating
		self.isFailure = isFailure
		failedOrigin = failedURL.flatMap(BrowserSiteOrigin.canonical(for:))
		self.certificate = certificate?.origin == committedOrigin ? certificate : nil

		guard let committedURL else {
			committedState = .noPage
			return
		}
		if committedURL.isFileURL {
			committedState = .localFile
		} else if committedURL.scheme?.lowercased() == "https" {
			if let hasOnlySecureContent {
				committedState = hasOnlySecureContent ? .encrypted : .mixedContent
			} else {
				committedState = .unavailable
			}
		} else if committedURL.scheme?.lowercased() == "http" {
			committedState = .notSecure
		} else {
			committedState = .localContent
		}
	}

	var connectionState: BrowserConnectionState {
		if isFailure {
			return .connectionFailed
		}
		return isNavigating ? .navigating : committedState
	}

	static func canRefreshCommittedSnapshot(
		committedURL: URL?,
		webViewURL: URL?,
		committedDocumentID: Int?,
		currentDocumentID: Int,
		isNavigating: Bool,
		isFailure: Bool
	) -> Bool {
		guard !isNavigating,
		      !isFailure,
		      committedDocumentID == currentDocumentID,
		      let committedURL,
		      let webViewURL,
		      let committedOrigin = BrowserSiteOrigin.canonical(for: committedURL)
		else { return false }
		return BrowserSiteOrigin.canonical(for: webViewURL) == committedOrigin
	}
}
