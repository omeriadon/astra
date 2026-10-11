import Foundation

@main
struct BrowserUseListenerChecks {
	@MainActor
	static func main() async {
		let server = BrowserAgentServer.shared
		server.setEnabled(true)
		for _ in 0 ..< 20 {
			if server.status != "Starting" {
				break
			}
			try? await Task.sleep(for: .milliseconds(50))
		}
		try? await Task.sleep(for: .milliseconds(250))
		let enabled = server.isEnabled && server.status == "Ready"
		print("Listener remains enabled: \(enabled); status: \(server.status)")
		server.setEnabled(false)
		if !enabled {
			exit(1)
		}
	}
}
