import Foundation
import Observation

nonisolated struct BrowserAIConversation: Codable, Identifiable, Sendable {
	let id: UUID
	var title: String
	var titleIsGenerated: Bool
	var updatedAt: Date
	var messages: [BrowserAIChat.Message]
	var pages: [UUID: BrowserAIPageText]
	var provider: String? = nil
	var modelID: String? = nil
	var reasoning: String? = nil
}

@MainActor
@Observable
final class BrowserAIChatHistory {
	static let shared = BrowserAIChatHistory()
	private(set) var conversations: [BrowserAIConversation] = []
	private(set) var error: String?
	@ObservationIgnored private let disk = BrowserAIChatArchive()
	@ObservationIgnored private var loadTask: Task<[BrowserAIConversation], Error>?
	@ObservationIgnored private var loaded = false
	@ObservationIgnored private var writable = true
	@ObservationIgnored private var revision = 0

	func load() async {
		guard !loaded else { return }
		if loadTask == nil {
			loadTask = Task { try await disk.load() }
		}
		do {
			let saved = try await loadTask!.value
			guard !loaded else { return }
			conversations = saved.sorted { $0.updatedAt > $1.updatedAt }
		} catch {
			writable = false
			self.error = "Saved chats could not be read. The existing archive has been preserved."
		}
		loaded = true
	}

	func save(_ conversation: BrowserAIConversation) async throws {
		await load()
		guard writable else { throw BrowserAIError.chatStorage }
		conversations.removeAll { $0.id == conversation.id }
		conversations.insert(conversation, at: 0)
		revision += 1
		do {
			try await disk.save(conversations, revision: revision)
			error = nil
		} catch {
			self.error = "This chat is still open, but could not be saved to disk."
			throw BrowserAIError.chatStorage
		}
	}
}

private actor BrowserAIChatArchive {
	private var savedRevision = 0

	private func fileURL() throws -> URL {
		let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		let directory = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "browser", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory.appendingPathComponent("ai-chats.json")
	}

	func load() throws -> [BrowserAIConversation] {
		let url = try fileURL()
		guard FileManager.default.fileExists(atPath: url.path) else { return [] }
		return try JSONDecoder().decode([BrowserAIConversation].self, from: Data(contentsOf: url))
	}

	func save(_ conversations: [BrowserAIConversation], revision: Int) throws {
		guard revision >= savedRevision else { return }
		let url = try fileURL()
		let data = try JSONEncoder().encode(conversations)
		try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
		try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
		savedRevision = revision
	}
}
