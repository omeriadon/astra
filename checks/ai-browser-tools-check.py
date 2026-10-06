"""Check production tool parsing and the execution permission boundary without browser mutations."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'astra/AI/BrowserAITools.swift').read_text()
types = source[:source.index('@MainActor\nenum BrowserAITools')].replace('import Defaults', '')
gate_start = source.index('\t\tguard Defaults[.aiFeaturesEnabled]')
gate = source[gate_start:source.index('\t\t#if os(macOS)', gate_start)]
manager = (root / 'astra/AI/BrowserAI.swift').read_text()
protocol = manager[manager.index('@MainActor\nprotocol BrowserAIFeature'):manager.index('@MainActor\nfinal class BrowserAI')]
models = manager[manager.index('nonisolated enum BrowserAIModel'):manager.index('nonisolated struct BrowserAIResponse')]
errors = manager[manager.index('nonisolated enum BrowserAIError'):]
attachments = (root / 'astra/AI/BrowserAIAttachment.swift').read_text()
attachment_types = attachments[attachments.index('nonisolated struct BrowserAIImage'):attachments.index('nonisolated struct BrowserAIAttachment')]
prompts = (root / 'astra/AI/BrowserAIPrompts.swift').read_text()
output = (root / 'astra/AI/Features/BrowserPageFeatures.swift').read_text().split('nonisolated enum BrowserAIOutput')[1]
host = '''
@MainActor enum Defaults {
    enum BooleanKey { case aiFeaturesEnabled }
    enum StringKey { case aiBrowserActionPermissions }
    static var all = true
    static var permissions = "{}"
    static subscript(key: BooleanKey) -> Bool { all }
    static subscript(key: StringKey) -> String {
        get { permissions }
        set { permissions = newValue }
    }
}
@MainActor enum BrowserAIFeatureID {
    case chat
    var model: BrowserAIModel { .codex(modelID: "") }
}
@MainActor struct Browser {
    struct Space { let id: UUID }
    var isPrivate = false
    var selectedSpace: Space
}
@MainActor func authorize(_ call: BrowserAIToolCall, browser: Browser, spaceID: UUID) throws -> BrowserAIAction {
''' + gate + '''return action
}
@main struct Check {
    @MainActor static func main() throws {
        func rejects(_ action: () throws -> Void) {
            do { try action(); assertionFailure("Unsafe action accepted") } catch {}
        }
        let space = UUID()
        let browser = Browser(selectedSpace: .init(id: space))
        let open = BrowserAIToolCall(name: "open_tab", arguments: ["url":"https://example.com"])
        let accepted = try authorize(open, browser: browser, spaceID: space)
        assert(accepted == .openTab)
        rejects { _ = try authorize(.init(name: "delete_bookmark", arguments: [:]), browser: browser, spaceID: space) }
        BrowserAIAction.deleteBookmark.enabled = true
        let deletion = try authorize(.init(name: "delete_bookmark", arguments: [:]), browser: browser, spaceID: space)
        assert(deletion == .deleteBookmark)
        Defaults.all = false
        rejects { _ = try authorize(open, browser: browser, spaceID: space) }
        Defaults.all = true
        rejects { _ = try authorize(open, browser: Browser(isPrivate: true, selectedSpace: .init(id: space)), spaceID: space) }
        rejects { _ = try authorize(open, browser: browser, spaceID: UUID()) }
        let feature = BrowserAIChatTurnFeature()
        let turn = try feature.output(from: #"{"response":"Working","actions":[{"name":"pin_tab","arguments":{"tabID":"123","enabled":true}}]}"#)
        assert(turn.actions.first?.arguments["enabled"] == "true")
        rejects { _ = try feature.output(from: #"{"response":"Unsafe","actions":[{"name":"run_shell","arguments":{}}]}"#) }
        rejects { _ = try feature.output(from: #"{"response":"Unsafe","actions":[{"name":"open_tab","arguments":{"url":[]}}]}"#) }
        let markdown = try feature.output(from: "# Final answer")
        assert(markdown.response == "# Final answer" && markdown.actions.isEmpty)
        print("Tool permissions, destructive defaults, private/space isolation, Boolean arguments, and unknown-tool rejection passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='astra-tools-check-') as directory:
    swift = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    swift.write_text('import Foundation\n' + attachment_types + models + errors + protocol + prompts + 'nonisolated enum BrowserAIOutput' + output + types + host)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
