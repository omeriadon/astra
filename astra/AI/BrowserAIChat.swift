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
		var augmentArtifacts: [BrowserWebsiteAugmentArtifact]? = nil
		var toolCalls: [ToolActivity]? = nil
	}

	nonisolated struct ToolActivity: Codable, Identifiable, Sendable {
		var id = UUID()
		let name: String
		var status: String
		var detail: String? = nil
	}

	private(set) var isAugmenting = false
	private(set) var augmentingTabID: UUID?
	private(set) var toolCalls: [ToolActivity] = []
	@ObservationIgnored private var turnArtifacts: [BrowserWebsiteAugmentArtifact] = []
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
		guard browser.canShowAISidebar, let tab = browser.aiSidebarPageTab, !linkedTabIDs.contains(tab.id) else { return }
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
		toolCalls = []
		turnArtifacts = []
		isAugmenting = false
		augmentingTabID = nil
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
		toolCalls = []
		turnArtifacts = []
		isAugmenting = false
		augmentingTabID = nil
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
		defer { isResponding = false; isAugmenting = false; augmentingTabID = nil }
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
			// Keep full page context locally; send a bounded excerpt first. The model
			// can inspect DOM structure or paginate read_page without resending huge lists.
			let context = contextPages.sorted { $0.key.uuidString < $1.key.uuidString }.map { entry in
				let page = entry.value
				let excerpt = BrowserAIPageText(title: page.title, url: page.url, text: String(page.text.prefix(6000)))
				let identity = tabs.contains(where: { $0.id == entry.key }) ? "tabID=\(entry.key)" : "referenceID=\(entry.key) (attached reference, not an open tab)"
				return "Context \(identity). Characters shown=\(min(page.text.count, 6000)) total=\(page.text.count). Use read_page offset/limit for more or get_page_structure for augmentation.\n" + excerpt.prompt
			}.joined(separator: "\n\n")
			let fileContext = files.map(\.prompt).joined(separator: "\n\n")
			var toolResults: [BrowserAIToolResult] = []
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
					"tool_result_count": String(toolResults.count),
				])
				let (turn, results) = try await streamTurn(input: .init(context: context + "\n" + fileContext + "\n<conversation>\n" + conversation + "\n</conversation>\n" + BrowserAITools.inventory(browser), question: question, catalog: BrowserAITools.catalog(), images: images, reasoning: selectedReasoning.isEmpty ? "provider-default" : selectedReasoning, files: files.compactMap(\.file), toolResults: toolResults), model: model, browser: browser, spaceID: spaceID)
				BrowserLog.debug(.ai, "ai.chat.turn-complete", metadata: [
					"id": BrowserLog.id(sendID), "round": String(round + 1),
					"action_count": String(turn.actions.count),
					"action_names": turn.actions.map(\.name).joined(separator: ","),
					"response_bytes": String(turn.response.utf8.count),
					"tool_result_count": String(results.count),
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
			messages.append(Message(isUser: false, text: answer, augmentArtifacts: turnArtifacts.isEmpty ? nil : turnArtifacts, toolCalls: toolCalls.isEmpty ? nil : toolCalls))
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
			// A completed augmentation remains reopenable even if a later provider round fails.
			if !answerCommitted, !turnArtifacts.isEmpty, id == conversationID {
				messages.append(Message(isUser: true, text: question, attachments: newAttachments))
				messages.append(Message(isUser: false, text: "Website Augment created. The follow-up response did not finish.", augmentArtifacts: turnArtifacts, toolCalls: toolCalls))
				draft = ""
				attachments = []
				pendingPages = []
				linkedTabIDs = []
				try? await save()
			}
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

	private func streamTurn(input: BrowserAIChatTurnFeature.Input, model: BrowserAIModel, browser: Browser, spaceID: UUID) async throws -> (BrowserAIChatTurnFeature.Turn, [BrowserAIToolResult]) {
		let feature = BrowserAIChatTurnFeature()
		var lastPublished: ContinuousClock.Instant?
		// Validate the entire model response before executing any actions. A completed
		// nested object inside malformed or truncated JSON is never authorization.
		let turn = try await BrowserAI.shared.performStreaming(feature, input: input, model: model) { snapshot in
			let now = ContinuousClock.now
			guard lastPublished.map({ $0.duration(to: now) >= .milliseconds(85) }) ?? true else { return }
			lastPublished = now
			preview = BrowserAIOutput.streamedString("response", in: snapshot)
				?? (snapshot.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ? "" : snapshot)
			if snapshot.contains("augment_website") || snapshot.contains("get_page_structure") {
				isAugmenting = true
				if augmentingTabID == nil {
					augmentingTabID = browser.aiSidebarPageTab?.id
				}
			}
		}
		preview = turn.response
		var results: [BrowserAIToolResult] = []
		for call in turn.actions {
			try Task.checkCancellation()
			attemptedBrowserAction = true
			activity = call.name == BrowserAIAction.augmentWebsite.rawValue ? "Augmenting Website" : "Using Browser Tools"
			if call.name == BrowserAIAction.augmentWebsite.rawValue || call.name == BrowserAIAction.getPageStructure.rawValue {
				isAugmenting = true
				augmentingTabID = call.arguments["tabID"].flatMap(UUID.init(uuidString:))
			}
			let index = toolCalls.count
			toolCalls.append(ToolActivity(name: call.name, status: "Running"))
			do {
				let result = try await BrowserAITools.execute(call, browser: browser, spaceID: spaceID, model: model) { artifact in
					self.turnArtifacts.append(artifact)
					// Keep the artifact even if a tab vanished while opening its peek.
					try BrowserWebsiteAugment.open(artifact, in: browser)
				}
				toolCalls[index].status = "Completed"
				toolCalls[index].detail = String(result.prefix(2000))
				results.append(.init(call: call, succeeded: true, result: result))
				await BrowserAIUsageLog.shared.record(id: UUID(), feature: call.name, provider: "Browser", event: "success", details: "phase=tool")
			} catch {
				toolCalls[index].status = Task.isCancelled ? "Cancelled" : "Failed"
				toolCalls[index].detail = error.localizedDescription
				try Task.checkCancellation()
				results.append(.init(call: call, succeeded: false, result: error.localizedDescription))
				await BrowserAIUsageLog.shared.record(id: UUID(), feature: call.name, provider: "Browser", event: "failed", details: "phase=tool")
			}
		}
		return (turn, results)
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
		toolCalls = []
		turnArtifacts = []
		isAugmenting = false
		augmentingTabID = nil
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
