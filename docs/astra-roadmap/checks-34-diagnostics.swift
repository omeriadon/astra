import Foundation

@main
struct DiagnosticChecks {
	@MainActor
	static func main() {
		precondition(BrowserDiagnosticReport.sanitizedCode("network.offline") == "network.offline")
		precondition(BrowserDiagnosticReport.sanitizedCode("web-content_terminated") == "web-content_terminated")
		precondition(BrowserDiagnosticReport.sanitizedCode("https://private.example/path?token=secret") == nil)
		precondition(BrowserDiagnosticReport.sanitizedCode("token=secret") == nil)
		precondition(BrowserDiagnosticReport.sanitizedCode(String(repeating: "a", count: 65)) == nil)

		let event = BrowserDiagnosticReport.Event(category: .navigationFailure, code: "offline", ageSeconds: 5)
		let report = BrowserDiagnosticReport(
			schema: BrowserDiagnosticReport.schemaVersion,
			applicationVersion: "0.1",
			applicationBuild: "1",
			operatingSystem: "Test OS",
			engine: "System WebKit",
			webKitVersion: "test",
			scope: "normal",
			tabCount: 10,
			hibernatedTabCount: 5,
			loadingTabCount: 1,
			navigationFailures: ["offline": 1],
			events: Array(repeating: event, count: BrowserDiagnosticReport.maximumEvents)
		)
		let encoded = report.encoded()
		precondition(encoded != nil)
		precondition(encoded!.count <= BrowserDiagnosticReport.maximumEncodedBytes)
		let text = String(decoding: encoded!, as: UTF8.self)
		for forbidden in ["http://", "https://", "?token=", "password", "pageContent", "formValue"] {
			precondition(!text.contains(forbidden))
		}
		let store = BrowserDiagnosticEventStore()
		store.record(.navigationFailure, code: "private.offline", isPrivate: true)
		store.record(.downloadFailure, code: "https://private.example/?token=secret", isPrivate: false)
		precondition(store.snapshot().isEmpty)
		for index in 0 ..< 100 {
			store.record(.navigationFailure, code: "failure-\(index)", isPrivate: false)
		}
		let events = store.snapshot()
		precondition(events.count == BrowserDiagnosticReport.maximumEvents)
		precondition(events.first?.code == "failure-36")
		precondition(events.last?.code == "failure-99")
		store.record(.extensionFailure, code: "private.extension", isPrivate: true)
		precondition(store.snapshot() == events)
		print("diagnostic checks passed")
	}
}
