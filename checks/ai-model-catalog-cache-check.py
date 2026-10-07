"""Run the production catalog cache with mocked installed providers."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
cli = (root / 'astra/AI/BrowserAICLI.swift').read_text()
options = cli[cli.index('nonisolated struct BrowserAIModelOption'):cli.index('\n@MainActor')]
cache = next(line for line in cli.splitlines() if 'private static var modelCatalogTasks:' in line)
start = cli.index('\t\tprivate static func cachedModelCatalog(')
helper = cli[start:cli.index('\n\t\tprivate static func modelCatalog(', start)]
program = 'import Foundation\n' + options + '\n@MainActor enum CatalogCheck {\n' + cache + '\n' + helper
program += r'''
    static var calls: [String: Int] = [:]
    static var failing = false

    private static func modelCatalog(provider: String) async throws -> [BrowserAIModelOption] {
        calls[provider, default: 0] += 1
        try await Task.sleep(for: .milliseconds(20))
        if failing {
            throw NSError(domain: "catalog", code: 1)
        }
        return [.init(id: provider, title: provider)]
    }

    static func check() async throws {
        async let first = cachedModelCatalog(provider: "codex")
        async let second = cachedModelCatalog(provider: "codex")
        let results = try await (first, second)
        assert(results.0.first?.id == "codex" && results.1.first?.id == "codex")
        assert(calls["codex"] == 1, "Overlapping menus must share one CLI query")
        _ = try await cachedModelCatalog(provider: "codex")
        assert(calls["codex"] == 1, "Opening a menu must reuse the catalog")
        _ = try await cachedModelCatalog(provider: "claude")
        assert(calls["claude"] == 1, "Providers must have separate catalogs")

        modelCatalogTasks["codex"]?.requestedAt = .now.advanced(by: .seconds(-3_600))
        _ = try await cachedModelCatalog(provider: "codex")
        assert(calls["codex"] == 2, "Expired catalogs must refresh")
        assert(calls["claude"] == 1)

        failing = true
        modelCatalogTasks["codex"] = nil
        for _ in 0..<2 {
            do {
                _ = try await cachedModelCatalog(provider: "codex")
                assertionFailure("Expected provider failure")
            } catch {}
        }
        assert(calls["codex"] == 3, "Failures must not launch a CLI on every menu opening")
        failing = false
        modelCatalogTasks["codex"] = nil
        _ = try await cachedModelCatalog(provider: "codex")
        assert(calls["codex"] == 4, "Permission recovery must allow an immediate retry")
        print("Model catalog cache: shared queries, provider isolation, hourly expiry, and failure recovery passed")
    }
}

@main struct Check {
    static func main() async throws {
        try await CatalogCheck.check()
    }
}
'''
with tempfile.TemporaryDirectory(prefix='astra-model-cache-check-') as directory:
    source = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    source.write_text(program)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
