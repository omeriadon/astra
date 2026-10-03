import CryptoKit
import Foundation
import Security

@MainActor
enum BrowserRestorationStore {
	private static var key: SymmetricKey?

	static func prepare() async {
		guard key == nil else { return }
		let data = await Task.detached(priority: .utility) {
			loadKey()
		}.value
		if let data {
			key = SymmetricKey(data: data)
		}
	}

	static func seal(_ data: Data, for url: URL) -> Data? {
		guard let key, data.count <= 4 * 1024 * 1024 else { return nil }
		return try? AES.GCM.seal(data, using: key, authenticating: Data(url.absoluteString.utf8)).combined
	}

	static func open(_ data: Data, for url: URL) -> Data? {
		guard let key, data.count <= 4 * 1024 * 1024 + 64,
		      let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
		return try? AES.GCM.open(box, using: key, authenticating: Data(url.absoluteString.utf8))
	}

	private nonisolated static func loadKey() -> Data? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "browser") + ".restoration",
			kSecAttrAccount as String: "key",
		]
		var lookup = query
		lookup[kSecReturnData as String] = true
		lookup[kSecMatchLimit as String] = kSecMatchLimitOne
		var result: CFTypeRef?
		let status = SecItemCopyMatching(lookup as CFDictionary, &result)
		if status == errSecSuccess {
			guard let data = result as? Data, data.count == 32 else { return nil }
			return data
		}
		guard status == errSecItemNotFound else { return nil }
		let created = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
		var item = query
		item[kSecValueData as String] = created
		item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		let added = SecItemAdd(item as CFDictionary, nil)
		if added == errSecSuccess {
			return created
		}
		if added == errSecDuplicateItem,
		   SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
		   let existing = result as? Data, existing.count == 32
		{
			return existing
		}
		return nil
	}
}
