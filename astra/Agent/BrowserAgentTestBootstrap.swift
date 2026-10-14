#if DEBUG && os(macOS) && !ASTRA_WEBSITE_APP_HELPER
import AppKit
import Darwin
import Foundation
import WebKit

/// Isolated integration-test entry point. The runner copies and re-signs a Debug
/// app with a unique bundle identity, so even Foundation defaults are isolated.
@MainActor
enum BrowserAgentTestBootstrap {
    private static let prefix = "com.omeriadon.astra.mcp-test."
    static let isActive: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["ASTRA_BROWSER_USE_TEST"] == "1"
            && Bundle.main.bundleIdentifier?.hasPrefix(prefix) == true
            && (Bundle.main.bundleIdentifier?.count ?? 0) > prefix.count
    }()

    // Normal windows in the test process share cookies; private windows still
    // receive their own independent, nonpersistent WKWebsiteDataStore.
    private static var controlSource: DispatchSourceSignal?
    static let normalDataStore = WKWebsiteDataStore.nonPersistent()

    @discardableResult
    static func startIfRequested(delegate: AppDelegate) -> Bool {
        guard isActive else { return false }
        let env = ProcessInfo.processInfo.environment
        guard let path = env["ASTRA_BROWSER_USE_HANDSHAKE"], path.hasPrefix("/"),
              let runID = env["ASTRA_BROWSER_USE_RUN_ID"], !runID.isEmpty,
              runID.count <= 128 else {
            fatalError("Invalid Browser Use test bootstrap configuration")
        }
        let window = delegate.openBrowserWindow()
        BrowserAgentServer.shared.setEnabled(true)
        // Only the uniquely re-signed Debug test process can grant these capabilities.
        BrowserAgentServer.shared.allowJavaScriptEvaluation = true
        BrowserAgentServer.shared.allowNativeMutations = true
        BrowserAgentServer.shared.allowBoostMutations = true
        installControl(path: path)
        Task { @MainActor in
            for _ in 0..<200 {
                guard BrowserAgentServer.shared.isEnabled else { break }
                if BrowserAgentServer.shared.status == "Ready" { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            let server = BrowserAgentServer.shared
            guard server.status == "Ready" else {
                fatalError("Browser Use test listener failed: \(server.status)")
            }
            let payload: [String: Any] = [
                "endpoint": server.endpoint,
                "token": server.testCredential,
                "runID": runID,
                "profileID": Bundle.main.bundleIdentifier ?? "",
                "pid": Int(getpid()),
                "windowID": window.browser.windowID.uuidString,
            ]
            guard let bytes = try? JSONSerialization.data(withJSONObject: payload),
                  writePrivate(bytes, to: path) else {
                fatalError("Could not write Browser Use test handshake")
            }
        }
        return true
    }

    // Process signal plus a runner-owned private file; never an MCP endpoint.
    private static func installControl(path: String) {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler {
            Task { @MainActor in
                guard isActive, let data = try? Data(contentsOf: URL(fileURLWithPath: path + ".control")),
                      let command = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                      let action = command["action"], let nonce = command["nonce"] else { return }
                let server = BrowserAgentServer.shared
                if action == "restart" {
                    server.setEnabled(false)
                    server.setEnabled(true)
                    server.allowJavaScriptEvaluation = true
                    server.allowNativeMutations = true
                    server.allowBoostMutations = true
                } else if let id = command["tabID"].flatMap(UUID.init(uuidString:)),
                          let browser = BrowserWindowRegistry.shared.openBrowsers.first(where: { $0.tabs.contains { $0.id == id } }),
                          let tab = browser.tab(withID: id) {
                    if action == "revoke" { server.revoke(id) }
                    if action == "grant" { server.share(tab: tab, in: browser) }
                }
                let result: [String: String] = ["nonce": nonce, "token": server.testCredential, "endpoint": server.endpoint]
                if let bytes = try? JSONSerialization.data(withJSONObject: result) {
                    _ = unlink(path + ".control-result")
                    _ = writePrivate(bytes, to: path + ".control-result")
                }
            }
        }
        source.resume()
        controlSource = source
    }

    private static func writePrivate(_ bytes: Data, to path: String) -> Bool {
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }
}
#endif
