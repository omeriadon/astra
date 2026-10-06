"""Run the production chat stream drain against cumulative mocked provider snapshots."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
chat = (root / 'astra/AI/BrowserAIChat.swift').read_text()
helper = chat[chat.index('\tprivate func streamTurn('):chat.index('\n\tprivate func save()')].replace('private func streamTurn', 'func streamTurn')
features = (root / 'astra/AI/Features/BrowserPageFeatures.swift').read_text()
output = features[features.index('nonisolated enum BrowserAIOutput'):]
program = r'''
import Foundation
nonisolated struct BrowserAIToolCall: Codable, Sendable {
    let name: String
    let arguments: [String: String]
}
nonisolated enum BrowserAIModel { case mock }
@MainActor final class Browser {}
@MainActor struct BrowserAIChatTurnFeature {
    struct Input {}
    struct Turn: Decodable { let response: String; let actions: [BrowserAIToolCall] }
    func output(from text: String) throws -> Turn {
        let result = try JSONDecoder().decode(Turn.self, from: Data(text.utf8))
        guard result.actions.allSatisfy({ $0.name == "create-folder" || $0.name == "move-tab" }) else {
            throw NSError(domain: "invalid-action", code: 1)
        }
        return result
    }
}
@MainActor enum BrowserAITools {
    static var executed: [String] = []
    static func execute(_ call: BrowserAIToolCall, browser: Browser, spaceID: UUID, model: BrowserAIModel) async throws -> String {
        try Task.checkCancellation()
        assert(!BrowserAI.completed)
        executed.append(call.name)
        return "success"
    }
}
@MainActor final class BrowserAIUsageLog {
    static let shared = BrowserAIUsageLog()
    func record(id: UUID, feature: String, provider: String, event: String, details: String) async {}
}
@MainActor final class BrowserAI {
    static let shared = BrowserAI()
    static var completed = false
    func performStreaming(_ feature: BrowserAIChatTurnFeature, input: BrowserAIChatTurnFeature.Input, model: BrowserAIModel, onSnapshot: @MainActor (String) -> Void) async throws -> BrowserAIChatTurnFeature.Turn {
        let first = #"{"response":"Working","actions":[{"name":"create-folder","arguments":{"name":"Research"}}"#
        onSnapshot(first)
        onSnapshot(first)
        try await Task.sleep(for: .milliseconds(80))
        onSnapshot(first + #",{"name":"move-tab","arguments":{"id":"tab-one"}}"#)
        try await Task.sleep(for: .milliseconds(80))
        Self.completed = true
        return try feature.output(from: first + #",{"name":"move-tab","arguments":{"id":"tab-one"}}]}"#)
    }
}
'''
program += output + '\n@MainActor final class ChatCheck { var preview = ""\n' + helper + '\n}\n'
program += r'''
@main struct Check {
    @MainActor static func main() async throws {
        let chat = ChatCheck()
        let (turn, results) = try await chat.streamTurn(input: .init(), model: .mock, browser: Browser(), spaceID: UUID())
        assert(turn.actions.count == 2)
        assert(BrowserAITools.executed == ["create-folder", "move-tab"])
        assert(results.contains("create-folder: success") && results.contains("move-tab: success"))
        assert(chat.preview == "Working")
        print("Chat actions streamed before final output, executed serially, and deduplicated cumulative snapshots")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='astra-chat-stream-check-') as directory:
    source = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    source.write_text(program)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
