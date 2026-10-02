import Foundation

@main
struct BrowserSitePreferenceCheck {
	static func main() throws {
		let canonical = BrowserSiteOrigin.canonical(
			for: URL(string: "HTTPS://User:Pass@EXAMPLE.com:443/path?q=1#part")!
		)
		assert(canonical == "https://example.com")
		assert(BrowserSiteOrigin.canonical(for: URL(fileURLWithPath: "/tmp/page.html")) == nil)

		let now = Date(timeIntervalSince1970: 1_800_000_000)
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
		let tiedReset = BrowserSiteZoomEntry(zoom: nil, modifiedAt: now)
		let tiedZoom = BrowserSiteZoomEntry(zoom: 2, modifiedAt: now)
		assert(BrowserSiteZoomEntry.preferred(tiedReset, tiedZoom).zoom == nil)
		assert(BrowserSiteZoomEntry.preferred(tiedZoom, tiedReset).zoom == nil)

		let legacy = Data(#"{"entries":{}}"#.utf8)
		assert(BrowserSiteZoomDocument.decodeSupported(legacy)?.version == 1)
		let future = Data(#"{"version":2,"entries":{}}"#.utf8)
		assert(BrowserSiteZoomDocument.decodeSupported(future) == nil)
		assert(BrowserSiteZoomDocument.decodeSupported(Data([0xFF])) == nil)

		let left = try syncedValue(first)
		let right = try syncedValue(second)
		let merged = try BrowserSiteZoomDocument.mergeSyncValues(left, right).unwrap()
		let mergedDocument = try decodedSyncedValue(merged)
		assert(mergedDocument.entries.count == 2)
		let reverseMerge = try BrowserSiteZoomDocument.mergeSyncValues(right, left).unwrap()
		assert(merged == reverseMerge)
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
