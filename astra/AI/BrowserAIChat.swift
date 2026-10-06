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
	private(set) var isResponding = false
	@ObservationIgnored private var pages: [UUID: BrowserAIPageText] = [:]

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
		isResponding = true
		error = nil
		preview = ""
		defer { isResponding = false }
		do {
			try await BrowserAI.shared.checkAccess(for: model, feature: "AI Sidebar")
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
				let page: BrowserAIPageText = if let controller = tab.activeController, controller.webViewIfLoaded != nil {
					try await BrowserAIPageText.extract(from: controller)
				} else {
					try await BrowserAIPageLoader().page(at: url)
				}
				contextPages[id] = page
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
			for _ in 0 ..< 5 {
				try Task.checkCancellation()
				let turn = try await BrowserAI.shared.perform(BrowserAIChatTurnFeature(), input: .init(context: context + "\n" + fileContext + "\n<conversation>\n" + conversation + "\n</conversation>\n" + BrowserAITools.inventory(browser) + "\n<tool-results>\n" + toolResults + "\n</tool-results>", question: question, catalog: BrowserAITools.catalog(), images: images, reasoning: selectedReasoning.isEmpty ? "provider-default" : selectedReasoning), model: model)
				if turn.actions.isEmpty {
					answer = turn.response; break
				}
				preview = turn.response
				for call in turn.actions {
					try Task.checkCancellation()
					do {
						let result = try await BrowserAITools.execute(call, browser: browser, spaceID: spaceID, model: model)
						toolResults += "\n\(call.name): \(result)\n"
						await BrowserAIUsageLog.shared.record(id: UUID(), feature: call.name, provider: "Browser", event: "success", details: "phase=tool")
					} catch {
						try Task.checkCancellation()
						toolResults += "\n\(call.name): Failed. \(error.localizedDescription)\n"
						await BrowserAIUsageLog.shared.record(id: UUID(), feature: call.name, provider: "Browser", event: "failed", details: "phase=tool")
					}
				}
			}
			guard !answer.isEmpty else { throw BrowserAIError.toolLimit }
			try Task.checkCancellation()
			guard id == conversationID else { return }
			pages = contextPages
			messages.append(Message(isUser: true, text: question, attachments: newAttachments))
			messages.append(Message(isUser: false, text: answer))
			if messages.count == 2 {
				title = String(question.prefix(70))
			}
			draft = ""
			linkedTabIDs = []
			attachments = []
			pendingPages = []
			preview = ""
			try await save()
			if !titleIsGenerated {
				let generated = try await BrowserAI.shared.perform(BrowserChatTitleFeature(), input: .init(question: question, answer: answer), model: model)
				try Task.checkCancellation()
				title = generated
				titleIsGenerated = true
				try await save()
			}
		} catch {
			preview = ""
			if !Task.isCancelled {
				self.error = error.localizedDescription
			}
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
