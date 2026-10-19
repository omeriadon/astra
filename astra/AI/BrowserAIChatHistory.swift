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

	var summary: Self {
		var value = self
		value.messages = []
		value.pages = [:]
		return value
	}
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
			BrowserLog.error(.ai, "ai.chat-history.load.failed", metadata: ["error": BrowserLog.errorDescription(error)])
			writable = false
			self.error = "Saved chats could not be read. The existing archive has been preserved."
		}
		loaded = true
	}

	func conversation(_ id: UUID) async -> BrowserAIConversation? {
		await load()
		do { return try await disk.conversation(id) }
		catch {
			self.error = "This saved chat could not be read. Its archive has been preserved."
			return nil
		}
	}

	func save(_ conversation: BrowserAIConversation) async throws {
		await load()
		guard writable else { throw BrowserAIError.chatStorage }
		conversations.removeAll { $0.id == conversation.id }
		conversations.insert(conversation.summary, at: 0)
		revision += 1
		do {
			try await disk.save(conversation, revision: revision)
			error = nil
		} catch {
			BrowserLog.error(.ai, "ai.chat-history.save.failed", metadata: [
				"conversation": BrowserLog.id(conversation.id),
				"messages": String(conversation.messages.count),
				"error": BrowserLog.errorDescription(error),
			])
			self.error = "This chat is still open, but could not be saved to disk."
			throw BrowserAIError.chatStorage
		}
	}
}

/// The index contains only metadata. Bodies and binary attachments are read on selection.
/// Each save writes an immutable generation before atomically replacing the index;
/// a failed migration/save leaves the previous archive readable.
actor BrowserAIChatArchive {
	private nonisolated struct Record: Codable { let summary: BrowserAIConversation; let generation: UUID }
	private nonisolated struct Asset: Codable { let message: Int; let attachment: Int; let image: Bool; let filename: String }
	private nonisolated struct Body: Codable { var conversation: BrowserAIConversation; let assets: [Asset] }
	private var savedRevisions: [UUID: Int] = [:]
	private var records: [Record] = []
	private var loaded = false
	private var cache: [(UUID, BrowserAIConversation)] = []
	private let testDirectory: URL?
	init(directory: URL? = nil) { testDirectory = directory }

	private func root() throws -> URL {
		if let testDirectory {
			try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
			return testDirectory
		}
		let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		let directory = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "browser", isDirectory: true).appendingPathComponent("ai-chats-v2", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}
	private func write(_ data: Data, to url: URL) throws {
		try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
		try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
	}
	func load() throws -> [BrowserAIConversation] {
		if loaded { return records.map(\.summary) }
		let directory = try root()
		let index = directory.appendingPathComponent("index.json")
		if FileManager.default.fileExists(atPath: index.path) {
			records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: index))
		} else {
			let legacy = directory.deletingLastPathComponent().appendingPathComponent("ai-chats.json")
			if FileManager.default.fileExists(atPath: legacy.path) {
				let conversations = try JSONDecoder().decode([BrowserAIConversation].self, from: Data(contentsOf: legacy))
				var migrated: [Record] = []
				for conversation in conversations { migrated.append(try writeBody(conversation, directory: directory)) }
				try write(JSONEncoder().encode(migrated), to: index)
				records = migrated
				// Keep the legacy file as a recovery copy; never replace it during migration.
			}
		}
		loaded = true
		return records.map(\.summary)
	}
	private func writeBody(_ conversation: BrowserAIConversation, directory: URL) throws -> Record {
		let generation = UUID()
		let folder = directory.appendingPathComponent(generation.uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		var body = conversation
		var assets: [Asset] = []
		for mi in body.messages.indices {
			for ai in body.messages[mi].attachments.indices {
				let attachment = body.messages[mi].attachments[ai]
				var image = attachment.image
				var file = attachment.file
				if let value = image {
					let filename = "\(mi)-\(ai)-image.bin"
					try write(value.data, to: folder.appendingPathComponent(filename))
					assets.append(.init(message: mi, attachment: ai, image: true, filename: filename))
					image = .init(name: value.name, mediaType: value.mediaType, data: Data())
				}
				if let value = file {
					let filename = "\(mi)-\(ai)-file.bin"
					try write(value.data, to: folder.appendingPathComponent(filename))
					assets.append(.init(message: mi, attachment: ai, image: false, filename: filename))
					file = .init(name: value.name, mediaType: value.mediaType, data: Data(), hasExtractedText: value.hasExtractedText)
				}
				body.messages[mi].attachments[ai] = .init(id: attachment.id, name: attachment.name, image: image, text: attachment.text, file: file)
			}
		}
		try write(JSONEncoder().encode(Body(conversation: body, assets: assets)), to: folder.appendingPathComponent("body.json"))
		return Record(summary: conversation.summary, generation: generation)
	}
	func conversation(_ id: UUID) throws -> BrowserAIConversation? {
		_ = try load()
		if let index = cache.firstIndex(where: { $0.0 == id }) {
			let value = cache.remove(at: index); cache.insert(value, at: 0); return value.1
		}
		guard let record = records.first(where: { $0.summary.id == id }) else { return nil }
		let directory = try root().appendingPathComponent(record.generation.uuidString)
		var body = try JSONDecoder().decode(Body.self, from: Data(contentsOf: directory.appendingPathComponent("body.json")))
		for asset in body.assets {
			guard body.conversation.messages.indices.contains(asset.message), body.conversation.messages[asset.message].attachments.indices.contains(asset.attachment),
			      asset.filename == "\(asset.message)-\(asset.attachment)-\(asset.image ? "image" : "file").bin" else { throw BrowserAIError.chatStorage }
			let original = body.conversation.messages[asset.message].attachments[asset.attachment]
			let bytes = try Data(contentsOf: directory.appendingPathComponent(asset.filename))
			let image = asset.image ? original.image.map { BrowserAIImage(name: $0.name, mediaType: $0.mediaType, data: bytes) } : original.image
			let file = !asset.image ? original.file.map { BrowserAIFile(name: $0.name, mediaType: $0.mediaType, data: bytes, hasExtractedText: $0.hasExtractedText) } : original.file
			body.conversation.messages[asset.message].attachments[asset.attachment] = .init(id: original.id, name: original.name, image: image, text: original.text, file: file)
		}
		cache.insert((id, body.conversation), at: 0)
		cache = Array(cache.prefix(2))
		return body.conversation
	}
	func save(_ conversation: BrowserAIConversation, revision: Int) throws {
		_ = try load()
		guard revision >= (savedRevisions[conversation.id] ?? 0) else { return }
		let directory = try root()
		let record = try writeBody(conversation, directory: directory)
		let previous = records.first { $0.summary.id == conversation.id }
		var next = records.filter { $0.summary.id != conversation.id }
		next.insert(record, at: 0)
		try write(JSONEncoder().encode(next), to: directory.appendingPathComponent("index.json"))
		records = next
		savedRevisions[conversation.id] = revision
		cache.removeAll { $0.0 == conversation.id }
		if let previous { try? FileManager.default.removeItem(at: directory.appendingPathComponent(previous.generation.uuidString)) }
	}
}
