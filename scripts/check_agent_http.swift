import Foundation

@main
struct AgentHTTPChecks {
	@MainActor
	static func main() {
		let prefix = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:8766\r\n"
		func parse(_ text: String) -> BrowserAgentHTTPParser.Result {
			BrowserAgentHTTPParser.parse(Data(text.utf8))
		}
		func rejects(_ text: String) {
			guard case .invalid = parse(text) else {
				preconditionFailure("Malformed request accepted")
			}
		}

		guard case let .request(request) = parse(prefix + "Content-Length: 2\r\n\r\n{}") else {
			preconditionFailure("Valid POST rejected")
		}
		precondition(request.method == "POST")
		precondition(request.path == "/mcp")
		precondition(request.body == Data("{}".utf8))
		guard case .incomplete = parse(prefix + "Content-Length: 2\r\n\r\n{") else {
			preconditionFailure("Partial request was not retained")
		}
		guard case .request = parse("GET /mcp HTTP/1.1\r\nHost: localhost:8766\r\n\r\n") else {
			preconditionFailure("Valid GET rejected before MCP transport")
		}

		rejects(prefix + "Content-Length: 0\r\ncontent-length: 0\r\n\r\n")
		rejects(prefix + "Content-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n")
		rejects(prefix + "Content-Length: -1\r\n\r\n")
		rejects(prefix + "Content-Length: +1\r\n\r\n")
		rejects(prefix + "Content-Length: 1048577\r\n\r\n")
		rejects(prefix + "Content-Length: 0\r\n\r\nextra")
		rejects(prefix + "Content-Length: 0\r\n Authorization: secret\r\n\r\n")
		rejects(prefix + "Content-Length: 0\r\nAuthorization: secret\u{0}\r\n\r\n")
		rejects("POST /mcp HTTP/1.1\r\nContent-Length: 0\r\n\r\n")
		rejects(prefix + "\r\n")
		rejects(String(repeating: "a", count: BrowserAgentHTTPParser.headerLimit + 1))
		print("Agent HTTP framing checks passed")
	}
}
