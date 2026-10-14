// Protocol interoperability fixture. Run on macOS with the resolved SDK products.
import Foundation
import MCP

nonisolated enum BrowserLog {
    nonisolated enum Category { case agent }
    static func debug(_: Category, _: String, metadata _: [String: String]) {}
    static func warning(_: Category, _: String, metadata _: [String: String]) {}
    static func errorDescription(_ error: Error) -> String { String(describing: error) }
}

@main
struct BrowserUseProtocolChecks {
    @MainActor static func main() async throws {
        var calls = 0
        let tool = Tool(name: "echo", description: "Fixture", inputSchema: .object([
            "type": .string("object"), "properties": .object(["text": .object(["type": .string("string")])]),
            "required": .array([.string("text")]), "additionalProperties": .bool(false)
        ]))
        let router = BrowserAgentProtocol(token: "fixture", port: 8766, tools: .init(tools: [tool])) { parameters in
            calls += 1
            if parameters.arguments?["text"] == .string("slow") { try? await Task.sleep(for: .seconds(10)) }
            if parameters.arguments?["text"] == .string("overlap") { try? await Task.sleep(for: .milliseconds(50)) }
            return .init(content: [.text("ok")])
        }
        func send(_ method: String, _ params: [String: Any] = [:], id: Int? = 1, modern: Bool = false, version: String = "2026-07-28", name: String? = nil, override: [String: String] = [:]) async throws -> BrowserAgentHTTP.Response {
            var parameters = params
            var headers = ["authorization": "Bearer fixture", "host": "localhost:8766", "content-type": "application/json", "accept": "application/json, text/event-stream"]
            if modern {
                parameters["_meta"] = ["io.modelcontextprotocol/protocolVersion": version, "io.modelcontextprotocol/clientCapabilities": [:], "io.modelcontextprotocol/clientInfo": ["name": "fixture", "version": "1"]]
                headers["mcp-protocol-version"] = version
                headers["mcp-method"] = method
                if let name { headers["mcp-name"] = name }
            }
            headers.merge(override) { _, new in new }
            var object: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": parameters]
            if let id { object["id"] = id }
            return await router.handle(.init(method: "POST", path: "/mcp", headers: headers, body: try JSONSerialization.data(withJSONObject: object)))
        }
        func errorCode(_ response: BrowserAgentHTTP.Response) throws -> Int? {
            let object = try JSONSerialization.jsonObject(with: response.body) as! [String: Any]
            return (object["error"] as? [String: Any])?["code"] as? Int
        }
        let initResponse = try await send("initialize", ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "fixture", "version": "1"]])
        precondition(initResponse.status == 200)
        let initialized = try await send("notifications/initialized", id: nil)
        precondition(initialized.status == 202 && initialized.body.isEmpty)
        let legacyList = try await send("tools/list")
        precondition(legacyList.status == 200)
        let discovery = try await send("server/discover", modern: true)
        precondition(discovery.status == 200)
        let discoveryBody = try JSONSerialization.jsonObject(with: discovery.body) as! [String: Any]
        precondition((discoveryBody["result"] as! [String: Any])["supportedVersions"] as? [String] == BrowserAgentProtocol.supportedVersions)
        let unknownVersion = try await send("tools/list", modern: true, version: "2099-01-01")
        precondition(unknownVersion.status == 400)
        let unknownVersionCode = try errorCode(unknownVersion)
        precondition(unknownVersionCode == -32022)
        let mismatch = try await send("tools/list", modern: true, override: ["mcp-method": "tools/call"])
        let mismatchCode = try errorCode(mismatch)
        precondition(mismatchCode == -32020)
        let unsupported = try await send("resources/list", modern: true)
        precondition(unsupported.status == 404)
        let unsupportedCode = try errorCode(unsupported)
        precondition(unsupportedCode == -32601)
        for arguments: [String: Any] in [[:], ["text": 1], ["text": "ok", "extra": true]] {
            let invalid = try await send("tools/call", ["name": "echo", "arguments": arguments], modern: true, name: "echo")
            let invalidCode = try errorCode(invalid)
        precondition(invalidCode == -32602)
        }
        precondition(calls == 0, "Invalid arguments reached application handler")
        let encodedName = "=?base64?" + Data("echo".utf8).base64EncodedString() + "?="
        let success = try await send("tools/call", ["name": "echo", "arguments": ["text": "ok"]], modern: true, name: encodedName)
        precondition(success.status == 200 && calls == 1)
        let successfulBody = try JSONSerialization.jsonObject(with: success.body) as! [String: Any]
        precondition((successfulBody["result"] as! [String: Any])["resultType"] as? String == "complete")
        let unauthorized = try await send("tools/list", override: ["authorization": "Bearer wrong"])
        precondition(unauthorized.status == 401)
        let forbidden = try await send("tools/list", override: ["origin": "https://example.com"])
        precondition(forbidden.status == 403)
        let pending = Task { try await send("tools/call", ["name": "echo", "arguments": ["text": "slow"]], id: 99) }
        while calls < 2 { await Task.yield() }
        let cancellation = try await send("notifications/cancelled", ["requestId": 99], id: nil)
        precondition(cancellation.status == 202)
        let cancelled = try await pending.value
        precondition(cancelled.status == 202 && cancelled.body.isEmpty)
        let duplicateA = Task { try await send("tools/call", ["name": "echo", "arguments": ["text": "overlap"]], id: 100, modern: true, name: "echo") }
        let duplicateB = Task { try await send("tools/call", ["name": "echo", "arguments": ["text": "overlap"]], id: 100, modern: true, name: "echo") }
        let duplicateResponseA = try await duplicateA.value
        let duplicateResponseB = try await duplicateB.value
        precondition(duplicateResponseA.status == 200 && duplicateResponseB.status == 200, "Independent HTTP requests may reuse JSON-RPC IDs")
        await router.stop()
        let stopped = try await send("tools/list")
        precondition(stopped.status == 401)
        print("Legacy and modern MCP protocol fixture checks passed")
    }
}
