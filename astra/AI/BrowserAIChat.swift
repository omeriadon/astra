import Defaults
import Foundation
import Observation

@MainActor
@Observable
final class BrowserAIChat {
	nonisolated struct Message: Codable, Identifiable, Sendable {
		var id = UUID()
		let isUser: Bool
		let text: String
		var attachments: [BrowserAIAttachment] = []
	}

	private(set) var id = UUID()
	private(set) var title = "New Chat"
	private var titleIsGenerated = false
	var attachments: [BrowserAIAttachment] = []
	var pendingPages: [BrowserAIPageText] = []
	var isImporting = false
	var selectedProvider = ""
	var selectedModelID = ""
	var selectedReasoning = "low"
	var draft = ""
	var linkedTabIDs: [UUID] = []
	private(set) var messages: [Message] = []
	private(set) var preview = ""
	private(set) var error: String?
	private(set) var canRetry = false
	private(set) var isResponding = false
	private(set) var activity = "Reading and Answering"
	@ObservationIgnored private var pages: [UUID: BrowserAIPageText] = [:]
	/// A failed stream can have already issued browser actions before the
	/// provider returns an error. Do not offer to replay that turn blindly.
	@ObservationIgnored private var attemptedBrowserAction = false

	var effectiveModel: BrowserAIModel {
		let provider = Defaults[.aiProvider]
		if provider == "codex" {
			return .codex(modelID: selectedProvider == provider && !selectedModelID.isEmpty ? selectedModelID : Defaults[.aiCodexModel])
		}
		if provider == "claude" {
			return .claude(modelID: selectedProvider == provider && !selectedModelID.isEmpty ? selectedModelID : Defaults[.aiClaudeModel])
		}
		return BrowserAIFeatureID.chat.model
	}

	func includeCurrentTab(in browser: Browser) {
		guard browser.canShowAISidebar, let tab = browser.selectedTab, !linkedTabIDs.contains(tab.id) else { return }
		linkedTabIDs.append(tab.id)
	}

	func availableTabs(in browser: Browser) -> [BrowserTab] {
		var seen = Set<UUID>()
		return (BrowserWindowRegistry.shared.openBrowsers.filter { !$0.isPrivate && $0.session === browser.session }.flatMap(\.tabs) + browser.tabs)
			.filter { $0.internalPage == nil && $0.currentURL != nil && seen.insert($0.id).inserted }
	}

	var mentionQuery: String? {
		guard let at = draft.lastIndex(of: "@"), at == draft.startIndex || draft[draft.index(before: at)].isWhitespace else { return nil }
		let query = String(draft[draft.index(after: at)...])
		return query.contains("\n") ? nil : query
	}

	func suggestions(in browser: Browser) -> [BrowserTab] {
		guard let query = mentionQuery else { return [] }
		return browser.visibleTabs.filter {
			$0.internalPage == nil && $0.currentURL != nil && !linkedTabIDs.contains($0.id)
				&& (query.isEmpty || $0.title.range(of: query, options: .caseInsensitive) != nil)
		}
	}

	func link(_ tab: BrowserTab) {
		if !linkedTabIDs.contains(tab.id) {
			linkedTabIDs.append(tab.id)
		}
		if mentionQuery != nil, let at = draft.lastIndex(of: "@") {
			draft.removeSubrange(at...)
		}
	}

	func addPage(_ page: BrowserAIPageText) {
		guard !isResponding else { return }
		pendingPages.removeAll { $0.url == page.url }
		pendingPages.append(page)
	}

	func importFiles(_ urls: [URL]) async {
		guard !isResponding, !isImporting else { return }
		isImporting = true
		defer { isImporting = false }
		do {
			var imported: [BrowserAIAttachment] = []
			for url in urls {
				try await imported.append(BrowserAIAttachment.read(url))
			}
			let images = (attachments + imported).compactMap(\.image)
			guard images.count <= 8, images.reduce(0, { $0 + $1.data.count }) <= 10 * 1024 * 1024 else { throw BrowserAIError.attachmentTooLarge }
			attachments += imported
			error = nil
		} catch {
			if !Task.isCancelled {
				self.error = error.localizedDescription
			}
		}
	}

	func reportImportError(_ error: Error) {
		self.error = "The selected files could not be opened: \(error.localizedDescription)"
	}

	func select(_ conversation: BrowserAIConversation) {
		guard !isResponding, !isImporting else { return }
		id = conversation.id
		title = conversation.title
		titleIsGenerated = conversation.titleIsGenerated
		messages = conversation.messages
		pages = conversation.pages
		selectedProvider = conversation.provider ?? ""
		selectedModelID = conversation.modelID ?? ""
		selectedReasoning = conversation.reasoning ?? "low"
		draft = ""
		attachments = []
		pendingPages = []
		linkedTabIDs = []
		preview = ""
		error = nil
		canRetry = false
		attemptedBrowserAction = false
	}

	func send(in browser: Browser) async {
		guard !browser.isPrivate, !isResponding, !isImporting else { return }
		let entered = draft.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !entered.isEmpty || !attachments.isEmpty || !pendingPages.isEmpty else { return }
		let question = entered.isEmpty ? "Describe and explain the attached context." : entered
		let newAttachments = attachments
		let conversationID = id
		let spaceID = browser.selectedSpace.id
		let model = effectiveModel
		let sendID = UUID()
		let started = BrowserLog.clock()
		var answerCommitted = false
		attemptedBrowserAction = false
		isResponding = true
		error = nil
		canRetry = false
		preview = ""
		activity = "Checking AI Access"
		BrowserLog.info(.ai, "ai.chat.send", metadata: [
			"id": BrowserLog.id(sendID), "conversation": BrowserLog.id(conversationID),
			"provider": BrowserLog.value(model.identifier),
			"history_messages": String(messages.count),
			"question_bytes": String(question.utf8.count),
			"attachments": String(newAttachments.count),
			"linked_tabs": String(linkedTabIDs.count),
			"pending_pages": String(pendingPages.count),
		])
		defer { isResponding = false }
		do {
			try await BrowserAI.shared.checkAccess(for: model, feature: "AI Sidebar")
			BrowserLog.debug(.ai, "ai.chat.preflight-passed", metadata: ["id": BrowserLog.id(sendID)])
			activity = "Reading Page Context"
			let tabs = availableTabs(in: browser)
			var ids = linkedTabIDs
			for tab in tabs.sorted(by: { $0.title.count > $1.title.count }) {
				if BrowserAIMentions.contains(title: tab.title, in: question), !ids.contains(tab.id) {
					ids.append(tab.id)
				}
			}
			var contextPages = pages
			for page in pendingPages {
				let existing = contextPages.first(where: { $0.value.url == page.url })?.key ?? UUID()
				contextPages[existing] = page
			}
			for id in ids {
				guard let tab = tabs.first(where: { $0.id == id }), let url = tab.currentURL else { throw BrowserAIError.pageUnavailable }
				let pageStarted = BrowserLog.clock()
				let page: BrowserAIPageText = if let controller = tab.activeController, controller.webViewIfLoaded != nil {
					try await BrowserAIPageText.extract(from: controller)
				} else {
					try await BrowserAIPageLoader().page(at: url)
				}
				contextPages[id] = page
				BrowserLog.debug(.ai, "ai.chat.page-extracted", metadata: [
					"id": BrowserLog.id(sendID), "tab": BrowserLog.id(id),
					"url": BrowserLog.url(url), "context_bytes": String(page.prompt.utf8.count),
					"elapsed_ms": String(Int((BrowserLog.clock() - pageStarted) * 1000)),
				])
			}
			try Task.checkCancellation()
			let files = messages.flatMap(\.attachments) + newAttachments
			let images = files.compactMap(\.image)
			guard images.count <= 8, images.reduce(0, { $0 + $1.data.count }) <= 10 * 1024 * 1024 else { throw BrowserAIError.attachmentTooLarge }
			let conversation = messages.map { "\($0.isUser ? "User" : "Assistant"): \($0.text)" }.joined(separator: "\n")
			let context = contextPages.sorted { $0.key.uuidString < $1.key.uuidString }.map(\.value.prompt).joined(separator: "\n\n")
			let fileContext = files.map(\.prompt).joined(separator: "\n\n")
			var toolResults = ""
			var answer = ""
			BrowserLog.debug(.ai, "ai.chat.context-ready", metadata: [
				"id": BrowserLog.id(sendID), "pages": String(contextPages.count),
				"page_bytes": String(context.utf8.count),
				"file_bytes": String(fileContext.utf8.count),
				"conversation_bytes": String(conversation.utf8.count),
				"image_count": String(images.count),
			])
			// Allow multi-page discovery, identity lookup, preview, apply, and a final answer.
			for round in 0 ..< 8 {
				activity = round == 0 ? "Generating Answer" : "Continuing Answer"
				try Task.checkCancellation()
				BrowserLog.debug(.ai, "ai.chat.turn-start", metadata: [
					"id": BrowserLog.id(sendID), "round": String(round + 1),
					"tool_results_bytes": String(toolResults.utf8.count),
				])
				let (turn, results) = try await streamTurn(input: .init(context: context + "\n" + fileContext + "\n<conversation>\n" + conversation + "\n</conversation>\n" + BrowserAITools.inventory(browser) + "\n<tool-results>\n" + toolResults + "\n</tool-results>", question: question, catalog: BrowserAITools.catalog(), images: images, reasoning: selectedReasoning.isEmpty ? "provider-default" : selectedReasoning, files: files.compactMap(\.file)), model: model, browser: browser, spaceID: spaceID)
				BrowserLog.debug(.ai, "ai.chat.turn-complete", metadata: [
					"id": BrowserLog.id(sendID), "round": String(round + 1),
					"action_count": String(turn.actions.count),
					"action_names": turn.actions.map(\.name).joined(separator: ","),
					"response_bytes": String(turn.response.utf8.count),
					"tool_results_bytes": String(results.utf8.count),
				])
				toolResults += results
				if turn.actions.isEmpty {
					answer = turn.response
					break
				}
				preview = turn.response
			}
			guard !answer.isEmpty else { throw BrowserAIError.toolLimit }
			activity = "Saving Conversation"
			try Task.checkCancellation()
			guard id == conversationID else { return }
			pages = contextPages
			messages.append(Message(isUser: true, text: question, attachments: newAttachments))
			messages.append(Message(isUser: false, text: answer))
			answerCommitted = true
			if messages.count == 2 {
				title = String(question.prefix(70))
			}
			draft = ""
			linkedTabIDs = []
			attachments = []
			pendingPages = []
			preview = ""
			try await save()
			BrowserLog.info(.ai, "ai.chat.saved", metadata: [
				"id": BrowserLog.id(sendID), "conversation": BrowserLog.id(conversationID),
				"answer_bytes": String(answer.utf8.count),
				"elapsed_ms": String(Int((BrowserLog.clock() - started) * 1000)),
			])
			// Title generation is supplementary: do not block the composer or
			// turn a successful, saved response into an apparent chat failure.
			if !titleIsGenerated {
				Task { @MainActor [weak self] in
					guard let self else { return }
					let generated = try? await BrowserAI.shared.perform(BrowserChatTitleFeature(), input: .init(question: question, answer: answer), model: model)
					guard id == conversationID, !titleIsGenerated, let generated else { return }
					title = generated
					titleIsGenerated = true
					do {
						try await save()
					} catch {
						BrowserLog.warning(.ai, "ai.chat.title-save-failed", metadata: [
							"id": BrowserLog.id(sendID), "error": BrowserLog.errorDescription(error),
						])
					}
				}
			}
		} catch {
			preview = ""
			if !Task.isCancelled {
				self.error = attemptedBrowserAction
					? "\(error.localizedDescription) Some browser actions may already have completed; review their effects before resending."
					: error.localizedDescription
				canRetry = !answerCommitted && !attemptedBrowserAction
				BrowserLog.error(.ai, "ai.chat.failed", metadata: [
					"id": BrowserLog.id(sendID), "conversation": BrowserLog.id(conversationID),
					"stage": answerCommitted ? "save" : "generation",
					"browser_action_attempted": String(attemptedBrowserAction),
					"error": BrowserLog.errorDescription(error),
					"elapsed_ms": String(Int((BrowserLog.clock() - started) * 1000)),
				])
			} else {
				BrowserLog.debug(.ai, "ai.chat.cancelled", metadata: ["id": BrowserLog.id(sendID)])
			}
		}
	}

	private func streamTurn(input: BrowserAIChatTurnFeature.Input, model: BrowserAIModel, browser: Browser, spaceID: UUID) async throws -> (BrowserAIChatTurnFeature.Turn, String) {
		let feature = BrowserAIChatTurnFeature()
		// Tool calls are pushed as they are decoded. The previous 30 ms
		// polling loop woke continuously during long model responses even
		// when no tool had arrived.
		let (pendingCalls, continuation) = AsyncStream.makeStream(of: BrowserAIToolCall.self)
		var seen = Set<Data>()
		var results = ""
		let turnID = UUID()
		BrowserLog.debug(.ai, "ai.chat.stream-turn-start", metadata: [
			"id": BrowserLog.id(turnID),
			"context_bytes": String(input.context.utf8.count),
			"question_bytes": String(input.question.utf8.count),
			"images": String(input.images.count),
			"model": BrowserLog.value(model.identifier),
		])
		let generation = Task { @MainActor in
			defer { continuation.finish() }
			var lastPreviewPublishedAt: ContinuousClock.Instant?
			var latestPreview = ""
			var lastActionScanAt: ContinuousClock.Instant?
			let turn = try await BrowserAI.shared.performStreaming(feature, input: input, model: model) { snapshot in
				BrowserLog.trace(.ai, "ai.chat.stream-progress", metadata: [
					"id": BrowserLog.id(turnID), "bytes": String(snapshot.utf8.count),
				])
				// Avoid decoding the growing response snapshot on every token.
				// Tool detection below still runs immediately, independently of UI throttling.
				let now = ContinuousClock.now
				if lastPreviewPublishedAt.map({ $0.duration(to: now) >= .milliseconds(85) }) ?? true {
					latestPreview = BrowserAIOutput.streamedString("response", in: snapshot)
						?? (snapshot.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ? "" : snapshot)
					if preview != latestPreview {
						preview = latestPreview
					}
					lastPreviewPublishedAt = now
				}
				// The JSON actions array comes after response text. Avoid
				// reparsing all completed JSON objects before it even exists.
				guard seen.count < 5, snapshot.contains("\"actions\"") else { return }
				// Completed-action JSON scanning is relatively expensive because each
				// snapshot includes previously streamed text. Throttle scans, then
				// perform a guaranteed final reconciliation after stream completion.
				if lastActionScanAt.map({ $0.duration(to: now) < .milliseconds(100) }) == true {
					return
				}
				lastActionScanAt = now
				for data in BrowserAIOutput.completedObjects(in: snapshot) {
					guard seen.count < 5,
					      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
					      object["name"] != nil, object["arguments"] != nil,
					      let envelope = try? JSONSerialization.data(withJSONObject: ["response": "", "actions": [object]]),
					      let turn = try? feature.output(from: String(decoding: envelope, as: UTF8.self)),
					      let call = turn.actions.first else { continue }
					// A bulk apply is destructive or moves multiple tabs. Execute it only
					// after the entire model response has been parsed and validated.
					guard !(call.arguments["phase"] == "apply"
						&& (call.name == BrowserAIAction.closeTab.rawValue
							|| call.name == BrowserAIAction.moveTabsToSpace.rawValue)) else { continue }
					let encoder = JSONEncoder()
					encoder.outputFormatting = .sortedKeys
					guard let identifier = try? encoder.encode(call), seen.insert(identifier).inserted else { continue }
					BrowserLog.debug(.ai, "ai.chat.tool-decoded", metadata: [
						"id": BrowserLog.id(turnID), "tool": call.name,
						"arguments_bytes": String(identifier.count),
					])
					continuation.yield(call)
				}
			}
			// The final decoded response is authoritative even if the last
			// streaming callback occurred inside the UI throttle interval.
			if preview != turn.response {
				preview = turn.response
			}
			// A tool object may have completed inside the final throttle window.
			// Reconcile by action identity so every emitted action is executed once.
			for call in turn.actions where seen.count < 5 {
				let encoder = JSONEncoder()
				encoder.outputFormatting = .sortedKeys
				guard let identifier = try? encoder.encode(call),
				      seen.insert(identifier).inserted else { continue }
				continuation.yield(call)
			}
			BrowserLog.debug(.ai, "ai.chat.stream-turn-finished", metadata: [
				"id": BrowserLog.id(turnID), "actions": String(turn.actions.count),
				"response_bytes": String(turn.response.utf8.count),
				"response": BrowserLog.value(String(turn.response.prefix(8192))),
			])
			return turn
		}
		defer { generation.cancel(); continuation.finish() }
		return try await withTaskCancellationHandler {
			for await call in pendingCalls {
				try Task.checkCancellation()
				let toolStarted = BrowserLog.clock()
				attemptedBrowserAction = true
				activity = "Using Browser Tools"
				BrowserLog.debug(.ai, "ai.chat.tool-start", metadata: [
					"id": BrowserLog.id(turnID), "tool": call.name,
				])
				do {
					let result = try await BrowserAITools.execute(call, browser: browser, spaceID: spaceID, model: model)
					BrowserLog.debug(.ai, "ai.chat.tool-success", metadata: [
						"id": BrowserLog.id(turnID), "tool": call.name,
						"elapsed_ms": String(Int((BrowserLog.clock() - toolStarted) * 1000)),
						"result_bytes": String(result.utf8.count),
						"result": BrowserLog.value(String(result.prefix(4096))),
					])
					results += "\n\(call.name): \(result)\n"
					await BrowserAIUsageLog.shared.record(id: UUID(), feature: call.name, provider: "Browser", event: "success", details: "phase=tool")
				} catch {
					try Task.checkCancellation()
					BrowserLog.error(.ai, "ai.chat.tool-failure", metadata: [
						"id": BrowserLog.id(turnID), "tool": call.name,
						"elapsed_ms": String(Int((BrowserLog.clock() - toolStarted) * 1000)),
						"error": BrowserLog.errorDescription(error),
					])
					results += "\n\(call.name): Failed. \(error.localizedDescription)\n"
					await BrowserAIUsageLog.shared.record(id: UUID(), feature: call.name, provider: "Browser", event: "failed", details: "phase=tool")
				}
			}
			return try await (generation.value, results)
		} onCancel: {
			generation.cancel()
			continuation.finish()
		}
	}

	private func save() async throws {
		try await BrowserAIChatHistory.shared.save(.init(id: id, title: title, titleIsGenerated: titleIsGenerated, updatedAt: .now, messages: messages, pages: pages, provider: selectedProvider, modelID: selectedModelID, reasoning: selectedReasoning))
	}

	func clear() {
		guard !isResponding, !isImporting else { return }
		id = UUID()
		title = "New Chat"
		titleIsGenerated = false
		draft = ""
		attachments = []
		pendingPages = []
		messages = []
		pages = [:]
		linkedTabIDs = []
		preview = ""
		error = nil
		canRetry = false
		attemptedBrowserAction = false
	}
}

nonisolated enum BrowserAIMentions {
	static func contains(title: String, in text: String) -> Bool {
		guard !title.isEmpty else { return false }
		var search = text.startIndex ..< text.endIndex
		while let range = text.range(of: "@" + title, options: .caseInsensitive, range: search) {
			let starts = range.lowerBound == text.startIndex || text[text.index(before: range.lowerBound)].isWhitespace
			let ends = range.upperBound == text.endIndex || text[range.upperBound].isWhitespace || text[range.upperBound].isPunctuation
			if starts, ends {
				return true
			}
			search = range.upperBound ..< text.endIndex
		}
		return false
	}
}
