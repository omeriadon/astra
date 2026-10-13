import Foundation

/// Realistically shaped sync account: many visits, bookmarks, open tabs,
/// reading-list entries and timestamped deletion records. No network required.
private struct Entry: Encodable {
	let id: UUID
	let url: URL
	let title: String
	let modifiedAt: Date
}
private struct AccountSnapshot: Encodable {
	let selectedTabID: UUID
	let deletedVisitsAt: [UUID: Date]
	let deletedBookmarksAt: [UUID: Date]
}
private struct AccountDocument: Encodable {
	let version: Int
	var tabs: [Entry]
	let bookmarks: [Entry]
	let readingList: [Entry]
	var history: [Entry]
	let browser: AccountSnapshot
	let settings: [String: String]
}
private struct DeviceSnapshot: Codable {
	let deviceID: UUID
	let payload: Data
}

@main
struct SyncLargeAccountCheck {
	static func main() throws {
		let timestamp = Date(timeIntervalSince1970: 1_790_000_000)
		func entries(_ count: Int, kind: String) -> [Entry] {
			(0 ..< count).map { index in
				Entry(
					id: UUID(),
					url: URL(string: "https://example.org/\(kind)/\(index)?source=reading&edition=international")!,
					title: "\(kind.capitalized) \(index): Example publication and document title for the user's browsing library",
					modifiedAt: timestamp
				)
			}
		}

		// Around tens of thousands of records, rather than a padded tiny fixture.
		let tabs = entries(400, kind: "tab")
		let bookmarks = entries(1_800, kind: "bookmark")
		let readingList = entries(350, kind: "reading")
		let history = entries(15_000, kind: "history")
		let tombstones = Dictionary(uniqueKeysWithValues: entries(2_000, kind: "deleted").map { ($0.id, timestamp) })
		let account = AccountDocument(
			version: 4,
			tabs: tabs,
			bookmarks: bookmarks,
			readingList: readingList,
			history: history,
			browser: AccountSnapshot(selectedTabID: tabs[0].id, deletedVisitsAt: tombstones, deletedBookmarksAt: [:]),
			settings: ["suggestionsEnabled": "true"]
		)
		let deviceID = UUID()
		let upload = try BrowserSyncPayloadLimits.makeUpload(deviceID: deviceID, document: account)
		assert(upload.payload.count > 2_500_000, "Fixture must be a genuinely large account")
		assert(upload.payload.count <= BrowserSyncPayloadLimits.maximumOutgoingBytes)
		let wireBody = try BrowserSyncPayloadLimits.makeEncodedUpload(deviceID: deviceID, document: account)
		assert(wireBody.count <= BrowserSyncPayloadLimits.maximumCollectedRequestBytes)
		let encodedUpload = try JSONDecoder().decode(DeviceSnapshot.self, from: wireBody)
		// Separate JSONEncoder instances may serialize dictionary keys in different
		// orders. Compare decoded content, not raw byte-for-byte JSON output.
		let sourceDocument = try JSONSerialization.jsonObject(with: upload.payload) as! NSDictionary
		let uploadedDocument = try JSONSerialization.jsonObject(with: encodedUpload.payload) as! NSDictionary
		assert(sourceDocument.isEqual(uploadedDocument))
		let wire = try JSONSerialization.jsonObject(with: wireBody) as! [String: Any]
		assert(wire["deviceID"] as? String == deviceID.uuidString)
		assert(Data(base64Encoded: wire["payload"] as! String) == encodedUpload.payload)

		// Exact 5,000,000-byte raw payload: Base64 must still fit the 7 MB body.
		let boundary = Data(repeating: 0x71, count: BrowserSyncPayloadLimits.maximumOutgoingBytes)
		let boundaryRequest = try JSONEncoder().encode(SyncRequest(deviceID: deviceID, payload: boundary))
		assert(boundaryRequest.count <= BrowserSyncPayloadLimits.maximumCollectedRequestBytes)
		let boundaryJSON = try JSONSerialization.jsonObject(with: boundaryRequest) as! [String: Any]
		assert(boundaryJSON["payload"] != nil)

		// Verify that the production serializer admits exactly 5,000,000
		// encoded JSON bytes and rejects even one more.
		let emptyJSONStringBytes = try JSONEncoder().encode(["value": ""]).count
		let exactDocument = ["value": String(repeating: "a", count: BrowserSyncPayloadLimits.maximumOutgoingBytes - emptyJSONStringBytes)]
		let exactUpload = try BrowserSyncPayloadLimits.makeUpload(deviceID: deviceID, document: exactDocument)
		assert(exactUpload.payload.count == BrowserSyncPayloadLimits.maximumOutgoingBytes)
		let exactBody = try BrowserSyncPayloadLimits.makeEncodedUpload(deviceID: deviceID, document: exactDocument)
		assert(exactBody.count <= BrowserSyncPayloadLimits.maximumCollectedRequestBytes)
		do {
			let extraByteDocument = ["value": String(repeating: "a", count: BrowserSyncPayloadLimits.maximumOutgoingBytes - emptyJSONStringBytes + 1)]
			_ = try BrowserSyncPayloadLimits.makeUpload(deviceID: deviceID, document: extraByteDocument)
			fatalError("The one-byte-over-limit document was accepted")
		} catch is BrowserSyncPayloadError {
			// Expected: the raw document, not Base64 body size, is bounded.
		}

		// An over-budget account is rejected before any network call; no records
		// are altered in the source document, and the error reports the real limit.
		var tooLarge = account
		tooLarge.history += entries(30_000, kind: "older-history")
		let originalVisitCount = tooLarge.history.count
		let oversizeBytes = try JSONEncoder().encode(tooLarge).count
		assert(oversizeBytes > BrowserSyncPayloadLimits.maximumOutgoingBytes)
		do {
			_ = try BrowserSyncPayloadLimits.makeUpload(deviceID: deviceID, document: tooLarge)
			fatalError("Oversize snapshot was accepted")
		} catch let error as BrowserSyncPayloadError {
			assert(error.localizedDescription.contains("5,000,000"))
		}
		assert(tooLarge.history.count == originalVisitCount)
		assert(account.history.count == 15_000)

		// The server returns *all* snapshots at once. Several valid devices can
		// exceed the old 16 MiB general-response limit solely due to Base64.
		let snapshots = (0 ..< 5).map { _ in DeviceSnapshot(deviceID: UUID(), payload: upload.payload) }
		let response = try JSONEncoder().encode(snapshots)
		assert(response.count > 16 * 1024 * 1024)
		assert(response.count <= BrowserSyncPayloadLimits.maximumSyncResponseBytes)
		let decoded = try JSONDecoder().decode([DeviceSnapshot].self, from: response)
		assert(decoded.count == 5 && decoded.allSatisfy { $0.payload == upload.payload })
		print("Sync large-account fixture: \(upload.payload.count) raw bytes, \(wireBody.count) PUT bytes, \(response.count) multi-device GET bytes")
	}
}
