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

	func request(for input: Input) throws -> BrowserAIRequest {
		try BrowserAIRequest(
			instructions: BrowserAIPrompts.chatTitle,
			prompt: String(decoding: JSONEncoder().encode([
				"userRequest": String(input.question.prefix(2000)),
				"assistantAnswer": String(input.answer.prefix(1500)),
			]), as: UTF8.self),
			maximumResponseTokens: 48
		)
	}

	func output(from text: String) throws -> String {
		let title = BrowserAIOutput.title(text)
		guard BrowserAIOutput.validLine(title, maximumWords: 7) else { throw BrowserAIError.emptyResponse }
		return title
	}
}
