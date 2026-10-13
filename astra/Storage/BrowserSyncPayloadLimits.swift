import Foundation

/// Wire limits shared by Astra's client and the Vapor /v1/sync contract.
/// The payload is raw JSON; JSONEncoder encodes Data as Base64 in the PUT body.
nonisolated enum BrowserSyncPayloadLimits {
	static let maximumOutgoingBytes = 5_000_000
	static let maximumCollectedRequestBytes = 7_000_000
	// GET returns the Base64-encoded snapshots of *all* the account's devices.
	// Keep a finite bound, but do not apply the smaller AI/general response cap.
	static let maximumSyncResponseBytes = 64 * 1024 * 1024

	static func makeUpload<Document: Encodable>(deviceID: UUID, document: Document) throws -> SyncRequest {
		let payload = try JSONEncoder().encode(document)
		guard payload.count <= maximumOutgoingBytes else {
			throw BrowserSyncPayloadError.tooLarge(actualBytes: payload.count)
		}
		return SyncRequest(deviceID: deviceID, payload: payload)
	}

	/// Complete wire framing happens off the main actor, not inside request().
	static func makeEncodedUpload<Document: Encodable>(deviceID: UUID, document: Document) throws -> Data {
		let upload = try makeUpload(deviceID: deviceID, document: document)
		let body = try JSONEncoder().encode(upload)
		guard body.count <= maximumCollectedRequestBytes else {
			throw BrowserSyncPayloadError.encodedBodyTooLarge(actualBytes: body.count)
		}
		return body
	}
}

nonisolated struct SyncRequest: Encodable, Sendable {
	let deviceID: UUID
	let payload: Data
}

nonisolated enum BrowserSyncPayloadError: LocalizedError, Sendable {
	case tooLarge(actualBytes: Int)
	case encodedBodyTooLarge(actualBytes: Int)

	var errorDescription: String? {
		switch self {
			case let .tooLarge(actualBytes):
				"Sync data (\(actualBytes) bytes) exceeds the server's 5,000,000-byte per-device limit. Your local data remains safe."
			case let .encodedBodyTooLarge(actualBytes):
				"Sync upload (\(actualBytes) bytes) exceeds the server's 7 MB request limit. Your local data remains safe."
		}
	}
}
