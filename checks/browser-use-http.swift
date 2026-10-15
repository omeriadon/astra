import Foundation

@main
struct BrowserUseHTTPChecks {
	@MainActor
	static func main() async throws {
		let server = BrowserAgentServer.shared
		precondition(!server.isEnabled)
		server.setEnabled(true)
		for _ in 0 ..< 100 {
			if !server.endpoint.isEmpty {
				break
			}
			try await Task.sleep(for: .milliseconds(50))
		}
		precondition(server.status == "Ready", server.status)
		let endpoint = URL(string: server.endpoint)!
		let credential = server.codexConfiguration.components(separatedBy: "Bearer ")[1].components(separatedBy: "\"")[0]
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = 5
		let session = URLSession(configuration: configuration)

		func request(_ object: [String: Any], authorized: Bool = true, origin: String? = nil, method: String = "POST", bearer: String? = nil) async throws -> (Data, Int) {
			var request = URLRequest(url: endpoint)
			request.httpMethod = method
			request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version")
			if authorized {
				request.setValue("Bearer " + (bearer ?? credential), forHTTPHeaderField: "Authorization")
			}
			if let origin {
				request.setValue(origin, forHTTPHeaderField: "Origin")
			}
			if method == "POST" {
				request.httpBody = try JSONSerialization.data(withJSONObject: object)
			}
			let (data, response) = try await session.data(for: request)
			return (data, (response as! HTTPURLResponse).statusCode)
		}

		let initialize: [String: Any] = [
			"jsonrpc": "2.0", "id": 1, "method": "initialize",
			"params": ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "Astra Checks", "version": "1"]],
		]
		let unauthorized = try await request(initialize, authorized: false)
		precondition(unauthorized.1 == 401)
		let forbidden = try await request(initialize, origin: "https://example.com")
		precondition(forbidden.1 == 403)
		let initialized = try await request(initialize)
		precondition(initialized.1 == 200)
		let initialization = try JSONSerialization.jsonObject(with: initialized.0) as! [String: Any]
		precondition((initialization["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-11-25")
		let notification = try await request(["jsonrpc": "2.0", "method": "notifications/initialized"])
		precondition(notification.1 == 202)
		let listed = try await request(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
		precondition(listed.1 == 200)
		let catalog = try JSONSerialization.jsonObject(with: listed.0) as! [String: Any]
		let tools = (catalog["result"] as! [String: Any])["tools"] as! [[String: Any]]
		let actualToolNames = tools.compactMap { $0["name"] as? String }
		let expectedToolNames: Set<String> = Set([
			"list_tabs", "open_tab", "navigate", "read_page", "snapshot", "screenshot",
		]).union(BrowserAgentToolCatalog.pageActions).union(BrowserAgentToolCatalog.waits)
		precondition(actualToolNames.count == expectedToolNames.count && Set(actualToolNames) == expectedToolNames,
		             "Unexpected or duplicate browser-use tools: \(actualToolNames)")
		let unknownTab = try await request(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "read_page", "arguments": ["tabID": UUID().uuidString]]])
		let denied = try JSONSerialization.jsonObject(with: unknownTab.0) as! [String: Any]
		precondition((denied["result"] as! [String: Any])["isError"] as? Bool == true)
		let get = try await request([:], method: "GET")
		precondition(get.1 == 405)
		precondition(BrowserAgentServer.webURL(URL(string: "http://user:password@example.com")) == nil)
		precondition(BrowserAgentServer.webURL(URL(string: "file:///tmp/example.html")) == nil)
		precondition(BrowserAgentServer.webURL(URL(string: "https://example.com")) != nil)
		let browser = Browser()
		BrowserWindowRegistry.shared.openBrowsers = [browser]
		let tab = browser.openHistoryURL(URL(string: "https://example.com")!, inBackground: false)
		precondition(!server.isControlled(tab.id))
		server.share(tab: tab, in: browser)
		precondition(server.isControlled(tab.id))
		let reading = Task {
			try await request(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "read_page", "arguments": ["tabID": tab.id.uuidString]]])
		}
		try await Task.sleep(for: .milliseconds(75))
		server.revoke(tab.id)
		precondition(!server.isControlled(tab.id))
		let revokedResponse = try await reading.value
		let revokedData = try JSONSerialization.jsonObject(with: revokedResponse.0) as! [String: Any]
		precondition((revokedData["result"] as! [String: Any])["isError"] as? Bool == true)
		precondition(!String(decoding: revokedResponse.0, as: UTF8.self).contains("fixture-content"))
		server.share(tab: tab, in: browser)
		precondition(server.isControlled(tab.id))
		browser.isPrivate = true
		precondition(!server.isControlled(tab.id))
		browser.isPrivate = false
		browser.tabs.removeAll()
		precondition(!server.isControlled(tab.id))
		var previousCredential = credential
		for cycle in 0 ..< 5 {
			server.setEnabled(false)
			precondition(!server.isEnabled && server.codexConfiguration.isEmpty)
			server.setEnabled(true)
			// Exercise superseding a listener before its startup task runs, too.
			if cycle == 0 {
				server.setEnabled(false)
				server.setEnabled(true)
			}
			for _ in 0 ..< 100 {
				if !server.endpoint.isEmpty { break }
				try await Task.sleep(for: .milliseconds(50))
			}
			precondition(server.status == "Ready", "Restart \(cycle): \(server.status)")
			precondition(URL(string: server.endpoint) == endpoint)
			let newCredential = server.codexConfiguration.components(separatedBy: "Bearer ")[1].components(separatedBy: "\"")[0]
			precondition(newCredential != previousCredential)
			let oldCredential = try await request(initialize, bearer: previousCredential)
			precondition(oldCredential.1 == 401)
			let newSession = try await request(initialize, bearer: newCredential)
			precondition(newSession.1 == 200)
			previousCredential = newCredential
		}
		server.setEnabled(false)
		session.invalidateAndCancel()
		print("MCP protocol, authorization, origin, URL validation, grant revocation during reads, private-tab exclusion, closure, and credential rotation checks passed")
	}
}
