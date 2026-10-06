"""Exercise production AI request wrappers, the master guard, and plaintext logging without inference."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
manager = (root / 'astra/AI/BrowserAI.swift').read_text()
logger = (root / 'astra/AI/BrowserAIUsageLog.swift').read_text()
protocol = manager[manager.index('@MainActor\nprotocol BrowserAIFeature'):manager.index('@MainActor\nfinal class BrowserAI')]
models = manager[manager.index('nonisolated enum BrowserAIModel'):manager.index('nonisolated struct BrowserAIResponse')]
errors = manager[manager.index('nonisolated enum BrowserAIError'):]
perform = manager[manager.index('\tfunc perform<'):manager.index('\n\t/// Each call')]
generate = manager[manager.index('\tfunc generate('):manager.index('\n\tprivate func generateResponse')]
streaming = manager[manager.index('\tfunc performStreaming<'):manager.index('\n\tprivate func streamResponse')]
logged = manager[manager.index('\tprivate func requireEnabled'):manager.index('\n\tprivate func authentication')]

with tempfile.TemporaryDirectory(prefix='astra-ai-log-check-') as directory:
    logger = logger.replace('let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)', '')
    logger = logger.replace('let directory = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "browser", isDirectory: true)', 'let directory = URL(fileURLWithPath: "' + directory + '")')
    host = '''import Foundation
import Observation
nonisolated struct BrowserAIImage: Codable, Sendable {
    let data: Data
}
@MainActor enum Defaults {
    enum Key { case aiFeaturesEnabled }
    static var enabled = true
    static subscript(key: Key) -> Bool { enabled }
}
@MainActor enum BrowserAISettings {
    static func effectiveModel(_ model: BrowserAIModel) -> BrowserAIModel { model }
}
@MainActor final class Probe {
    var executed = 0
    var response = "Completed answer"
    var wait = false
'''
    host += perform + generate + streaming + logged
    host += r'''
    private func generateResponse(_ request: BrowserAIRequest, model: BrowserAIModel) async throws -> String {
        executed += 1
        if wait { try await Task.sleep(for: .seconds(20)) }
        return response
    }
    private func streamResponse(_ request: BrowserAIRequest, model: BrowserAIModel, onSnapshot: @MainActor (String) -> Void) async throws -> String {
        let value = try await generateResponse(request, model: model)
        onSnapshot(value)
        return value
    }
}
@MainActor struct CheckedFeature: BrowserAIFeature {
    let model: BrowserAIModel = .codex(modelID: "")
    let logName = "Checked Feature"
    func request(for input: String) -> BrowserAIRequest {
        .init(instructions: "PRIVATE_SYSTEM_CONTEXT", prompt: input, maximumResponseTokens: 128)
    }
    func output(from text: String) throws -> String {
        guard text != "invalid" else { throw BrowserAIError.emptyResponse }
        return text
    }
}
@main struct Check {
    @MainActor static func main() async throws {
        let probe = Probe()
        let request = BrowserAIRequest(instructions: "PRIVATE_SYSTEM_CONTEXT", prompt: "PRIVATE_PAGE_CONTENT", maximumResponseTokens: 128, images: [.init(data: Data("PRIVATE_IMAGE_CONTENT".utf8))])
        _ = try await probe.generate(request, model: .openRouter())
        var snapshot = ""
        _ = try await probe.stream(request, model: .claude(modelID: "")) { snapshot = $0 }
        assert(snapshot == "Completed answer")
        _ = try await probe.perform(CheckedFeature(), input: "PRIVATE_PAGE_CONTENT")
        _ = try await probe.performStreaming(CheckedFeature(), input: "PRIVATE_PAGE_CONTENT") { _ in }
        probe.response = "invalid"
        do {
            _ = try await probe.perform(CheckedFeature(), input: "PRIVATE_PAGE_CONTENT")
            assertionFailure("Invalid feature output accepted")
        } catch {}
        let before = probe.executed
        Defaults.enabled = false
        do {
            _ = try await probe.generate(request)
            assertionFailure("Disabled AI executed")
        } catch {}
        assert(probe.executed == before)
        Defaults.enabled = true
        probe.wait = true
        let pending = Task { try await probe.generate(request) }
        while probe.executed == before { try await Task.sleep(for: .milliseconds(5)) }
        pending.cancel()
        _ = try? await pending.value
        let log = BrowserAIUsageLog.shared
        await log.record(id: UUID(), feature: "Test\nforged-entry", provider: "Default", event: "success", details: "images=0")
        guard let url = await log.location() else { fatalError("No usage log") }
        let text = try String(contentsOf: url, encoding: .utf8)
        assert(text.split(separator: "\n").count == 15)
        assert(text.contains("event=success") && text.contains("event=failed") && text.contains("event=cancelled"))
        assert(text.contains("error=disabled") && text.contains("error=emptyResponse"))
        assert(text.contains("mode=single") && text.contains("mode=stream") && text.contains("images=1"))
        assert(text.contains("feature=Checked Feature") && text.contains("provider=Codex") && text.contains("provider=Claude"))
        assert(!text.contains("PRIVATE_") && !text.contains("openai/") && !text.contains("inclusionai/"))
        assert(text.contains("feature=Testforged-entry"))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        assert(permissions?.intValue == 0o600)
        assert(log.errorDescription == nil)
        print("Master guard, single/stream logging, feature validation failures, cancellation, privacy, and file permissions passed")
    }
}
'''
    source = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    source.write_text(models + errors + protocol + logger + host)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=20)
