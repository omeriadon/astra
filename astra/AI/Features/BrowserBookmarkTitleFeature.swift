import Foundation

@MainActor
struct BrowserBookmarkTitleFeature: BrowserAIFeature {
	var logName: String {
		"Clean Bookmark Titles"
	}

	var model: BrowserAIModel {
		BrowserAIFeatureID.bookmarkTitles.model
	}

	func request(for input: Bookmark) -> BrowserAIRequest {
		.init(instructions: BrowserAIPrompts.cleanTitle, prompt: "Current bookmark title: \(input.name)\nURL: \(BrowserAddress.withoutCredentials(input.url).absoluteString)", maximumResponseTokens: 64)
	}

	func output(from text: String) throws -> String {
		try BrowserTabTitleFeature().output(from: text)
	}
}
