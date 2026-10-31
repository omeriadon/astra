import Foundation

/// A Handoff reference preserves the identity of a synced tab. The URL is
/// intentionally not part of this payload: falling back to a URL would create
/// a second, unrelated tab on the receiving device.
struct BrowserHandoffTabReference: Equatable {
	nonisolated static let activityType = "com.omeriadon.astra.browse"
	static let tabIDKey = "tabID"
	static let versionKey = "version"
	static let version = 1

	let tabID: UUID

	init(tabID: UUID) {
		self.tabID = tabID
	}

	init?(userInfo: [AnyHashable: Any]?) {
		guard let userInfo,
		      let version = userInfo[Self.versionKey] as? Int,
		      version == Self.version,
		      let rawID = userInfo[Self.tabIDKey] as? String,
		      let tabID = UUID(uuidString: rawID)
		else { return nil }
		self.tabID = tabID
	}

	var userInfo: [AnyHashable: Any] {
		[Self.versionKey: Self.version, Self.tabIDKey: tabID.uuidString]
	}
}
