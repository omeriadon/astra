import Foundation
import Security

enum BrowserSessionStore {
	private static let service = "com.omeriadon.browser.sync"
	private static let account = "session"

	static func load() throws -> String? {
		var query = baseQuery
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne

		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		if status == errSecItemNotFound {
			return nil
		}
		guard status == errSecSuccess,
		      let data = result as? Data,
		      let token = String(data: data, encoding: .utf8)
		else {
			throw BrowserSessionStoreError.keychain(status)
		}
		return token
	}

	static func save(_ token: String) throws {
		guard let data = token.data(using: .utf8) else {
			throw BrowserSessionStoreError.invalidToken
		}
		var query = baseQuery
		query[kSecValueData as String] = data
		query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

		let status = SecItemAdd(query as CFDictionary, nil)
		if status == errSecDuplicateItem {
			let update = [kSecValueData as String: data]
			let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
			guard updateStatus == errSecSuccess else {
				throw BrowserSessionStoreError.keychain(updateStatus)
			}
		} else if status != errSecSuccess {
			throw BrowserSessionStoreError.keychain(status)
		}
	}

	static func delete() throws {
		let status = SecItemDelete(baseQuery as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw BrowserSessionStoreError.keychain(status)
		}
	}

	private static var baseQuery: [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
	}
}

enum BrowserSessionStoreError: LocalizedError {
	case keychain(OSStatus)
	case invalidToken

	var errorDescription: String? {
		switch self {
			case let .keychain(status):
				"Keychain error \(status)."
			case .invalidToken:
				"The server returned an invalid session token."
		}
	}
}
