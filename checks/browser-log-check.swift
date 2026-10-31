import Foundation

@main
struct BrowserLogCheck {
	static func main() {
		precondition(BrowserLog.verboseEnabled == BrowserLog.isEnabled(.trace))
		precondition(BrowserLog.verboseEnabled == BrowserLog.isEnabled(.debug))
		precondition(BrowserLog.verboseEnabled == BrowserLog.isEnabled(.info))
		precondition(BrowserLog.verboseEnabled == BrowserLog.isEnabled(.notice))
		precondition(BrowserLog.isEnabled(.warning))
		precondition(BrowserLog.isEnabled(.error))
		var evaluations = 0
		BrowserLog.info(.diagnostics, "test.disabled", ({
			evaluations += 1
			return "quiet"
		}()), metadata: ({
			evaluations += 1
			return ["evaluated": "true"]
		}()))
		precondition(evaluations == (BrowserLog.verboseEnabled ? 2 : 0))
		BrowserLog.warning(.diagnostics, "test.enabled", ({
			evaluations += 1
			return "visible"
		}()))
		precondition(evaluations == (BrowserLog.verboseEnabled ? 3 : 1))

		BrowserLog.syncEvent("sync.check", metadata: ["documents": "0", "low_power": "false"])
		let phase = BrowserLog.beginSyncPhase("validation")
		BrowserLog.endSyncPhase("validation", phase)

		let timingEvaluations = evaluations
		BrowserLog.duration(.performance, "test.timing", since: 0, metadata: ({
			evaluations += 1
			return ["evaluated": "true"]
		}()))
		precondition(evaluations == timingEvaluations + (BrowserLog.verboseEnabled ? 1 : 0))

		let underlying = NSError(
			domain: "NSCocoaErrorDomain",
			code: 513,
			userInfo: [NSUnderlyingErrorKey: NSError(domain: "URLSession", code: -1009)]
		)
		let formatted = BrowserLog.errorDescription(underlying)
		precondition(formatted.contains("NSCocoaErrorDomain:513"))
		precondition(formatted.contains("URLSession:-1009"))
		precondition(formatted.contains("userInfoKeys") || formatted.contains("userInfoCount"))
		let decoding = DecodingError.dataCorrupted(.init(
			codingPath: [],
			debugDescription: "Bad document",
			underlyingError: NSError(domain: "decoder-cause", code: 42)
		))
		let decodingDescription = BrowserLog.errorDescription(decoding)
		precondition(decodingDescription.contains("decoding=dataCorrupted"))
		precondition(decodingDescription.contains("decoder-cause:42"))

		let transport = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [
			NSURLErrorFailingURLErrorKey: URL(string: "https://example.test/private?token=secret-token")!,
			NSLocalizedDescriptionKey: "Authorization: Bearer secret-bearer password=secret-password",
		])
		let transportDescription = BrowserLog.errorDescription(transport)
		precondition(transportDescription.contains("example.test"))
		precondition(!transportDescription.contains("secret-token"))
		precondition(!transportDescription.contains("secret-bearer"))
		precondition(!transportDescription.contains("secret-password"))
		precondition(transportDescription.contains("reason="))

		let longError = NSError(domain: "long", code: 1, userInfo: [
			NSLocalizedDescriptionKey: String(repeating: "large ", count: 10000),
		])
		precondition(BrowserLog.errorDescription(longError).count <= 4096)
		let keychain = BrowserLog.errorDescription(BrowserSessionStoreError.keychain(-25308))
		precondition(keychain.contains("com.omeriadon.astra.keychain:-25308"))
		print("browser-log checks passed")
	}
}
