import Foundation

nonisolated struct BrowserSyncRemoteSnapshot: Decodable, Sendable {
	let deviceID: UUID
	let payload: Data
}

/// Owns document-sized transformations; never reads live browser objects.
actor BrowserSyncEngine {
	/// Inject a transport in deterministic tests; production uses URLSession.
	typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
	private let network: Transport
	init(network: @escaping Transport = { request in try await URLSession.shared.data(for: request) }) {
		self.network = network
	}
	nonisolated struct SnapshotKey: Hashable, Sendable {
		let window: UUID
		let revision: UInt64
		let settingsRevision: UInt64
		let contentRevision: UInt64
	}
	nonisolated struct Prepared: Sendable {
		let document: BrowserSyncDocument
		let localPortableTabs: [UUID: OpenTab]
	}
	private var projectionCache: [UUID: (key: SnapshotKey, document: BrowserSyncDocument)] = [:]
	func fetch(url: URL, token: String) async throws -> [BrowserSyncRemoteSnapshot] {
		let data = try await transport(url: url, token: token, body: nil)
		return try JSONDecoder().decode([BrowserSyncRemoteSnapshot].self, from: data)
	}
	func publish(url: URL, token: String, body: Data) async throws {
		let data = try await transport(url: url, token: token, body: body)
		_ = try JSONDecoder().decode(BrowserSyncRemoteSnapshot.self, from: data)
	}
	private func transport(url: URL, token: String, body: Data?) async throws -> Data {
		var request = URLRequest(url: url.appending(path: "v1/sync"))
		request.httpMethod = body == nil ? "GET" : "PUT"
		request.httpBody = body
		request.timeoutInterval = 30
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		let phase = BrowserLog.beginSyncPhase("sync.transport")
		defer { BrowserLog.endSyncPhase("sync.transport", phase) }
		let (data, response) = try await network(request)
		try Task.checkCancellation()
		guard let response = response as? HTTPURLResponse,
		      data.count <= (body == nil ? BrowserSyncPayloadLimits.maximumSyncResponseBytes : 16 * 1024 * 1024) else { throw BrowserSyncError.invalidResponse }
		guard 200..<300 ~= response.statusCode else { throw BrowserSyncError.http(response.statusCode) }
		BrowserLog.syncEvent("sync.transport.complete", metadata: ["method": body == nil ? "GET" : "PUT", "response_bytes": String(data.count), "request_bytes": String(body?.count ?? 0)])
		return data
	}
	nonisolated struct Decoded: Sendable {
		let documents: [BrowserSyncDocument]
		let own: BrowserSyncDocument?
	}
	func decode(_ snapshots: [BrowserSyncRemoteSnapshot], deviceID: UUID) throws -> Decoded {
		let phase = BrowserLog.beginSyncPhase("sync.decode-validate")
		defer { BrowserLog.endSyncPhase("sync.decode-validate", phase) }
		try Task.checkCancellation()
		guard snapshots.allSatisfy({ $0.payload.count <= BrowserSyncPayloadLimits.maximumOutgoingBytes }) else {
			throw BrowserSyncError.invalidResponse
		}
		let decoder = JSONDecoder()
		var documents: [BrowserSyncDocument] = []
		var own: BrowserSyncDocument?
		for snapshot in snapshots {
			try Task.checkCancellation()
			let document = try decoder.decode(BrowserSyncDocument.self, from: snapshot.payload)
			guard document.hasSupportedVersion else { throw BrowserSyncError.unsupportedVersion }
			guard document.hasValidStructure else { throw BrowserSyncError.invalidResponse }
			documents.append(document)
			if snapshot.deviceID == deviceID { own = document }
		}
		return Decoded(documents: documents, own: own)
	}
	func merge(_ local: [BrowserSyncDocument], keys: [SnapshotKey], remote: Decoded) throws -> (local: BrowserSyncDocument, merged: BrowserSyncDocument, changed: Bool, prepared: [Prepared]) {
		let phase = BrowserLog.beginSyncPhase("sync.project-merge")
		defer { BrowserLog.endSyncPhase("sync.project-merge", phase) }
		try Task.checkCancellation()
		let liveWindows = Set(keys.map(\.window))
		projectionCache = projectionCache.filter { liveWindows.contains($0.key) }
		let projected = zip(local, keys).map { document, key in
			if let cached = projectionCache[key.window], cached.key == key { return cached.document }
			let portable = document.portableProjection()
			projectionCache[key.window] = (key, portable)
			return portable
		}
		let combined = projected.dropFirst().reduce(projected[0]) { $0.merging($1) }
		let merged = remote.documents.reduce(combined) { $0.merging($1) }
		let changed = merged != combined
		let prepared = !changed ? [] : zip(local, projected).map { raw, portable in
			Prepared(document: merged.preservingLocalOnlyData(from: raw), localPortableTabs: Dictionary(portable.tabs.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }))
		}
		return (combined, merged, changed, prepared)
	}
	func upload(_ document: BrowserSyncDocument, own: BrowserSyncDocument?, deviceID: UUID) throws -> Data? {
		let phase = BrowserLog.beginSyncPhase("sync.compare-encode")
		defer { BrowserLog.endSyncPhase("sync.compare-encode", phase) }
		try Task.checkCancellation()
		guard own != document else { return nil }
		return try BrowserSyncPayloadLimits.makeEncodedUpload(deviceID: deviceID, document: document)
	}
}
