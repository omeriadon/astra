import Foundation

// Run: swiftc browser/Models/BrowserTheme.swift Checks/BrowserThemeIdentityCheck.swift -o /tmp/browser-theme-identity-check && /tmp/browser-theme-identity-check
@main
struct BrowserThemeIdentityCheck {
	static func main() throws {
		for usesGradient in [false, true] {
			let legacyTheme = Data("{\"usesGradient\":\(usesGradient)}".utf8)
			let first = try JSONDecoder().decode(BrowserTheme.self, from: legacyTheme)
			let second = try JSONDecoder().decode(BrowserTheme.self, from: legacyTheme)
			let firstIDs = first.meshColorPoints.map(\.id)
			let secondIDs = second.meshColorPoints.map(\.id)
			guard firstIDs.count == (usesGradient ? 2 : 1), firstIDs == secondIDs else {
				print("FAIL: migrated color point identities change on every decode")
				exit(1)
			}

			let saved = try JSONEncoder().encode(first)
			let restored = try JSONDecoder().decode(BrowserTheme.self, from: saved)
			guard restored.meshColorPoints.map(\.id) == firstIDs else {
				print("FAIL: saved color point identities changed")
				exit(1)
			}
		}

		var emptyTheme = BrowserTheme()
		emptyTheme.meshColorPoints.removeAll()
		let restoredEmpty = try JSONDecoder().decode(BrowserTheme.self, from: JSONEncoder().encode(emptyTheme))
		guard restoredEmpty.meshColorPoints.isEmpty else {
			print("FAIL: empty theme gained color points during decoding")
			exit(1)
		}
		print("PASS: migrated and saved color point identities remain stable")
	}
}
