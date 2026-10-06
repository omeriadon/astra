"""Run with python3 checks/ai-features-check.py. Compiles the production validators with type-only host stubs."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
manager = (root / 'astra/AI/BrowserAI.swift').read_text()
protocol = manager[manager.index('@MainActor\nprotocol BrowserAIFeature'):manager.index('@MainActor\nfinal class BrowserAI')]
request = manager[manager.index('nonisolated struct BrowserAIRequest'):manager.index('nonisolated struct BrowserAIResponse')]
errors = manager[manager.index('nonisolated enum BrowserAIError'):]
features = (root / 'astra/AI/Features/BrowserPageFeatures.swift').read_text()
prompts = (root / 'astra/AI/BrowserAIPrompts.swift').read_text()
chat = (root / 'astra/AI/BrowserAIChat.swift').read_text()
mentions = chat[chat.index('nonisolated enum BrowserAIMentions'):]
cli = (root / 'astra/AI/BrowserAICLI.swift').read_text()
symbols = (root / 'astra/AI/BrowserAISymbols.swift').read_text()
titles = (root / 'astra/AI/Features/BrowserChatTitleFeature.swift').read_text()
auth_start = manager.index('\tprivate func authentication(')
auth_end = manager.index('\n\tprivate func pccSession', auth_start)
authentication = manager[auth_start:auth_end]
address = (root / 'astra/UI/AddressBar/BrowserAddress.swift').read_text()
address_method = address[address.index('\tnonisolated static func withoutCredentials'):address.index('\n\tstatic func destination')]
models = manager[manager.index('nonisolated enum BrowserAIModel'):manager.index('nonisolated struct BrowserAIRequest')]
stubs = '''
@MainActor final class BrowserSync {
    static let shared = BrowserSync()
    func requireAIAuthentication() throws -> UInt64 { throw BrowserAIError.signInRequired }
}
@MainActor final class AuthenticationProbe {
    func check(_ model: BrowserAIModel) throws -> UInt64? { try authentication(for: model) }
AUTHENTICATION
}

nonisolated struct BrowserAIImage: Codable, Sendable {
    let name: String
    let mediaType: String
    let data: Data
}
nonisolated enum BrowserAIFeatureID {
    case downloads, linkPreview, tabGroups, find, chat, tabTitles
    @MainActor var model: BrowserAIModel { .appleIntelligence }
    var title: String { String(describing: self) }
}
nonisolated struct BrowserAIPageText {
    let title: String
    let url: URL
    let text: String
    var prompt: String { text }
}
'''
stubs = stubs.replace('AUTHENTICATION', authentication)
stubs += 'enum BrowserAddress {\n' + address_method + '\n}\n'
checks = r'''
@main struct Checks {
    @MainActor static func main() async throws {
        func rejects(_ action: () throws -> Void) {
            do {
                try action()
                assertionFailure("Invalid output was accepted")
            } catch {}
        }
        let titles = BrowserTabTitleFeature()
        let cleaned = try titles.output(from: "AirPods Pro 3")
        assert(cleaned == "AirPods Pro 3")
        rejects { _ = try titles.output(from: "one two three four five six seven eight") }
        rejects { _ = try titles.output(from: "First title\nInjected instructions") }
        rejects { _ = try titles.output(from: " \n ") }
        let summaries = BrowserLinkSummaryFeature()
        let origin = URL(string: "https://secret:password@www.google.com/search?q=C%2B%2B+memory+ownership")!
        let destination = URL(string: "https://username:password@example.com/article")!
        let page = BrowserAIPageText(title: "C++ Ownership", url: destination, text: "Unique ownership releases memory safely.")
        let preview = summaries.request(for: .init(sourceURL: origin, destinationURL: destination, page: page))
        assert(preview.prompt.contains("Source page URL: https://www.google.com/search"))
        assert(preview.prompt.contains("Previewed link URL: https://example.com/article"))
        assert(preview.prompt.contains("Search query: C++ memory ownership"))
        assert(!preview.prompt.contains("secret:") && !preview.prompt.contains("username:"))
        assert(preview.prompt.contains("Unique ownership releases memory safely."))
        let valid = #"{"title":"SQLite at the Edge","header":"SQLite stores relational data in a single file.","bullets":[{"text":"Embedded storage works without a separate database server.","symbol":"server.rack"}]}"#
        let summary = try summaries.output(from: valid)
        assert(summary.bullets.count == 1)
        let fenced = try summaries.output(from: "```json\n" + valid + "\n```")
        assert(fenced.title == "SQLite at the Edge")
        rejects { _ = try summaries.output(from: #"{"title":"Title","header":"Header","bullets":["a","b","c","d","e","f"]}"#) }
        let long = String(repeating: "word ", count: 21)
        let invalid = try JSONSerialization.data(withJSONObject: ["title": "Title", "header": "Header", "bullets": [["text":long,"symbol":"book"]]])
        rejects { _ = try summaries.output(from: String(decoding: invalid, as: UTF8.self)) }
        rejects { _ = try summaries.output(from: #"{"title":"Title","header":"Header","bullets":[{"text":"Valid text","symbol":"not.a.real.symbol"}]}"#) }
        assert((300...400).contains(BrowserAISymbols.names.count))
        assert(Set(BrowserAISymbols.names).count == BrowserAISymbols.names.count)
        let chatTitle = try BrowserChatTitleFeature().output(from: "Understanding SQLite Transactions")
        assert(chatTitle == "Understanding SQLite Transactions")
        rejects { _ = try BrowserChatTitleFeature().output(from: "one two three four five six seven eight") }
        assert(BrowserAIError.signInRequired.localizedDescription.contains("Default AI"))
        assert(BrowserAIError.http(413, data: Data()).localizedDescription.contains("size limit"))
        assert(BrowserAIError.http(400, data: Data(#"{"reason":"This preset is disabled"}"#.utf8)).localizedDescription.contains("preset is disabled"))
        let first = UUID()
        let second = UUID()
        let group = BrowserTabGroupingFeature.Group(name: "Research", tabIDs: [first, second])
        try BrowserTabGroupingFeature.validate([group], expectedIDs: [first, second])
        rejects { try BrowserTabGroupingFeature.validate([group], expectedIDs: [first]) }
        rejects { try BrowserTabGroupingFeature.validate([.init(name: "Research", tabIDs: [first, first])], expectedIDs: [first, second]) }
        rejects { try BrowserTabGroupingFeature.validate([.init(name: "Research", tabIDs: [first, UUID()])], expectedIDs: [first, second]) }
        assert(BrowserAIMentions.contains(title: "Swift Documentation", in: "Explain @Swift Documentation"))
        assert(BrowserAIMentions.contains(title: "Swift Documentation", in: "Compare @swift documentation, please"))
        assert(!BrowserAIMentions.contains(title: "Swift", in: "Explain @SwiftUI"))
        assert(!BrowserAIMentions.contains(title: "Swift", in: "email@Swift.example"))
        assert(!BrowserAIMentions.contains(title: "", in: "@"))
        let authentication = AuthenticationProbe()
        let codexAccess = try authentication.check(.codex(modelID: ""))
        let claudeAccess = try authentication.check(.claude(modelID: ""))
        let localAccess = try authentication.check(.appleIntelligence)
        assert(codexAccess == nil && claudeAccess == nil && localAccess == nil)
        rejects { _ = try authentication.check(.openRouter()) }
        let codexModels = try await BrowserAICLI.models(provider: "codex")
        assert(codexModels.map(\.id) == ["available-low", "high-only"])
        assert(codexModels.first?.reasoningLevels == ["low"])
        let claudeModels = try await BrowserAICLI.models(provider: "claude")
        assert(claudeModels.map(\.id) == ["claude-current"])
        let request = BrowserAIRequest(instructions: "Return plain text", prompt: String(repeating: "page-data ", count: 30_000), maximumResponseTokens: 128)
        let codexAnswer = try await BrowserAICLI.generate(request, model: .codex(modelID: "available-low"))
        assert(codexAnswer == "Codex pipe answer")
        let claudeAnswer = try await BrowserAICLI.generate(request, model: .claude(modelID: "claude-current"))
        assert(claudeAnswer == "Claude pipe answer")
        let image = BrowserAIImage(name: "diagram.png", mediaType: "image/png", data: Data([137,80,78,71,13,10,26,10]))
        let imageRequest = BrowserAIRequest(instructions: "Describe", prompt: "Describe the image", maximumResponseTokens: 128, images: [image])
        let codexImage = try await BrowserAICLI.generate(imageRequest, model: .codex(modelID: "available-low"))
        let claudeImage = try await BrowserAICLI.generate(imageRequest, model: .claude(modelID: "claude-current"))
        assert(codexImage == "Codex image answer" && claudeImage == "Claude image answer")
        do {
            _ = try await BrowserAICLI.generate(.init(instructions: "Answer", prompt: "providerAuthFailure", maximumResponseTokens: 128), model: .codex(modelID: "available-low"))
            assertionFailure("Provider authentication failure was accepted")
        } catch {
            assert(error.localizedDescription.contains("provider account"))
            assert(error.localizedDescription.contains("No Astra sign-in"))
        }
        let waiting = Task { try await BrowserAICLI.generate(.init(instructions: "Answer", prompt: "waitForCancellation", maximumResponseTokens: 128), model: .codex(modelID: "available-low")) }
        try await Task.sleep(for: .milliseconds(100))
        waiting.cancel()
        do {
            _ = try await waiting.value
            assertionFailure("Canceled command completed successfully")
        } catch {}
        print("CLI catalogs, long stdin, responses, tool restrictions, and cancellation passed")
        print("AI title/summary limits, fenced JSON, tab identity coverage, and exact-title mention checks passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='astra-ai-check-') as temporary:
    source = Path(temporary) / 'Checks.swift'
    binary = Path(temporary) / 'checks'
    source.write_text('import Foundation\n' + models + request + protocol + errors + stubs + prompts + features + symbols + titles + mentions + cli + checks)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(binary)], check=True)
    import os
    fake = r'''#!/usr/bin/python3
import sys, json, time
args = sys.argv[1:]
if "app-server" in args:
    for line in sys.stdin:
        event = json.loads(line)
        if event.get("method") == "initialize":
            print(json.dumps({"id": 1, "result": {}}), flush=True)
        elif event.get("method") == "model/list":
            print(json.dumps({"id": 2, "result": {"data": [
                {"model": "available-low", "displayName": "Low", "supportedReasoningEfforts": [{"reasoningEffort": "low"}]},
                {"model": "high-only", "supportedReasoningEfforts": [{"reasoningEffort": "high"}]}
            ], "nextCursor": None}}), flush=True)
elif "--input-format" in args:
    event = json.loads(sys.stdin.readline())
    if event.get("type") == "user":
        parts = event["message"]["content"]
        image = next(p for p in parts if p["type"] == "image")
        assert image["source"]["type"] == "base64" and image["source"]["media_type"] == "image/png"
        print(json.dumps({"type":"result", "result":"Claude image answer", "is_error":False}), flush=True)
        sys.exit(0)
    assert event["request"]["subtype"] == "initialize"
    print(json.dumps({"type": "control_response", "response": {"subtype": "success", "response": {"models": [{"value": "claude-current", "displayName": "Claude Current"}]}}}), flush=True)
    sys.stdin.read()
else:
    prompt = sys.stdin.read()
    if "waitForCancellation" in prompt:
        time.sleep(20)
    if "providerAuthFailure" in prompt:
        sys.stderr.write("401 Unauthorized: provider account login required")
        sys.exit(1)
    if "--image" in args:
        from pathlib import Path
        data=Path(args[args.index("--image")+1]).read_bytes()
        assert data.startswith(bytes([137,80,78,71]))
        print(json.dumps({"type":"item.completed", "item":{"type":"agent_message", "text":"Codex image answer"}}), flush=True)
        sys.exit(0)
    assert len(prompt) >= 300_000
    if "exec" in args:
        assert "--ignore-user-config" in args and "read-only" in args and "shell_tool" in args
        assert 'model_reasoning_effort="low"' in args
        print(json.dumps({"type": "item.completed", "item": {"type": "agent_message", "text": "Codex pipe answer"}}), flush=True)
    else:
        assert args[args.index("--tools") + 1] == ""
        assert "--strict-mcp-config" in args and args[args.index("--effort") + 1] == "low"
        print(json.dumps({"type": "result", "result": "Claude pipe answer", "is_error": False}), flush=True)
'''
    for name in ['codex', 'claude']:
        command = Path(temporary) / name
        command.write_text(fake)
        command.chmod(0o700)
    environment = dict(os.environ, PATH=temporary + ':' + os.environ.get('PATH', ''))
    subprocess.run([str(binary)], check=True, env=environment, timeout=20)
