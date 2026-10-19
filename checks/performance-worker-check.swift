import CryptoKit
import Foundation

// Collaborators only: transport, attachment preparation, archive and ranking
// below compile directly from production files with the app's actor isolation.
nonisolated struct BrowserAIPageText: Codable, Sendable { let title: String; let url: URL; let text: String }
@MainActor final class BrowserAIChat {
	nonisolated struct Message: Codable, Sendable { var id = UUID(); let isUser: Bool; let text: String; var attachments: [BrowserAIAttachment] = [] }
}

nonisolated enum BrowserAIError: Error { case chatStorage, attachmentTooLarge, attachmentUnreadable(String) }

@main struct PerformanceWorkerCheck {
	@MainActor static func main() async throws {
		try await transport()
		try await search()
		try await archive()
		try await attachments()
		try await encryption()
		print("Performance workers: backpressure, cancellation, ranking, lazy migration, binary assets and bounds passed")
	}

	@MainActor static func transport() async throws {
		let pipe = Pipe()
		let writer = BrowserAICommandInput(pipe.fileHandleForWriting)
		let task = Task { try await writer.write(String(repeating: "x", count: 8 * 1024 * 1024)) }
		let started = ContinuousClock.now
		try await Task.sleep(for: .milliseconds(80))
		precondition(started.duration(to: .now) < .seconds(2), "Backpressure blocked the UI actor")
		task.cancel()
		do { try await task.value; preconditionFailure("Blocked write ignored cancellation") } catch is CancellationError {}
		precondition(started.duration(to: .now) < .seconds(2), "Cancellation did not unblock the transport")
		try? pipe.fileHandleForReading.close()
		let normal = Pipe()
		let expected = String(repeating: "abcdef", count: 100_000)
		let reader = Task.detached { try normal.fileHandleForReading.readToEnd() }
		try await BrowserAICommandInput(normal.fileHandleForWriting).write(expected, close: true)
		let actual = try await reader.value
		precondition(actual == Data(expected.utf8), "Partial writes changed transport bytes")
		try? normal.fileHandleForReading.close()
	}

	@MainActor static func search() async throws {
		let entries: [BrowserLibrarySearchEntry] = (0 ..< 1200).map { index in
			.init(id: UUID(), url: URL(string: "https://example.com/\(index / 3)")!, title: "Café Alpha \(index)", isTab: index.isMultiple(of: 2), bonus: index.isMultiple(of: 2) ? 0.04 : 0.03)
		}
		let worker = BrowserLibrarySearchWorker()
		for query in ["cafe", "alhpa", "Alpha 12", "no match found"] {
			let request = BrowserLibrarySearchModel.Request(query: query, revision: 1, tabRevision: 1, localeID: "en_US")
			let actual = try await worker.search(entries, request: request)
			let normalized = BrowserSearchMatching.normalized(query, locale: Locale(identifier: "en_US"))
			let expected = entries.compactMap { entry -> BrowserLibrarySearchMatch? in
				let score = max(BrowserSearchMatching.score(normalizedQuery: normalized, in: entry.title), BrowserSearchMatching.score(normalizedQuery: normalized, in: entry.url.absoluteString))
				return score > 0 ? .init(entry: entry, score: score + entry.bonus) : nil
			}.sorted { $0.score == $1.score ? $0.entry.id.uuidString < $1.entry.id.uuidString : $0.score > $1.score }
			var seen: Set<String> = []; var counts: [Bool: Int] = [:]
			let ranked = expected.filter { item in
				let kind = item.entry.isTab
				guard counts[kind, default: 0] < 4, seen.insert("\(kind):\(item.entry.url)").inserted else { return false }
				counts[kind, default: 0] += 1; return true
			}
			precondition(actual.map(\.entry.id) == ranked.map(\.entry.id), "Prepared ranking/deduplication changed")
		}
		let model = BrowserLibrarySearchModel()
		let old = BrowserLibrarySearchModel.Request(query: "Alpha", revision: 1, tabRevision: 1)
		let next = BrowserLibrarySearchModel.Request(query: "Café", revision: 2, tabRevision: 1)
		let cancelled = Task { await model.update(old, scope: .newTab) { entries } }
		cancelled.cancel()
		await model.update(next, scope: .newTab) { entries }
		await cancelled.value
		precondition(model.matches(for: old, scope: .newTab).isEmpty)
		precondition(!model.matches(for: next, scope: .newTab).isEmpty)
	}

	static func archive() async throws {
		let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: temp) }
		try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
		let bytes = Data(repeating: 42, count: 1024 * 1024)
		let attachment = BrowserAIAttachment(id: UUID(), name: "original.bin", image: nil, text: "extracted", file: .init(name: "original.bin", mediaType: "application/octet-stream", data: bytes))
		var original = BrowserAIConversation(id: UUID(), title: "Old chat", titleIsGenerated: false, updatedAt: .now, messages: [.init(isUser: true, text: "Original", attachments: [attachment])], pages: [:])
		let legacy = try JSONEncoder().encode([original])
		try legacy.write(to: temp.appendingPathComponent("ai-chats.json"))
		let directory = temp.appendingPathComponent("ai-chats-v2")
		let archive = BrowserAIChatArchive(directory: directory)
		let summaries = try await archive.load()
		precondition(summaries.count == 1 && summaries[0].messages.isEmpty && summaries[0].pages.isEmpty)
		let recovery = try Data(contentsOf: temp.appendingPathComponent("ai-chats.json"))
		precondition(recovery == legacy)
		let restored = try await archive.conversation(original.id)
		precondition(restored?.messages.first?.attachments.first?.file?.data == bytes)
		original.title = "Renamed"
		try await archive.save(original, revision: 3)
		original.title = "Stale"
		try await archive.save(original, revision: 2)
		let reopened = BrowserAIChatArchive(directory: directory)
		let index = try await reopened.load()
		precondition(index.first?.title == "Renamed")
		var other = original; other = .init(id: UUID(), title: "Another chat", titleIsGenerated: false, updatedAt: .now, messages: [], pages: [:])
		try await reopened.save(other, revision: 1)
		let both = try await reopened.load()
		precondition(both.count == 2, "Revision ordering dropped another conversation")
		let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent != "index.json" }
		for folder in folders {
			try FileManager.default.removeItem(at: folder)
		}
		let metadataOnly = BrowserAIChatArchive(directory: directory)
		let metadata = try await metadataOnly.load()
		precondition(metadata.count == 2, "Metadata load read a body eagerly")
		do { _ = try await metadataOnly.conversation(original.id); preconditionFailure("Missing body was silently accepted") } catch {}
	}

	static func encryption() async throws {
		let sealer = BrowserRestorationStore.Sealer(key: SymmetricKey(data: Data(repeating: 7, count: 32)))
		let url = URL(string: "https://example.com/document")!
		let plaintext = Data(repeating: 9, count: 4 * 1024 * 1024)
		let encrypted = await Task.detached { sealer.seal(plaintext, for: url) }.value
		let box = try AES.GCM.SealedBox(combined: encrypted!)
		let restored = try AES.GCM.open(box, using: sealer.key, authenticating: Data(url.absoluteString.utf8))
		precondition(restored == plaintext)
		do {
			_ = try AES.GCM.open(box, using: sealer.key, authenticating: Data("https://other.example".utf8))
			preconditionFailure("Restoration state lost URL authentication")
		} catch {}
		let tooLarge = await Task.detached { sealer.seal(Data(repeating: 0, count: plaintext.count + 1), for: url) }.value
		precondition(tooLarge == nil)
	}

	@MainActor static func attachments() async throws {
		let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
		defer { try? FileManager.default.removeItem(at: temp) }
		try Data("hello".utf8).write(to: temp)
		let small = try await BrowserAIAttachment.read(temp)
		precondition(small.text == "hello" && small.file?.data == Data("hello".utf8))
		let handle = try FileHandle(forWritingTo: temp)
		try handle.truncate(atOffset: UInt64(BrowserAIAttachment.maximumFileBytes + 1)); try handle.close()
		do { _ = try await BrowserAIAttachment.read(temp); preconditionFailure("Oversized attachment was accepted") } catch BrowserAIError.attachmentTooLarge {}
		do { try BrowserAIAttachment.validateBudget(Array(repeating: small, count: 17)); preconditionFailure("Count budget ignored") } catch BrowserAIError.attachmentTooLarge {}
	}
}
