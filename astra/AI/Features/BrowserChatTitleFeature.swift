import Foundation

@MainActor
struct BrowserChatTitleFeature: BrowserAIFeature {
	var logName: String {
		"Chat Titles"
	}

	struct Input {
		let question: String
		let answer: String
	}

	var model: BrowserAIModel {
		BrowserAIFeatureID.chat.model
	}

	func request(for input: Input) -> BrowserAIRequest {
		BrowserAIRequest(
			instructions: BrowserAIPrompts.chatTitle,
			prompt: "User: \(String(input.question.prefix(2000)))\nAssistant: \(String(input.answer.prefix(6000)))",
			maximumResponseTokens: 48
		)
	}

	func output(from text: String) throws -> String {
		let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard BrowserAIOutput.validLine(title, maximumWords: 7) else { throw BrowserAIError.emptyResponse }
		return title
	}
}
