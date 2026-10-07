import Defaults
import Foundation
import FoundationModels

nonisolated enum BrowserAIModel: Equatable, Sendable {
	case appleIntelligence
	case privateCloudCompute
	case codex(modelID: String)
	case claude(modelID: String)
	case openRouter(modelID: String = "inclusionai/ling-3.1-flash")
}

nonisolated struct BrowserAIRequest: Codable, Sendable {
	let instructions: String
	let prompt: String
	let maximumResponseTokens: Int
	var images: [BrowserAIImage]? = nil
	var reasoningEffort: String? = nil
	var webSearch: Bool? = nil
	var files: [BrowserAIFile]? = nil
}

nonisolated struct BrowserAIResponse: Codable, Sendable {
	let text: String
}

nonisolated struct BrowserAICloudRequest: Encodable, Sendable {
	let modelID: String
	let instructions: String
	let prompt: String
	let maximumResponseTokens: Int
	let images: [BrowserAIImage]?
	let webSearch: Bool?
}

/// Features own prompts and output validation; the manager owns provider execution.
@MainActor
protocol BrowserAIFeature {
	associatedtype Input
	associatedtype Output

	var model: BrowserAIModel { get }
	var logName: String { get }
	func request(for input: Input) throws -> BrowserAIRequest
	func output(from text: String) throws -> Output
}

extension BrowserAIFeature {
	var logName: String {
		String(describing: Self.self)
	}
}

@MainActor
final class BrowserAI {
	static let shared = BrowserAI()

	func perform<Feature: BrowserAIFeature>(
		_ feature: Feature,
		input: Feature.Input,
		model: BrowserAIModel? = nil
	) async throws -> Feature.Output {
		let request = try feature.request(for: input)
		let selected = model ?? BrowserAISettings.effectiveModel(feature.model)
		return try await logged(request, model: selected, feature: feature.logName, mode: "single") {
			let text = try await generateResponse(request, model: selected)
			return try (feature.output(from: text), text.utf8.count)
		}
	}

	/// Each call has its own session. There is no shared transcript or automatic cloud fallback.
	func generate(_ request: BrowserAIRequest, model: BrowserAIModel = .appleIntelligence) async throws -> String {
		let selected = BrowserAISettings.effectiveModel(model)
		return try await logged(request, model: selected, feature: "AI Request", mode: "single") {
			let text = try await generateResponse(request, model: selected)
			return (text, text.utf8.count)
		}
	}

	private func generateResponse(_ request: BrowserAIRequest, model: BrowserAIModel) async throws -> String {
		try Task.checkCancellation()
		try requireEnabled()
		let generation = try authentication(for: model)
		try validate(request)
		try validateFiles(request, model: model)
		if request.images?.isEmpty == false, model == .appleIntelligence || model == .privateCloudCompute {
			throw BrowserAIError.attachmentsUnsupported
		}

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
			case .privateCloudCompute:
				text = try await pccSession(instructions: request.instructions).respond(
					to: request.prompt,
					options: GenerationOptions(maximumResponseTokens: request.maximumResponseTokens),
					contextOptions: ContextOptions(reasoningLevel: .light)
				).content
			case .codex, .claude:
				text = try await BrowserAICLI.generate(request, model: model)
			case let .openRouter(modelID):
				let response = try await BrowserSync.shared.generateAI(cloudRequest(request, modelID: modelID))
				text = response.text
		}
		try Task.checkCancellation()
		try requireEnabled()
		if let generation {
			try BrowserSync.shared.validateAIAuthentication(generation)
		}
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
		let request = try feature.request(for: input)
		let selected = model ?? BrowserAISettings.effectiveModel(feature.model)
		return try await logged(request, model: selected, feature: feature.logName, mode: "stream") {
			let text = try await streamResponse(request, model: selected, onSnapshot: onSnapshot)
			return try (feature.output(from: text), text.utf8.count)
		}
	}

	func stream(
		_ request: BrowserAIRequest,
		model: BrowserAIModel = .appleIntelligence,
		onSnapshot: @MainActor (String) -> Void
	) async throws -> String {
		let selected = BrowserAISettings.effectiveModel(model)
		return try await logged(request, model: selected, feature: "AI Request", mode: "stream") {
			let text = try await streamResponse(request, model: selected, onSnapshot: onSnapshot)
			return (text, text.utf8.count)
		}
	}

	private func streamResponse(
		_ request: BrowserAIRequest,
		model: BrowserAIModel,
		onSnapshot: @MainActor (String) -> Void
	) async throws -> String {
		try Task.checkCancellation()
		try requireEnabled()
		let generation = try authentication(for: model)
		try validate(request)
		try validateFiles(request, model: model)
		if request.images?.isEmpty == false, model == .appleIntelligence || model == .privateCloudCompute {
			throw BrowserAIError.attachmentsUnsupported
		}
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
					try requireEnabled()
					if let generation {
						try BrowserSync.shared.validateAIAuthentication(generation)
					}
					latest = snapshot.content
					onSnapshot(latest)
				}
				text = latest
			case .privateCloudCompute:
				let session = try pccSession(instructions: request.instructions)
				var latest = ""
				for try await snapshot in session.streamResponse(
					to: request.prompt,
					options: GenerationOptions(maximumResponseTokens: request.maximumResponseTokens),
					contextOptions: ContextOptions(reasoningLevel: .light)
				) {
					try Task.checkCancellation()
					try requireEnabled()
					if let generation {
						try BrowserSync.shared.validateAIAuthentication(generation)
					}
					latest = snapshot.content
					onSnapshot(latest)
				}
				text = latest
			case .codex, .claude:
				text = try await BrowserAICLI.generate(request, model: model) { snapshot in
					if Defaults[.aiFeaturesEnabled] {
						onSnapshot(snapshot)
					}
				}
			case let .openRouter(modelID):
				text = try await BrowserSync.shared.streamAI(
					cloudRequest(request, modelID: modelID),
					onSnapshot: { snapshot in
						if Defaults[.aiFeaturesEnabled] {
							onSnapshot(snapshot)
						}
					}
				)
		}
		try Task.checkCancellation()
		try requireEnabled()
		if let generation {
			try BrowserSync.shared.validateAIAuthentication(generation)
		}
		try validateOutput(text)
		return text
	}

	func checkAccess(for model: BrowserAIModel, feature: String = "AI Request") async throws {
		BrowserLog.debug(.ai, "ai.access-check", metadata: ["provider": logProvider(model), "feature": BrowserLog.value(feature)])
		let selected = BrowserAISettings.effectiveModel(model)
		do {
			try requireEnabled()
			_ = try authentication(for: selected)
		} catch {
			await BrowserAIUsageLog.shared.record(id: UUID(), feature: feature, provider: logProvider(selected), event: "blocked", details: "phase=preflight error=\(logError(error))")
			throw error
		}
	}

	private func requireEnabled() throws {
		guard Defaults[.aiFeaturesEnabled] else { throw BrowserAIError.disabled }
	}

	private func logged<Output>(
		_ request: BrowserAIRequest,
		model: BrowserAIModel,
		feature: String,
		mode: String,
		operation: @MainActor () async throws -> (Output, Int)
	) async throws -> Output {
		let id = UUID()
		let started = ContinuousClock.now
		let provider = logProvider(model)
		BrowserLog.info(.ai, "ai.request", metadata: ["id": BrowserLog.id(id), "feature": BrowserLog.value(feature), "provider": provider, "mode": mode, "input_bytes": String(request.instructions.utf8.count + request.prompt.utf8.count), "images": String(request.images?.count ?? 0)])
		#if DEBUG
			BrowserLog.debug(.ai, "ai.prompt.debug", metadata: ["id": BrowserLog.id(id), "instructions": BrowserLog.value(request.instructions), "prompt": BrowserLog.value(request.prompt)])
		#endif
		await BrowserAIUsageLog.shared.record(id: id, feature: feature, provider: provider, event: "request", details: "mode=\(mode) input_utf8_bytes=\(request.instructions.utf8.count + request.prompt.utf8.count) images=\(request.images?.count ?? 0)")
		do {
			try requireEnabled()
			let (output, bytes) = try await operation()
			BrowserLog.info(.ai, "ai.success", metadata: ["id": BrowserLog.id(id), "feature": BrowserLog.value(feature), "provider": provider, "output_bytes": String(bytes), "elapsed_ms": String(elapsedMilliseconds(since: started))])
			await BrowserAIUsageLog.shared.record(id: id, feature: feature, provider: provider, event: "success", details: "output_utf8_bytes=\(bytes) elapsed_ms=\(elapsedMilliseconds(since: started))")
			return output
		} catch {
			let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
			if cancelled {
				BrowserLog.debug(.ai, "ai.cancelled", metadata: ["id": BrowserLog.id(id), "feature": BrowserLog.value(feature), "provider": provider])
			} else {
				BrowserLog.error(.ai, "ai.failed", metadata: ["id": BrowserLog.id(id), "feature": BrowserLog.value(feature), "provider": provider, "error": BrowserLog.errorDescription(error), "elapsed_ms": String(elapsedMilliseconds(since: started))])
			}
			await BrowserAIUsageLog.shared.record(id: id, feature: feature, provider: provider, event: cancelled ? "cancelled" : "failed", details: "error=\(logError(error)) elapsed_ms=\(elapsedMilliseconds(since: started))")
			throw error
		}
	}

	private func logProvider(_ model: BrowserAIModel) -> String {
		switch model {
			case .codex: "Codex"
			case .claude: "Claude"
			default: "Default"
		}
	}

	private func logError(_ error: Error) -> String {
		if let error = error as? BrowserAIError {
			return String(String(describing: error).prefix { $0 != "(" })
		}
		let error = error as NSError
		return "\(error.domain):\(error.code)"
	}

	private func elapsedMilliseconds(since started: ContinuousClock.Instant) -> Int64 {
		let duration = started.duration(to: .now).components
		return duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000
	}

	private func authentication(for model: BrowserAIModel) throws -> UInt64? {
		switch model {
			case .openRouter: try BrowserSync.shared.requireAIAuthentication()
			default: nil
		}
	}

	private func pccSession(instructions: String) throws -> LanguageModelSession {
		let model = PrivateCloudComputeLanguageModel()
		guard model.isAvailable else { throw BrowserAIError.privateCloudComputeUnavailable }
		return LanguageModelSession(model: model, instructions: instructions)
	}

	private func validate(_ request: BrowserAIRequest) throws {
		guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
		      request.instructions.utf8.count <= 32768,

		      (1 ... 2048).contains(request.maximumResponseTokens)
		else {
			throw BrowserAIError.invalidRequest
		}
	}

	private func validateFiles(_ request: BrowserAIRequest, model: BrowserAIModel) throws {
		guard request.files?.contains(where: { $0.hasExtractedText != true }) == true else { return }
		switch model {
			case .codex, .claude: break
			default: throw BrowserAIError.fileProviderRequired
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
			maximumResponseTokens: request.maximumResponseTokens,
			images: request.images,
			webSearch: request.webSearch
		)
	}

	private func validateOutput(_ text: String) throws {
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw BrowserAIError.emptyResponse
		}
	}
}

nonisolated enum BrowserAIError: LocalizedError {
	case toolDenied
	case toolLimit
	case disabled
	case commandMissing(String)
	case commandFailed(String, String)
	case commandTimedOut(String)
	case server(Int, String?)
	case chatStorage
	case attachmentTooLarge
	case attachmentUnreadable(String)
	case attachmentsUnsupported
	case fileProviderRequired
	case privateCloudComputeUnavailable
	case cliUnavailable
	case pageUnavailable
	case signInRequired
	case appleIntelligenceUnavailable
	case invalidRequest
	case emptyResponse
	case invalidResponse(String)
	case invalidStream

	static func http(_ status: Int, data: Data) -> Self {
		let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		let reason = (object?["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
		return .server(status, reason.flatMap { $0.isEmpty ? nil : String($0.prefix(300)) })
	}

	var errorDescription: String? {
		switch self {
			case .toolLimit:
				"The assistant reached its browser-action limit for this turn. Completed actions are retained; send another message to continue."
			case .toolDenied:
				"This browser action is disabled, unavailable in this space, or not allowed in private browsing."
			case .disabled:
				"AI features are disabled. Turn on All AI Features in AI settings to use them."
			case let .commandMissing(provider):
				"\(provider) is not installed or could not be found. Install its command-line tool. No Astra sign-in is required."
			case let .commandFailed(provider, reason):
				"\(provider): \(reason) No Astra sign-in is required."
			case let .commandTimedOut(provider):
				"\(provider) did not finish within three minutes. Try again with less context."
			case let .server(status, reason):
				switch status {
					case 401: "Sign in to Astra in Account & Sync to use Default AI. Codex and Claude do not require an Astra account."
					case 413: "The attached files and page context exceed the server’s request size limit. Remove an attachment or linked page."
					case 429: reason.map { "Default AI: \($0)" } ?? "The AI provider or account usage limit has been reached. Try again later."
					case 503: "Default AI is temporarily unavailable or is not configured on the server."
					default: reason.map { "Default AI: \($0) (HTTP \(status))." } ?? "Default AI returned HTTP \(status). Try again."
				}
			case .chatStorage:
				"The chat could not be saved. Check available disk space and folder permissions. Its open transcript has been preserved."
			case .attachmentTooLarge:
				"The image exceeds the provider’s supported image size."
			case let .attachmentUnreadable(name):
				"Could not read \(name). Check the file’s access permissions and retry."
			case .fileProviderRequired:
				"This provider cannot inspect the original file contents. Codex or Claude can access the attached file through the installed command. The file remains attached."
			case .attachmentsUnsupported:
				"The selected AI provider does not accept images. Use Default, Codex, or Claude for this chat."
			case .privateCloudComputeUnavailable:
				"Private Cloud Compute is unavailable. Check Apple Intelligence and the app’s PCC entitlement."
			case .cliUnavailable:
				"The selected AI command is unavailable or failed. Install it and sign in, then retry."
			case .pageUnavailable:
				"This page has no readable text, changed during extraction, or could not be loaded."
			case .signInRequired:
				"Sign in to Astra in Account & Sync to use Default AI. Codex and Claude do not require an Astra account."
			case .appleIntelligenceUnavailable:
				"Apple Intelligence is unavailable on this device."
			case .invalidRequest:
				"The AI request exceeds the supported limits or is empty."
			case let .invalidResponse(reason):
				"The AI response could not be applied: \(reason)"
			case .emptyResponse:
				"The AI model did not return usable text."
			case .invalidStream:
				"AI generation failed or the response stream ended before completion."
		}
	}
}
