// Run: swiftc astra/Models/Core/BrowserHandoffTabReference.swift checks/handoff-payload-check.swift -o /tmp/astra-handoff-check && /tmp/astra-handoff-check
import Foundation

@main
struct BrowserHandoffPayloadCheck {
	static func main() {
		let id = UUID(uuidString: "9F4CFC69-A843-4D56-A947-9B4001E9A002")!
		let outgoing = BrowserHandoffTabReference(tabID: id)
		let incoming = BrowserHandoffTabReference(userInfo: outgoing.userInfo)
		assert(incoming == outgoing, "Handoff must preserve the exact tab UUID")
		assert(BrowserHandoffTabReference(userInfo: nil) == nil)
		assert(BrowserHandoffTabReference(userInfo: [BrowserHandoffTabReference.tabIDKey: id.uuidString]) == nil)
		assert(BrowserHandoffTabReference(userInfo: [
			BrowserHandoffTabReference.versionKey: 2,
			BrowserHandoffTabReference.tabIDKey: id.uuidString,
		]) == nil)
		assert(BrowserHandoffTabReference(userInfo: [
			BrowserHandoffTabReference.versionKey: 1,
			BrowserHandoffTabReference.tabIDKey: "https://example.com",
		]) == nil, "URLs must never be interpreted as tab IDs")
		assert(BrowserHandoffTabReference(userInfo: [
			BrowserHandoffTabReference.versionKey: 1,
			BrowserHandoffTabReference.tabIDKey: UUID().uuidString,
		]) != incoming, "An unrelated tab must not be treated as the same tab")
		print("Handoff tab identity checks passed")
	}
}
