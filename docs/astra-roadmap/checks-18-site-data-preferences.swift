import Foundation

@main
struct BrowserSitePreferenceCheck {
	static func main() throws {
		let canonical = BrowserSiteOrigin.canonical(
			for: URL(string: "HTTPS://User:Pass@EXAMPLE.com:443/path?q=1#part")!
		)
		assert(canonical == "https://example.com")
		let compressedIPv6 = BrowserSiteOrigin.canonical(for: URL(string: "https://[2001:DB8::1]:443/a")!)
		let expandedIPv6 = BrowserSiteOrigin.canonical(for: URL(string: "https://[2001:db8:0:0::1]/b")!)
		assert(compressedIPv6 == "https://[2001:db8::1]")
		assert(compressedIPv6 == expandedIPv6)
		assert(BrowserSiteOrigin.canonical(for: URL(fileURLWithPath: "/tmp/page.html")) == nil)

		let now = Date(timeIntervalSince1970: 1_700_000_000)
		var utc = Calendar(identifier: .gregorian)
		utc.timeZone = TimeZone(secondsFromGMT: 0)!
		assert(BrowserWebsiteDataRange.lastHour.modifiedSince(now: now) == now.addingTimeInterval(-3600))
		assert(BrowserWebsiteDataRange.today.modifiedSince(now: now, calendar: utc) == utc.startOfDay(for: now))
		assert(BrowserWebsiteDataRange.allTime.modifiedSince(now: now) == .distantPast)

		let first = BrowserSiteZoomDocument(entries: [
			"https://a.example": BrowserSiteZoomEntry(zoom: 1.25, modifiedAt: now),
		])
		let second = BrowserSiteZoomDocument(entries: [
			"https://b.example": BrowserSiteZoomEntry(zoom: 1.5, modifiedAt: now),
		])
		assert(first.merging(second) == second.merging(first))
		assert(first.merging(second).entries.count == 2)

		let reset = BrowserSiteZoomDocument(entries: [
			"https://a.example": BrowserSiteZoomEntry(zoom: nil, modifiedAt: now.addingTimeInterval(1)),
		])
		assert(reset.merging(first).entries["https://a.example"]?.zoom == nil)
		let resetData = try reset.encoded().unwrap()
		assert(BrowserSiteZoomDocument.decodeSupported(resetData)?.entries["https://a.example"]?.zoom == nil)
		let tiedReset = BrowserSiteZoomEntry(zoom: nil, modifiedAt: now)
		let tiedZoom = BrowserSiteZoomEntry(zoom: 2, modifiedAt: now)
		assert(BrowserSiteZoomEntry.preferred(tiedReset, tiedZoom).zoom == nil)
		assert(BrowserSiteZoomEntry.preferred(tiedZoom, tiedReset).zoom == nil)

		let legacy = Data(#"{"entries":{}}"#.utf8)
		assert(BrowserSiteZoomDocument.decodeSupported(legacy)?.version == 1)
		let future = Data(#"{"version":2,"entries":{}}"#.utf8)
		assert(BrowserSiteZoomDocument.decodeSupported(future) == nil)
		let futureTimestamp = Data(#"{"version":1,"entries":{"https://future.example":{"zoom":2,"modifiedAt":\#(Date.now.timeIntervalSinceReferenceDate + 3600)}}}"#.utf8)
		assert(BrowserSiteZoomDocument.decodeSupported(futureTimestamp) == nil)
		assert(BrowserSiteZoomDocument.decodeSupported(Data([0xFF])) == nil)
		let localLegacy = Data(#"{"entries":{"https://local.example":{"contentMode":"desktop","customUserAgent":"agent"}}}"#.utf8)
		assert(BrowserLocalSitePreferencesDocument.decodeSupported(localLegacy)?.version == 1)
		let localFuture = Data(#"{"version":2,"entries":{}}"#.utf8)
		assert(BrowserLocalSitePreferencesDocument.decodeSupported(localFuture) == nil)
		let localUnknownField = Data(#"{"version":1,"entries":{"https://local.example":{"contentMode":"desktop","customUserAgent":"agent","future":"value"}}}"#.utf8)
		assert(BrowserLocalSitePreferencesDocument.decodeSupported(localUnknownField) == nil)

		let left = try syncedValue(first)
		let right = try syncedValue(second)
		let merged = try BrowserSiteZoomDocument.mergeSyncValues(left, right).unwrap()
		let mergedDocument = try decodedSyncedValue(merged)
		assert(mergedDocument.entries.count == 2)
		let reverseMerge = try BrowserSiteZoomDocument.mergeSyncValues(right, left).unwrap()
		assert(merged == reverseMerge)
		let futureValue = try syncedValueData(future)

		let tabID = UUID()
		let tab = OpenTab(id: tabID, url: URL(string: "https://local.example")!, modifiedAt: now)
		let space = BrowserSpace(id: BrowserSpace.firstID)
		let workspace = BrowserWorkspace(spaces: [space], favouriteTabIDs: [], selectedSpaceID: space.id)
		let snapshot = BrowserSnapshot(selectedTabID: tabID)
		let localFutureSetting = SyncedSetting(value: futureValue, modifiedAt: now)
		let remoteZoom = BrowserSiteZoomDocument(entries: [
			"https://remote.example": BrowserSiteZoomEntry(zoom: 1.5, modifiedAt: now),
		])
		let remoteZoomValue = try syncedValue(remoteZoom)
		let remoteTab = OpenTab(id: UUID(), url: URL(string: "https://remote.example")!, modifiedAt: now.addingTimeInterval(1))
		let remoteVisit = BrowserVisit(
			id: UUID(),
			url: URL(string: "https://remote.example/history")!,
			title: "Remote page",
			visitedAt: now,
			modifiedAt: now
		)
		let localDocument = BrowserSyncDocument(
			tabs: [tab],
			workspace: workspace,
			bookmarks: [],
			history: [],
			browser: snapshot,
			settings: [BrowserSiteZoomDocument.defaultsKey: localFutureSetting]
		)
		let remoteDocument = BrowserSyncDocument(
			tabs: [remoteTab],
			workspace: workspace,
			bookmarks: [],
			history: [remoteVisit],
			browser: snapshot,
			settings: [BrowserSiteZoomDocument.defaultsKey: SyncedSetting(value: remoteZoomValue, modifiedAt: now.addingTimeInterval(2))]
		)
		let futureSafeMerge = localDocument.merging(remoteDocument)
		assert(localDocument.hasValidStructure && remoteDocument.hasValidStructure && futureSafeMerge.hasValidStructure)
		assert(futureSafeMerge.tabs.contains(where: { $0.id == remoteTab.id }))
		assert(futureSafeMerge.history.contains(where: { $0.id == remoteVisit.id }))
		assert(futureSafeMerge.settings[BrowserSiteZoomDocument.defaultsKey] == localFutureSetting)

		let invalidTimestampValue = try syncedValueData(futureTimestamp)
		let invalidTimestampSetting = SyncedSetting(value: invalidTimestampValue, modifiedAt: now.addingTimeInterval(2))
		let supportedLocalSetting = SyncedSetting(value: left, modifiedAt: now)
		let supportedLocalDocument = BrowserSyncDocument(
			tabs: [tab],
			workspace: workspace,
			bookmarks: [],
			history: [],
			browser: snapshot,
			settings: [BrowserSiteZoomDocument.defaultsKey: supportedLocalSetting]
		)
		let invalidRemoteDocument = BrowserSyncDocument(
			tabs: [remoteTab],
			workspace: workspace,
			bookmarks: [],
			history: [remoteVisit],
			browser: snapshot,
			settings: [BrowserSiteZoomDocument.defaultsKey: invalidTimestampSetting]
		)
		let invalidTimestampMerge = supportedLocalDocument.merging(invalidRemoteDocument)
		assert(invalidRemoteDocument.hasValidStructure && invalidTimestampMerge.hasValidStructure)
		assert(invalidTimestampMerge.tabs.contains(where: { $0.id == remoteTab.id }))
		assert(invalidTimestampMerge.history.contains(where: { $0.id == remoteVisit.id }))
		assert(invalidTimestampMerge.settings[BrowserSiteZoomDocument.defaultsKey] == supportedLocalSetting)

		let equalTimeRemoteDocument = BrowserSyncDocument(
			tabs: [remoteTab],
			workspace: workspace,
			bookmarks: [],
			history: [remoteVisit],
			browser: snapshot,
			settings: [BrowserSiteZoomDocument.defaultsKey: SyncedSetting(value: right, modifiedAt: now)]
		)
		let equalTimeForward = supportedLocalDocument.merging(equalTimeRemoteDocument)
		let equalTimeReverse = equalTimeRemoteDocument.merging(supportedLocalDocument)
		let mergedZoomSetting = try equalTimeForward.settings[BrowserSiteZoomDocument.defaultsKey].unwrap()
		let mergedZoomValue = try mergedZoomSetting.value.unwrap()
		let mergedZoomDocument = try decodedSyncedValue(mergedZoomValue)
		assert(equalTimeForward == equalTimeReverse)
		assert(mergedZoomDocument.entries.count == 2)
	}

	private static func syncedValue(_ document: BrowserSiteZoomDocument) throws -> Data {
		let documentData = try document.encoded().unwrap()
		return try PropertyListSerialization.data(
			fromPropertyList: ["value": documentData],
			format: .binary,
			options: 0
		)
	}

	private static func decodedSyncedValue(_ value: Data) throws -> BrowserSiteZoomDocument {
		let propertyList = try PropertyListSerialization.propertyList(from: value, format: nil)
		let dictionary = try (propertyList as? [String: Data]).unwrap()
		return try JSONDecoder().decode(BrowserSiteZoomDocument.self, from: dictionary["value"].unwrap())
	}

	private static func syncedValueData(_ documentData: Data) throws -> Data {
		try PropertyListSerialization.data(
			fromPropertyList: ["value": documentData],
			format: .binary,
			options: 0
		)
	}
}

private extension Optional {
	func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
		guard let value = self else {
			throw CheckError(file: file, line: line)
		}
		return value
	}
}

private struct CheckError: Error {
	let file: StaticString
	let line: UInt

	init(file: StaticString, line: UInt) {
		self.file = file
		self.line = line
	}
}
