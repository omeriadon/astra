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
		let fixtureURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("astra-content-rules-check-\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: fixtureURL) }
		let fixtureData = Data("[]".utf8)
		try fixtureData.write(to: fixtureURL, options: .atomic)
		let readFixture = try BrowserContentBlockingRuleSource.readBounded(from: fixtureURL)
		precondition(readFixture == fixtureData)
		try Data(repeating: 0x20, count: BrowserContentBlockingRuleSource.maximumBytes + 1)
			.write(to: fixtureURL, options: .atomic)
		precondition(throwsReadError(fixtureURL))

		precondition(BrowserContentBlockingRuleSource.shouldApply(enabled: true, hasCompiledList: true, isSiteException: false))
		precondition(!BrowserContentBlockingRuleSource.shouldApply(enabled: true, hasCompiledList: true, isSiteException: true))
		precondition(!BrowserContentBlockingRuleSource.shouldApply(enabled: false, hasCompiledList: true, isSiteException: false))
		precondition(!BrowserContentBlockingRuleSource.shouldApply(enabled: true, hasCompiledList: false, isSiteException: false))
		let currentOrigin = "https://source.example"
		let destinationOrigin = "https://exception.example"
		for disposition in [BrowserContentBlockingRuleSource.NavigationDisposition.cancel, .download] {
			precondition(BrowserContentBlockingRuleSource.originAfterNavigationDecision(
				isMainFrame: true,
				disposition: disposition,
				currentOrigin: currentOrigin,
				destinationOrigin: destinationOrigin
			) == currentOrigin)
		}
		precondition(BrowserContentBlockingRuleSource.originAfterNavigationDecision(
			isMainFrame: true,
			disposition: .redirect,
			currentOrigin: currentOrigin,
			destinationOrigin: nil
		) == nil)
		precondition(BrowserContentBlockingRuleSource.originAfterNavigationDecision(
			isMainFrame: true,
			disposition: .allow,
			currentOrigin: currentOrigin,
			destinationOrigin: destinationOrigin
		) == destinationOrigin)
		precondition(BrowserContentBlockingRuleSource.originAfterNavigationDecision(
			isMainFrame: true,
			disposition: .allow,
			currentOrigin: currentOrigin,
			destinationOrigin: nil
		) == nil)
		precondition(BrowserContentBlockingRuleSource.originAfterNavigationDecision(
			isMainFrame: false,
			disposition: .allow,
			currentOrigin: currentOrigin,
			destinationOrigin: destinationOrigin
		) == currentOrigin)

		let legacySitePreferences = Data("""
		{"version":1,"entries":{"https://example.com":{"contentMode":"desktop","customUserAgent":null}}}
		""".utf8)
		let decodedLegacy = BrowserLocalSitePreferencesDocument.decodeSupported(legacySitePreferences)
		precondition(decodedLegacy?.entries["https://example.com"]?.nativeContentBlockingDisabled == nil)

		let sitePreferences = BrowserLocalSitePreferencesDocument(entries: [
			"https://example.com": BrowserLocalSitePreference(
				contentMode: nil,
				customUserAgent: nil,
				nativeContentBlockingDisabled: true
			),
		])
		let encoded = sitePreferences.encoded()
		let decoded = encoded.flatMap(BrowserLocalSitePreferencesDocument.decodeSupported)
		precondition(decoded?.entries["https://example.com"]?.nativeContentBlockingDisabled == true)
		precondition(decoded?.entries["https://example.com"]?.isEmpty == false)
	}

	private static func throwsValidationError(_ data: Data) -> Bool {
		errorOf { try BrowserContentBlockingRuleSource.validate(data) } != nil
	}

	private static func throwsReadError(_ url: URL) -> Bool {
		errorOf { try BrowserContentBlockingRuleSource.readBounded(from: url) } != nil
	}

	private static func errorOf(_ body: () throws -> some Any) -> (any Error)? {
		do {
			_ = try body()
			return nil
		} catch {
			return error
		}
	}
}
