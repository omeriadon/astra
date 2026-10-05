import Foundation
import FoundationModels

nonisolated enum BrowserAIModel: Equatable, Sendable {
	case appleIntelligence
	case openRouter(modelID: String = "openai/gpt-4o-mini")
}

nonisolated struct BrowserAIRequest: Codable, Sendable {
	let instructions: String
	let prompt: String
	let maximumResponseTokens: Int
}

nonisolated struct BrowserAIResponse: Codable, Sendable {
	let text: String
}

nonisolated struct BrowserAICloudRequest: Encodable, Sendable {
	let modelID: String
	let instructions: String
	let prompt: String
	let maximumResponseTokens: Int
}

/// Features own prompts and output validation; the manager owns provider execution.
@MainActor
protocol BrowserAIFeature {
	associatedtype Input
	associatedtype Output

	var model: BrowserAIModel { get }
	func request(for input: Input) throws -> BrowserAIRequest
	func output(from text: String) throws -> Output
}

@MainActor
final class BrowserAI {
	static let shared = BrowserAI()

	func perform<Feature: BrowserAIFeature>(
		_ feature: Feature,
		input: Feature.Input,
		model: BrowserAIModel? = nil
	) async throws -> Feature.Output {
		let text = try await generate(feature.request(for: input), model: model ?? feature.model)
		return try feature.output(from: text)
	}

	/// Each call has its own session. There is no shared transcript or automatic cloud fallback.
	func generate(_ request: BrowserAIRequest, model: BrowserAIModel = .appleIntelligence) async throws -> String {
		try Task.checkCancellation()
		let generation = try BrowserSync.shared.requireAIAuthentication()
		try validate(request)

		let text: String
		switch model {
			case .appleIntelligence:
				guard SystemLanguageModel.default.isAvailable else {
					throw BrowserAIError.appleIntelligenceUnavailable
				}
				let session = LanguageModelSession(instructions: request.instructions)
				let response = try await session.respond(
					to: request.prompt,
					options: GenerationOptions(maximumResponseTokens: request.maximumResponseTokens)
				)
				text = response.content
			case let .openRouter(modelID):
				let response = try await BrowserSync.shared.generateAI(cloudRequest(request, modelID: modelID))
				text = response.text
		}
		try Task.checkCancellation()
		try BrowserSync.shared.validateAIAuthentication(generation)
		try validateOutput(text)
		return text
	}

	/// Snapshots are cumulative display text. Only the returned output has feature validation.
	func performStreaming<Feature: BrowserAIFeature>(
		_ feature: Feature,
		input: Feature.Input,
		model: BrowserAIModel? = nil,
		onSnapshot: @MainActor (String) -> Void
	) async throws -> Feature.Output {
		let text = try await stream(
			feature.request(for: input),
			model: model ?? feature.model,
			onSnapshot: onSnapshot
		)
		return try feature.output(from: text)
	}

	func stream(
		_ request: BrowserAIRequest,
		model: BrowserAIModel = .appleIntelligence,
		onSnapshot: @MainActor (String) -> Void
	) async throws -> String {
		try Task.checkCancellation()
		let generation = try BrowserSync.shared.requireAIAuthentication()
		try validate(request)
		let text: String
		switch model {
			case .appleIntelligence:
				guard SystemLanguageModel.default.isAvailable else {
					throw BrowserAIError.appleIntelligenceUnavailable
				}
				let session = LanguageModelSession(instructions: request.instructions)
				let snapshots = session.streamResponse(
					to: request.prompt,
					options: GenerationOptions(maximumResponseTokens: request.maximumResponseTokens)
				)
				var latest = ""
				for try await snapshot in snapshots {
					try Task.checkCancellation()
					try BrowserSync.shared.validateAIAuthentication(generation)
					latest = snapshot.content
					onSnapshot(latest)
				}
				text = latest
			case let .openRouter(modelID):
				text = try await BrowserSync.shared.streamAI(
					cloudRequest(request, modelID: modelID),
					onSnapshot: onSnapshot
				)
		}
		try Task.checkCancellation()
		try BrowserSync.shared.validateAIAuthentication(generation)
		try validateOutput(text)
		return text
	}

	private func validate(_ request: BrowserAIRequest) throws {
		guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
		      request.instructions.utf8.count + request.prompt.utf8.count <= 32768,
		      (1 ... 2048).contains(request.maximumResponseTokens)
		else {
			throw BrowserAIError.invalidRequest
		}
	}

	private func cloudRequest(_ request: BrowserAIRequest, modelID: String) throws -> BrowserAICloudRequest {
		guard !modelID.isEmpty, modelID.utf8.count <= 200 else {
			throw BrowserAIError.invalidRequest
		}
		return BrowserAICloudRequest(
			modelID: modelID,
			instructions: request.instructions,
			prompt: request.prompt,
			maximumResponseTokens: request.maximumResponseTokens
		)
	}

	private func validateOutput(_ text: String) throws {
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw BrowserAIError.emptyResponse
		}
	}
}

nonisolated enum BrowserAIError: LocalizedError {
	case signInRequired
	case appleIntelligenceUnavailable
	case invalidRequest
	case emptyResponse
	case invalidStream

	var errorDescription: String? {
		switch self {
			case .signInRequired:
				"Sign in to Astra to use AI features."
			case .appleIntelligenceUnavailable:
				"Apple Intelligence is unavailable on this device."
			case .invalidRequest:
				"The AI request exceeds the supported limits or is empty."
			case .emptyResponse:
				"The AI model did not return usable text."
			case .invalidStream:
				"AI generation failed or the response stream ended before completion."
		}
	}
}
