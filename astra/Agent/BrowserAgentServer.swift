#if os(macOS)

	import AppKit
	import Foundation
	import MCP
	import Network
	import Observation
	import Security
	import WebKit

	@MainActor
	@Observable
	final class BrowserAgentServer {
		static let shared = BrowserAgentServer()

		private(set) var isEnabled = false
		private(set) var endpoint = ""
		private(set) var status = "Disabled"
		var codexConfiguration: String {
			guard isEnabled, !endpoint.isEmpty, !token.isEmpty else { return "" }
			let value = [
				"mcpServers": [
					"astra": [
						"url": endpoint,
						"http_headers": ["Authorization": "Bearer \(token)"],
					],
				],
			]
			guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else {
				return ""
			}
			return String(decoding: data, as: UTF8.self)
		}

		private let port: UInt16 = 8766
		private let bodyLimit = 1_048_576
		private var token = ""
		private var listener: NWListener?
		private var grants: [UUID: Grant] = [:]
		private var nodeReferences: [String: NodeReference] = [:]
		private var tabTasks: [UUID: Task<Void, Never>] = [:]
		private var requestTasks: Set<UUID> = []

		private struct Grant {
			weak var tab: BrowserTab?
			weak var browser: Browser?
			let documentID: Int
			let userShared: Bool
		}

		private struct NodeReference {
			let tabID: UUID
			let documentID: Int
			let selector: String
		}

		private init() {}

		func setEnabled(_ enabled: Bool) {
			guard enabled != isEnabled else { return }
			if enabled {
				guard ProcessInfo.processInfo.environment["ASTRA_WEBSITE_APP_RUNTIME"] == nil else {
					status = "Unavailable in website app runtime"
					return
				}
				token = Self.makeToken()
				isEnabled = true
				status = "Starting"
				Task { @MainActor [weak self] in
					await self?.start()
				}
			} else {
				isEnabled = false
				token = ""
				endpoint = ""
				status = "Stopping"
				listener?.cancel()
				listener = nil
				grants.removeAll()
				nodeReferences.removeAll()
				for task in tabTasks.values {
					task.cancel()
				}
				tabTasks.removeAll()
				status = "Disabled"
			}
		}

		func isControlled(_ tabID: UUID) -> Bool {
			guard let grant = grants[tabID], grant.tab != nil, grant.browser != nil else { return false }
			return true
		}

		func share(tab: BrowserTab, in browser: Browser) {
			guard isEnabled, !browser.isPrivate, !browser.isMini, tab.internalPage == nil,
			      BrowserWindowRegistry.shared.openBrowsers.contains(where: { $0 === browser })
			else { return }
			grants[tab.id] = Grant(tab: tab, browser: browser, documentID: tab.activeController?.navigationIdentifier ?? -1, userShared: true)
		}

		func revoke(_ tabID: UUID) {
			grants.removeValue(forKey: tabID)
			nodeReferences = nodeReferences.filter { $0.value.tabID != tabID }
			tabTasks[tabID]?.cancel()
			tabTasks.removeValue(forKey: tabID)
		}

		private func start() async {
			do {
				let parameters = NWParameters.tcp
				parameters.requiredLocalEndpoint = .hostPort(
					host: NWEndpoint.Host("127.0.0.1"),
					port: NWEndpoint.Port(rawValue: port)!
				)
				let listener = try NWListener(using: parameters)
				self.listener = listener
				listener.stateUpdateHandler = { [weak self] state in
					Task { @MainActor in
						guard let self, self.isEnabled else { return }
						switch state {
							case .ready:
								self.endpoint = "http://127.0.0.1:\(self.port)/mcp"
								self.status = "Ready"
							case let .failed(error):
								self.status = "Failed: \(error.localizedDescription)"
								self.isEnabled = false
							default:
								break
						}
					}
				}
				listener.newConnectionHandler = { [weak self] connection in
					Task { @MainActor in self?.accept(connection) }
				}
				listener.start(queue: .main)
			} catch {
				status = "Failed: \(error.localizedDescription)"
				isEnabled = false
			}
		}

		private func accept(_ connection: NWConnection) {
			connection.start(queue: .main)
			receive(connection, buffer: Data())
		}

		private func receive(_ connection: NWConnection, buffer: Data) {
			connection.receive(minimumIncompleteLength: 1, maximumLength: bodyLimit + 16384) { [weak self] data, _, isComplete, error in
				Task { @MainActor in
					guard let self else { connection.cancel(); return }
					var buffer = buffer
					if let data {
						buffer.append(data)
					}
					if buffer.count > self.bodyLimit + 16384 {
						self.write(.badRequest, body: Self.errorBody("Request too large"), to: connection)
						return
					}
					if let request = HTTPRequestParser.parse(buffer, bodyLimit: self.bodyLimit) {
						await self.handle(request, on: connection)
					} else if isComplete || error != nil {
						self.write(.badRequest, body: Self.errorBody("Malformed HTTP request"), to: connection)
					} else {
						self.receive(connection, buffer: buffer)
					}
				}
			}
		}

		private func handle(_ request: ParsedHTTPRequest, on connection: NWConnection) async {
			guard request.path == "/mcp" else {
				write(.notFound, body: Self.errorBody("Not found"), to: connection)
				return
			}
			guard request.headers["authorization"] == "Bearer \(token)" else {
				write(.unauthorized, body: Self.errorBody("Unauthorized"), to: connection)
				return
			}
			guard request.headers["host"] == "127.0.0.1:\(port)" || request.headers["host"] == "localhost:\(port)" else {
				write(.forbidden, body: Self.errorBody("Invalid host"), to: connection)
				return
			}
			if let origin = request.headers["origin"], origin != "http://127.0.0.1:\(port)", origin != "http://localhost:\(port)" {
				write(.forbidden, body: Self.errorBody("Invalid origin"), to: connection)
				return
			}
			guard request.method == "POST", request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
				write(.methodNotAllowed, body: Self.errorBody("POST application/json required"), to: connection)
				return
			}
			guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
			      let method = object["method"] as? String
			else {
				write(.badRequest, body: Self.errorBody("Invalid JSON-RPC request"), to: connection)
				return
			}
			let id = object["id"] as? Any
			let result: Any
			switch method {
				case "initialize":
					result = ["protocolVersion": "2025-06-18", "capabilities": ["tools": [:]], "serverInfo": ["name": "Astra", "version": "1"]]
				case "notifications/initialized":
					write(.accepted, body: Data(), to: connection)
					return
				case "ping":
					result = [:]
				case "tools/list":
					result = ["tools": toolDefinitions()]
				case "tools/call":
					guard let params = object["params"] as? [String: Any], let name = params["name"] as? String else {
						result = ["isError": true, "content": [["type": "text", "text": "Missing tool name"]]]
						break
					}
					let arguments = params["arguments"] as? [String: Any] ?? [:]
					result = await callTool(name, arguments: arguments)
				default:
					write(.badRequest, body: Self.errorBody("Method not found"), to: connection)
					return
			}
			write(.ok, body: Self.rpcResult(id: id, result: result), to: connection)
		}

		private func toolDefinitions() -> [[String: Any]] {
			[
				["name": "list_tabs", "description": "List shared tabs.", "inputSchema": ["type": "object", "properties": [:]]],
				["name": "open_tab", "description": "Open a credential-free HTTP or HTTPS tab.", "inputSchema": ["type": "object", "properties": ["url": ["type": "string"]], "required": ["url"]]],
				["name": "read_page", "description": "Read rendered page text without form values.", "inputSchema": ["type": "object", "properties": ["tabID": ["type": "string"]], "required": ["tabID"]]],
				["name": "snapshot", "description": "Snapshot visible interactive roles and text.", "inputSchema": ["type": "object", "properties": ["tabID": ["type": "string"]], "required": ["tabID"]]],
				["name": "navigate", "description": "Navigate a shared tab.", "inputSchema": ["type": "object", "properties": ["tabID": ["type": "string"], "url": ["type": "string"]], "required": ["tabID", "url"]]],
				["name": "click", "description": "Click a temporary snapshot node reference.", "inputSchema": ["type": "object", "properties": ["tabID": ["type": "string"], "ref": ["type": "string"]], "required": ["tabID", "ref"]]],
				["name": "fill", "description": "Fill a non-password input.", "inputSchema": ["type": "object", "properties": ["tabID": ["type": "string"], "ref": ["type": "string"], "value": ["type": "string"]], "required": ["tabID", "ref", "value"]]],
				["name": "select_option", "description": "Select an option.", "inputSchema": ["type": "object", "properties": ["tabID": ["type": "string"], "ref": ["type": "string"], "value": ["type": "string"]], "required": ["tabID", "ref", "value"]]],
				["name": "scroll", "description": "Scroll the page by a bounded amount.", "inputSchema": ["type": "object", "properties": ["tabID": ["type": "string"], "dy": ["type": "number"]], "required": ["tabID"]]],
				["name": "screenshot", "description": "Capture the shared tab.", "inputSchema": ["type": "object", "properties": ["tabID": ["type": "string"]], "required": ["tabID"]]],
				["name": "wait", "description": "Wait for bounded page progress.", "inputSchema": ["type": "object", "properties": ["tabID": ["type": "string"], "text": ["type": "string"], "timeout": ["type": "number"]], "required": ["tabID"]]],
			]
		}

		private func callTool(_ name: String, arguments: [String: Any]) async -> [String: Any] {
			do {
				switch name {
					case "list_tabs":
						return try textResult(listTabs())
					case "open_tab":
						guard let raw = arguments["url"] as? String, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased()) else { throw AgentError.invalidArgument }
						let browser = BrowserWindowRegistry.shared.openBrowsers.first(where: { !$0.isPrivate && !$0.isMini })
						guard let browser else { throw AgentError.noBrowser }
						let tab = browser.openHistoryURL(BrowserAddress.withoutCredentials(url), inBackground: false)
						share(tab: tab, in: browser)
						return try textResult(["tabID": tab.id.uuidString, "url": url.absoluteString])
					case "read_page":
						let (tab, controller) = try controlled(arguments)
						let documentID = controller.navigationIdentifier
						let page = try await BrowserAIPageText.extract(from: controller)
						guard isValid(tab, documentID: documentID) else { throw AgentError.revoked }
						return try textResult(["title": page.title, "url": BrowserAddress.withoutCredentials(page.url).absoluteString, "text": String(page.text.prefix(100_000))])
					case "snapshot":
						let (tab, controller) = try controlled(arguments)
						let documentID = controller.navigationIdentifier
						guard let webView = controller.webViewIfLoaded else { throw AgentError.pageUnavailable }
						let value = try await webView.callAsyncJavaScript(Self.snapshotScript, arguments: [:], in: nil, contentWorld: .defaultClient)
						guard isValid(tab, documentID: documentID) else { throw AgentError.revoked }
						if let snapshot = value as? [String: Any], let refs = snapshot["refs"] as? [[String: Any]] {
							for ref in refs.compactMap({ $0["ref"] as? String }) {
								nodeReferences[ref] = NodeReference(tabID: tab.id, documentID: documentID, selector: "[data-astra-ref='\(ref)']")
							}
						}
						return try textResult(value ?? [:])
					case "navigate":
						let (tab, controller) = try controlled(arguments)
						guard let raw = arguments["url"] as? String, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased()) else { throw AgentError.invalidArgument }
						guard isValid(tab) else { throw AgentError.revoked }
						controller.navigate(URLRequest(url: BrowserAddress.withoutCredentials(url)))
						return try textResult(["ok": true])
					case "click", "fill", "select_option", "scroll":
						let (tab, controller) = try controlled(arguments)
						guard let ref = arguments["ref"] as? String, let node = nodeReferences[ref], node.tabID == tab.id, node.documentID == controller.navigationIdentifier else { throw AgentError.staleReference }
						guard let webView = controller.webViewIfLoaded else { throw AgentError.pageUnavailable }
						let value = try await webView.callAsyncJavaScript(Self.actionScript(name: name, selector: node.selector, value: arguments["value"] as? String, dy: arguments["dy"] as? Double), arguments: [:], in: nil, contentWorld: .defaultClient)
						guard isValid(tab, documentID: node.documentID) else { throw AgentError.revoked }
						return try textResult(value ?? ["ok": true])
					case "screenshot":
						let (tab, controller) = try controlled(arguments)
						let documentID = controller.navigationIdentifier
						let capture = try await controller.captureScreenshot()
						guard isValid(tab, documentID: documentID) else { throw AgentError.revoked }
						guard let tiff = capture.image.tiffRepresentation,
						      let bitmap = NSBitmapImageRep(data: tiff),
						      let png = bitmap.representation(using: .png, properties: [:]) else { throw AgentError.pageUnavailable }
						return try textResult(["mimeType": "image/png", "data": png.base64EncodedString()])
					case "wait":
						let (tab, controller) = try controlled(arguments)
						let deadline = Date().addingTimeInterval(min(max(arguments["timeout"] as? Double ?? 2, 0), 10))
						let wanted = arguments["text"] as? String
						repeat {
							try Task.checkCancellation()
							if let wanted, let page = try? await BrowserAIPageText.extract(from: controller), page.text.localizedCaseInsensitiveContains(wanted) {
								return try textResult(["matched": true])
							}
							if Date() >= deadline {
								break
							}
							try await Task.sleep(for: .milliseconds(100))
						} while isValid(tab)
						return try textResult(["matched": false])
					default:
						throw AgentError.unknownTool
				}
			} catch {
				return ["isError": true, "content": [["type": "text", "text": error.localizedDescription]]]
			}
		}

		private func listTabs() -> [[String: Any]] {
			grants.compactMap { id, grant in
				guard let tab = grant.tab, let browser = grant.browser else { return nil }
				return ["tabID": id.uuidString, "title": tab.title, "url": tab.copyableURL?.absoluteString ?? "", "windowID": browser.windowID.uuidString]
			}
		}

		private func controlled(_ arguments: [String: Any]) throws -> (BrowserTab, BrowserController) {
			guard let raw = arguments["tabID"] as? String, let id = UUID(uuidString: raw), let grant = grants[id], let tab = grant.tab, let controller = tab.activeController else { throw AgentError.notControlled }
			guard grant.browser != nil, isValid(tab) else { throw AgentError.revoked }
			return (tab, controller)
		}

		private func isValid(_ tab: BrowserTab, documentID: Int? = nil) -> Bool {
			guard let grant = grants[tab.id], grant.tab === tab, grant.browser != nil, let controller = tab.activeController else { return false }
			return documentID.map { $0 == controller.navigationIdentifier } ?? true
		}

		private func textResult(_ value: Any) throws -> [String: Any] {
			let data = try JSONSerialization.data(withJSONObject: value)
			return ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]]]
		}

		private static func makeToken() -> String {
			var bytes = [UInt8](repeating: 0, count: 32)
			_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
			return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: CharacterSet(charactersIn: "="))
		}

		private static func rpcResult(id: Any?, result: Any) -> Data {
			var value: [String: Any] = ["jsonrpc": "2.0", "result": result]
			value["id"] = id ?? NSNull()
			return (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
		}

		private static func errorBody(_ message: String) -> Data {
			(try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "error": ["code": -32600, "message": message], "id": NSNull()])) ?? Data()
		}

		private func write(_ response: HTTPStatus, body: Data, to connection: NWConnection) {
			let header = "HTTP/1.1 \(response.code) \(response.reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
			connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
		}

		private static let snapshotScript = """
		(() => { const refs = []; const nodes = document.querySelectorAll('a,button,input:not([type=password]),textarea,select,[role],h1,h2,h3'); for (const [index,node] of Array.from(nodes).entries()) { if (refs.length >= 200) break; const r = 'n' + index; node.setAttribute('data-astra-ref', r); refs.push({ref:r, role:node.getAttribute('role') || node.tagName.toLowerCase(), text:(node.innerText || node.getAttribute('aria-label') || node.value || '').slice(0,500)}); } return {title:document.title,url:location.href,refs}; })()
		"""

		private static func actionScript(name: String, selector: String, value: String?, dy: Double?) -> String {
			let encodedSelector = String(data: (try? JSONSerialization.data(withJSONObject: selector)) ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
			let encodedValue = String(data: (try? JSONSerialization.data(withJSONObject: value ?? "")) ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
			switch name {
				case "click": return "(() => { const n=document.querySelector(\(encodedSelector)); if (!n) throw new Error('stale reference'); n.click(); return {ok:true}; })()"
				case "fill": return "(() => { const n=document.querySelector(\(encodedSelector)); if (!n || n.type === 'password') throw new Error('password fields are not controlled'); n.focus(); n.value=\(encodedValue); n.dispatchEvent(new Event('input',{bubbles:true})); n.dispatchEvent(new Event('change',{bubbles:true})); return {ok:true}; })()"
				case "select_option": return "(() => { const n=document.querySelector(\(encodedSelector)); if (!n || n.tagName !== 'SELECT') throw new Error('select reference required'); n.value=\(encodedValue); n.dispatchEvent(new Event('change',{bubbles:true})); return {ok:true}; })()"
				default: return "(() => { window.scrollBy(0, \(dy ?? 0)); return {ok:true}; })()"
			}
		}
	}

	private enum AgentError: LocalizedError {
		case invalidArgument, noBrowser, pageUnavailable, revoked, staleReference, notControlled, unknownTool
		var errorDescription: String? {
			switch self {
				case .invalidArgument: "Invalid argument"
				case .noBrowser: "No eligible browser window"
				case .pageUnavailable: "Page unavailable"
				case .revoked: "Tab grant revoked or document changed"
				case .staleReference: "Node reference is stale"
				case .notControlled: "Tab is not shared with Astra Agent"
				case .unknownTool: "Unknown tool"
			}
		}
	}

	private enum HTTPStatus {
		case ok, accepted, badRequest, unauthorized, forbidden, notFound, methodNotAllowed
		var code: Int {
			switch self { case .ok: 200; case .accepted: 202; case .badRequest: 400; case .unauthorized: 401; case .forbidden: 403; case .notFound: 404; case .methodNotAllowed: 405 }
		}

		var reason: String {
			switch self { case .ok: "OK"; case .accepted: "Accepted"; case .badRequest: "Bad Request"; case .unauthorized: "Unauthorized"; case .forbidden: "Forbidden"; case .notFound: "Not Found"; case .methodNotAllowed: "Method Not Allowed" }
		}
	}

	private struct ParsedHTTPRequest {
		let method: String
		let path: String
		let headers: [String: String]
		let body: Data
	}

	private enum HTTPRequestParser {
		static func parse(_ data: Data, bodyLimit: Int) -> ParsedHTTPRequest? {
			guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
			let head = String(decoding: data[..<separator.lowerBound], as: UTF8.self)
			let lines = head.components(separatedBy: "\r\n")
			guard let request = lines.first?.split(separator: " ", maxSplits: 2).map(String.init), request.count == 3, request[2] == "HTTP/1.1" else { return nil }
			var headers: [String: String] = [:]
			for line in lines.dropFirst() {
				guard let colon = line.firstIndex(of: ":") else { return nil }
				let name = line[..<colon].lowercased()
				let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
				guard headers[name] == nil else { return nil }
				headers[name] = value
			}
			guard headers["transfer-encoding"] == nil, let length = headers["content-length"].flatMap(Int.init), (0 ... bodyLimit).contains(length) else { return nil }
			let bodyStart = separator.upperBound
			guard data.count - bodyStart >= length else { return nil }
			return ParsedHTTPRequest(method: request[0], path: request[1], headers: headers, body: Data(data[bodyStart ..< bodyStart + length]))
		}
	}

#endif
