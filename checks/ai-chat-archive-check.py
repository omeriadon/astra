"""Exercise the production attachment reader and chat archive in an isolated temporary folder."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
history = (root / 'astra/AI/BrowserAIChatHistory.swift').read_text()
attachment = (root / 'astra/AI/BrowserAIAttachment.swift').read_text()
manager = (root / 'astra/AI/BrowserAI.swift').read_text()
errors = manager[manager.index('nonisolated enum BrowserAIError'):]
chat = (root / 'astra/AI/BrowserAIChat.swift').read_text()
message = chat[chat.index('\tnonisolated struct Message'):chat.index('\n\tprivate(set) var id')]
with tempfile.TemporaryDirectory(prefix='astra-chat-archive-check-') as directory:
    folder = Path(directory)
    history = history.replace('let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)', '')
    history = history.replace('let directory = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "browser", isDirectory: true)', 'let directory = URL(fileURLWithPath: "' + directory + '")')
    stubs = 'import Foundation\nimport Observation\n@MainActor final class BrowserAIChat {\n' + message + '\n}\n'
    stubs += '''nonisolated struct BrowserAIPageText: Codable, Sendable {
        let title: String
        let url: URL
        let text: String
    }
'''
    program = r'''
@main struct Check {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: "CHECK_DIRECTORY")
        let textURL = directory.appendingPathComponent("reference.txt")
        try Data("Specific document facts\nA second detail.".utf8).write(to: textURL)
        let file = try await BrowserAIAttachment.read(textURL)
        assert(file.image == nil && file.text?.contains("Specific document facts") == true)
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        image.unlockFocus()
        let pngURL = directory.appendingPathComponent("reference.png")
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: pngURL)
        let picture = try await BrowserAIAttachment.read(pngURL)
        assert(picture.image?.mediaType == "image/png")
        assert(picture.image?.data.starts(with: [137,80,78,71]) == true)
        let message = BrowserAIChat.Message(isUser: true, text: "Explain the reference", attachments: [file, picture])
        let conversation = BrowserAIConversation(id: UUID(), title: "Reference Facts", titleIsGenerated: true, updatedAt: .now, messages: [message], pages: [UUID(): BrowserAIPageText(title: "Page", url: URL(string: "https://example.com")!, text: "Full saved page context")])
        let disk = BrowserAIChatArchive()
        try await disk.save([conversation], revision: 2)
        try await disk.save([], revision: 1)
        let restored = try await disk.load()
        assert(restored.count == 1)
        assert(restored[0].title == conversation.title)
        assert(restored[0].messages[0].id == message.id)
        assert(restored[0].messages[0].attachments[1].image?.data == picture.image?.data)
        assert(restored[0].pages.values.first?.text == "Full saved page context")
        let history = BrowserAIChatHistory()
        await history.load()
        assert(history.conversations.count == 1)
        let archive = directory.appendingPathComponent("ai-chats.json")
        let corrupt = Data("invalid archive".utf8)
        try corrupt.write(to: archive)
        let unreadable = BrowserAIChatHistory()
        await unreadable.load()
        do {
            try await unreadable.save(conversation)
            assertionFailure("Corrupt archive was overwritten")
        } catch {}
        let preserved = try Data(contentsOf: archive)
        assert(preserved == corrupt)
        print("Text/image attachments, chat restoration, stale-write protection, and corrupt-archive preservation passed")
    }
}
'''.replace('CHECK_DIRECTORY', directory)
    swift = folder / 'Check.swift'
    executable = folder / 'check'
    swift.write_text(stubs + errors + attachment + history + program)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=20)
