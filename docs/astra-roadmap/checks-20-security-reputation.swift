import Foundation

@main
struct BrowserSecurityPresentationCheck {
	static func main() {
		let committedURL = URL(string: "https://example.test/account")!
		let certificate = BrowserServerCertificateSummary(
			origin: "https://example.test",
			subject: "example.test",
		notValidBefore: nil,
		notValidAfter: .now
		)
		let secure = BrowserSecurityPresentation(
			committedURL: committedURL,
			hasOnlySecureContent: true,
			isNavigating: false,
			isFailure: false,
			failedURL: nil,
			certificate: certificate
		)
		assert(secure.committedState == .encrypted)
		assert(secure.connectionState == .encrypted)
		assert(secure.committedOrigin == "https://example.test")
		assert(secure.certificate == certificate)
		assert(BrowserActiveCaptureStatus.current(isActive: false, isMuted: false, sampledDocumentID: nil, committedDocumentID: nil) == .unavailable)
		assert(BrowserActiveCaptureStatus.current(isActive: false, isMuted: false, sampledDocumentID: 3, committedDocumentID: 4) == .checking)
		assert(BrowserActiveCaptureStatus.current(isActive: false, isMuted: false, sampledDocumentID: 4, committedDocumentID: 4) == .inactive)
		assert(BrowserActiveCaptureStatus.current(isActive: true, isMuted: false, sampledDocumentID: 4, committedDocumentID: 4) == .active)
		assert(BrowserActiveCaptureStatus.current(isActive: false, isMuted: true, sampledDocumentID: 4, committedDocumentID: 4) == .muted)
		let mismatchedCertificate = BrowserSecurityPresentation(
			committedURL: committedURL,
			hasOnlySecureContent: true,
			isNavigating: false,
			isFailure: false,
			failedURL: nil,
			certificate: BrowserServerCertificateSummary(
				origin: "https://another.test",
				subject: "another.test",
				notValidBefore: nil,
				notValidAfter: nil
			)
		)
		assert(mismatchedCertificate.certificate == nil)

		let pendingHTTP = BrowserSecurityPresentation(
			committedURL: committedURL,
			hasOnlySecureContent: true,
			isNavigating: true,
			isFailure: false,
			failedURL: nil,
			certificate: certificate
		)
		assert(pendingHTTP.committedState == .encrypted)
		assert(pendingHTTP.connectionState == .navigating)

		let failedHTTP = BrowserSecurityPresentation(
			committedURL: committedURL,
			hasOnlySecureContent: true,
			isNavigating: false,
			isFailure: true,
			failedURL: URL(string: "http://untrusted.test/login")!,
			certificate: certificate
		)
		assert(failedHTTP.committedState == .encrypted)
		assert(failedHTTP.connectionState == .connectionFailed)
		assert(failedHTTP.committedOrigin == "https://example.test")
		assert(failedHTTP.failedOrigin == "http://untrusted.test")

		assert(BrowserSecurityPresentation(
			committedURL: committedURL,
			hasOnlySecureContent: nil,
			isNavigating: false,
			isFailure: false,
			failedURL: nil,
			certificate: nil
		).committedState == .unavailable)
		assert(BrowserSecurityPresentation(
			committedURL: committedURL,
			hasOnlySecureContent: false,
			isNavigating: false,
			isFailure: false,
			failedURL: nil,
			certificate: nil
		).committedState == .mixedContent)
		assert(BrowserSecurityPresentation(
			committedURL: URL(string: "http://example.test")!,
			hasOnlySecureContent: nil,
			isNavigating: false,
			isFailure: false,
			failedURL: nil,
			certificate: certificate
		).committedState == .notSecure)
		assert(BrowserSecurityPresentation(
			committedURL: URL(fileURLWithPath: "/tmp/page.html"),
			hasOnlySecureContent: nil,
			isNavigating: false,
			isFailure: false,
			failedURL: nil,
			certificate: nil
		).committedState == .localFile)
		assert(BrowserSecurityPresentation(
			committedURL: URL(string: "astra://settings")!,
			hasOnlySecureContent: nil,
			isNavigating: false,
			isFailure: false,
			failedURL: nil,
			certificate: nil
		).committedState == .localContent)

		assert(!BrowserSecurityPresentation.canRefreshCommittedSnapshot(
			committedURL: committedURL,
			webViewURL: URL(string: "https://untrusted.test"),
			committedDocumentID: 4,
			currentDocumentID: 4,
			isNavigating: false,
			isFailure: false
		))
		assert(!BrowserSecurityPresentation.canRefreshCommittedSnapshot(
			committedURL: committedURL,
			webViewURL: committedURL,
			committedDocumentID: 4,
			currentDocumentID: 5,
			isNavigating: false,
			isFailure: false
		))
		assert(!BrowserSecurityPresentation.canRefreshCommittedSnapshot(
			committedURL: committedURL,
			webViewURL: committedURL,
			committedDocumentID: 4,
			currentDocumentID: 4,
			isNavigating: true,
			isFailure: false
		))
		assert(!BrowserSecurityPresentation.canRefreshCommittedSnapshot(
			committedURL: committedURL,
			webViewURL: committedURL,
			committedDocumentID: 4,
			currentDocumentID: 4,
			isNavigating: false,
			isFailure: true
		))
		assert(BrowserSecurityPresentation.canRefreshCommittedSnapshot(
			committedURL: committedURL,
			webViewURL: URL(string: "https://example.test/redirected-path"),
			committedDocumentID: 4,
			currentDocumentID: 4,
			isNavigating: false,
			isFailure: false
		))
		let failedFile = BrowserSecurityPresentation(
			committedURL: committedURL,
			hasOnlySecureContent: true,
			isNavigating: false,
			isFailure: true,
			failedURL: URL(fileURLWithPath: "/tmp/missing.html"),
			certificate: certificate
		)
		assert(failedFile.connectionState == .connectionFailed)
		assert(failedFile.failedOrigin == nil)
	}
}
