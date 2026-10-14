import Foundation
import WebKit

@main
struct BrowserUseDOMChecks {
	@MainActor
	static func main() async throws {
		let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
		view.loadHTMLString("""
		<!doctype html><html><body>
		<label for="name">Name</label><input id="name" value="must-not-be-exposed">
		<input type="password" aria-label="Hidden password" value="secret">
		<button id="go" onclick="document.getElementById('result').textContent='Clicked'">Go</button>
		<select aria-label="Choice"><option value="one">One</option><option value="two">Two</option></select>
		<p id="result"></p>
		<div id="host"></div><iframe id="frame" srcdoc="<button id='nested'>Nested</button>"></iframe>
		<script>document.getElementById('host').attachShadow({mode:'open'}).innerHTML='<button id="shadow">Shadow</button>'</script>
		</body></html>
		""", baseURL: URL(string: "https://example.com"))
		for _ in 0 ..< 100 {
			try await Task.sleep(for: .milliseconds(50))
			if !view.isLoading, await (try? view.evaluateJavaScript("document.getElementById('go') !== null")) as? Bool == true {
				break
			}
		}
		let snapshot = try await view.callAsyncJavaScript(BrowserAgentPageScripts.snapshot, arguments: ["snapshotID": "first"], in: nil, contentWorld: .defaultClient) as! [String: Any]
		let encoded = try String(decoding: JSONSerialization.data(withJSONObject: snapshot), as: UTF8.self)
		precondition(!encoded.contains("must-not-be-exposed") && !encoded.contains("Hidden password") && !encoded.contains("secret"))
		let controls = snapshot["controls"] as! [[String: Any]]
		let button = controls.first { $0["name"] as? String == "Go" }!["ref"] as! String
		let name = controls.first { $0["name"] as? String == "Name" }!["ref"] as! String
		let choice = controls.first { $0["name"] as? String == "Choice" }!["ref"] as! String
		precondition(controls.contains { $0["name"] as? String == "Shadow" })
		precondition(controls.contains { $0["name"] as? String == "Nested" })
		let fragment = try await view.callAsyncJavaScript(BrowserAgentPageScripts.action, arguments: ["operation": "get_dom_fragment", "snapshotID": "first", "ref": controls.first { $0["type"] as? String == "body" }?["ref"] ?? "", "value": "", "dy": 0, "options": ["selector": "body"]], in: nil, contentWorld: .defaultClient) as? [String: Any]
		let fragmentHTML = fragment?["html"] as? String ?? ""
		precondition(!fragmentHTML.contains("secret") && !fragmentHTML.contains("Hidden password") && !fragmentHTML.contains("must-not-be-exposed"))
		func act(_ operation: String, _ ref: String, _ value: String = "") async throws {
			_ = try await view.callAsyncJavaScript(BrowserAgentPageScripts.action, arguments: ["operation": operation, "snapshotID": "first", "ref": ref, "value": value, "dy": 0], in: nil, contentWorld: .defaultClient)
		}
		try await act("fill", name, "Updated")
		let filled = try await view.evaluateJavaScript("document.getElementById('name').value") as? String
		precondition(filled == "Updated")
		try await act("select_option", choice, "two")
		let selected = try await view.evaluateJavaScript("document.querySelector('select').value") as? String
		precondition(selected == "two")
		try await act("click", button)
		let clicked = try await view.evaluateJavaScript("document.getElementById('result').textContent") as? String
		precondition(clicked == "Clicked")
		_ = try await view.evaluateJavaScript("document.getElementById('go').outerHTML = '<button id=go>Replacement</button>'")
		var rejectedReplacement = false
		do { try await act("click", button) } catch { rejectedReplacement = true }
		precondition(rejectedReplacement)
		let wait = try await view.callAsyncJavaScript(BrowserAgentPageScripts.wait, arguments: ["snapshotID": "first", "options": ["condition": "element", "selector": "#result", "state": "visible", "timeoutMs": 1000]], in: nil, contentWorld: .defaultClient) as! [String: Any]
		precondition(wait["ok"] as? Bool == true)
		print("WebKit snapshot privacy, fill, select, click, and detached-reference checks passed")
	}
}
