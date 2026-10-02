import Foundation

@main
struct BrowserContentBlockingChecks {
	static func main() throws {
		let first = try BrowserContentBlockingRuleSource.validate(Data("""
		[
		  {
		    "trigger": { "url-filter": "^https://ads\\\\.example/" },
		    "action": { "type": "block" }
		  }
		]
		""".utf8))
		precondition(first.ruleCount == 1)
		precondition(first.identifier.hasPrefix("astra.user-content-rules."))
		precondition(BrowserContentBlockingRuleSource.lastGood(
			current: first,
			candidate: first,
			compiledIdentifier: nil
		) == first)

		let second = try BrowserContentBlockingRuleSource.validate(Data("""
		[
		  {
		    "trigger": { "url-filter": "^https://trackers\\\\.example/" },
		    "action": { "type": "block" }
		  }
		]
		""".utf8))
		precondition(BrowserContentBlockingRuleSource.lastGood(
			current: first,
			candidate: second,
			compiledIdentifier: second.identifier
		) == second)
		precondition(BrowserContentBlockingRuleSource.lastGood(
			current: first,
			candidate: second,
			compiledIdentifier: "different-compiled-list"
		) == first)

		precondition(throwsValidationError(Data("not json".utf8)))
		precondition(throwsValidationError(Data(repeating: 0x20, count: BrowserContentBlockingRuleSource.maximumBytes + 1)))
		precondition(throwsValidationError(Data("""
		[{"trigger":{"url-filter":".*"},"action":{"type":"redirect"}}]
		""".utf8)))

		precondition(BrowserContentBlockingRuleSource.shouldApply(enabled: true, hasCompiledList: true, isSiteException: false))
		precondition(!BrowserContentBlockingRuleSource.shouldApply(enabled: true, hasCompiledList: true, isSiteException: true))
		precondition(!BrowserContentBlockingRuleSource.shouldApply(enabled: false, hasCompiledList: true, isSiteException: false))
		precondition(!BrowserContentBlockingRuleSource.shouldApply(enabled: true, hasCompiledList: false, isSiteException: false))
	}

	private static func throwsValidationError(_ data: Data) -> Bool {
		errorOf { try BrowserContentBlockingRuleSource.validate(data) } != nil
	}

	private static func errorOf<T>(_ body: () throws -> T) -> (any Error)? {
		do {
			_ = try body()
			return nil
		} catch {
			return error
		}
	}
}
