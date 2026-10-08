"""Compile and execute the production usage payload decoders and cookie policy."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
production = (root / "astra/Web/Usage/BrowserUsageLimits.swift").read_text()
production = production.replace(
    "BrowserUsageLimitsClient(dataStore: dataStore).fetch(provider)",
    "ProbeClient.fetch(provider)",
)
tab_source = (root / "astra/Models/Tabs/BrowserTab.swift").read_text()
property_source = tab_source[tab_source.index("\tvar isDeveloperMode: Bool {"):tab_source.index("\n\tvar isHibernated:", tab_source.index("\tvar isDeveloperMode: Bool {"))]
check = r'''
import Foundation

enum Defaults {
    enum Key { case developerModeEnabled }
    static var developerModeEnabled = false
    static subscript(_: Key) -> Bool { developerModeEnabled }
}

struct ManualController { var url: URL? }
struct ManualTab {
    var internalPage: String? = nil
    var activeController: ManualController? = nil
    var currentURL: URL? = nil
MANUAL_PROPERTY
}

@MainActor
enum ProbeClient {
    static var calls = 0
    static func fetch(_ provider: BrowserUsageLimitsProvider) async throws -> [BrowserUsageWindow] {
        calls += 1
        if provider == .codex {
            try? await Task.sleep(for: .milliseconds(150))
            return [BrowserUsageWindow(title: "Codex", usedPercent: 10, resetAt: nil)]
        }
        return [BrowserUsageWindow(title: "Claude", usedPercent: 20, resetAt: nil)]
    }
}

@main
struct Check {
    static func main() async throws {
        let codex = try JSONDecoder().decode(CodexUsage.self, from: Data(#"{"rate_limit":{"primary_window":{"used_percent":25.0,"limit_window_seconds":86400,"reset_at":1700000000},"secondary_window":null}}"#.utf8))
        assert(codex.rateLimit?.primaryWindow?.usedPercent == 25)
        assert(codex.rateLimit?.primaryWindow?.limitWindowSeconds == 86400)
        let noQuota = try JSONDecoder().decode(CodexUsage.self, from: Data(#"{"rate_limit":null}"#.utf8))
        assert(noQuota.rateLimit == nil)
        do {
            _ = try JSONDecoder().decode(CodexUsage.self, from: Data(#"{"rate_limit":{"primary_window":{"used_percent":-1}}}"#.utf8))
            assertionFailure("invalid Codex percentages must be rejected")
        } catch { }
        let claude = try JSONDecoder().decode(ClaudeUsage.self, from: Data(#"{"five_hour":{"utilization":12.5,"resets_at":"2026-10-07T12:34:56.789Z"},"seven_day":{"utilization":25,"resets_at":"2026-10-07T12:34:56Z"},"seven_day_sonnet":null,"seven_day_opus":null}"#.utf8))
        assert(claude.fiveHour?.resetsAt != nil)
        assert(claude.sevenDay?.resetsAt != nil)
        let emptyClaude = try JSONDecoder().decode(ClaudeUsage.self, from: Data(#"{"five_hour":null}"#.utf8))
        assert(emptyClaude.fiveHour == nil && emptyClaude.sevenDay == nil)
        do {
            _ = try JSONDecoder().decode(ClaudeUsage.self, from: Data(#"{"five_hour":{"utilization":101}}"#.utf8))
            assertionFailure("invalid percentages must be rejected")
        } catch { }
        assert(BrowserUsageCookiePolicy.matchesDomain(host: "claude.ai", cookieDomain: ".claude.ai"))
        assert(!BrowserUsageCookiePolicy.matchesDomain(host: "evilclaude.ai", cookieDomain: ".claude.ai"))
        assert(BrowserUsageCookiePolicy.matchesPath(urlPath: "/api/usage", cookiePath: "/api"))
        assert(!BrowserUsageCookiePolicy.matchesPath(urlPath: "/apiary", cookiePath: "/api"))
        assert(BrowserUsageCookiePolicy.matchesPath(urlPath: "/api/usage", cookiePath: "/api/"))
        assert(!BrowserUsageCookiePolicy.matchesPath(urlPath: "/apix", cookiePath: "/api/"))

        Defaults.developerModeEnabled = false
        assert(!ManualTab(currentURL: URL(string: "https://example.com")).isDeveloperMode)
        Defaults.developerModeEnabled = true
        assert(ManualTab(currentURL: URL(string: "https://example.com")).isDeveloperMode)
        assert(!ManualTab(internalPage: "settings", currentURL: URL(string: "https://example.com")).isDeveloperMode)
        Defaults.developerModeEnabled = false

        let store = BrowserUsageLimitsStore(dataStore: .nonPersistent())
        let firstConsumer = UUID()
        let secondConsumer = UUID()
        store.start(provider: .codex, consumerID: firstConsumer)
        store.start(provider: .codex, consumerID: secondConsumer)
        try await Task.sleep(for: .milliseconds(20))
        assert(ProbeClient.calls == 1)
        store.stop(consumerID: firstConsumer)
        assert(store.provider == .codex)
        store.start(provider: .claude, consumerID: secondConsumer)
        try await Task.sleep(for: .milliseconds(200))
        assert(store.provider == .claude)
        assert(store.windows.first?.title == "Claude")
        assert(ProbeClient.calls == 2)
        store.stop(consumerID: secondConsumer)
        assert(store.provider == .none)
        assert(store.windows.isEmpty)
        print("Usage limits check passed")
    }
}
'''
with tempfile.TemporaryDirectory() as directory:
    check_path = Path(directory) / "usage-limits-check.swift"
    binary = Path(directory) / "usage-limits-check"
    check_path.write_text(check.replace("MANUAL_PROPERTY", property_source))
    production_path = Path(directory) / "BrowserUsageLimits.swift"
    production_path.write_text(production)
    subprocess.run(["swiftc", "-Onone", "-o", str(binary), str(production_path), str(check_path)], check=True)
    subprocess.run([str(binary)], check=True)
