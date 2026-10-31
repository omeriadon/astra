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
		let bookmarksChanged: Bool
		let readingListChanged: Bool
		let historyChanged: Bool
		let workspaceChanged: Bool
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
		let started = BrowserLog.clock()
		BrowserLog.syncEvent("sync.transport.begin", metadata: ["method": body == nil ? "GET" : "PUT", "request_bytes": String(body?.count ?? 0)])
		var request = URLRequest(url: url.appending(path: "v1/sync"))
		request.httpMethod = body == nil ? "GET" : "PUT"
		request.httpBody = body
		request.timeoutInterval = 30
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		let phase = BrowserLog.beginSyncPhase("sync.transport")
		defer { BrowserLog.endSyncPhase("sync.transport", phase) }
		let data: Data
		let response: URLResponse
		do { (data, response) = try await network(request) }
		catch {
			BrowserLog.syncEvent("sync.transport.failed", metadata: ["network_code": String((error as? URLError)?.code.rawValue ?? 0), "elapsed_ms": String(Int((BrowserLog.clock() - started) * 1000))])
			throw error
		}
		try Task.checkCancellation()
		guard let response = response as? HTTPURLResponse,
		      data.count <= (body == nil ? BrowserSyncPayloadLimits.maximumSyncResponseBytes : 16 * 1024 * 1024) else { throw BrowserSyncError.invalidResponse }
		guard 200 ..< 300 ~= response.statusCode else {
			BrowserLog.syncEvent("sync.transport.rejected", metadata: ["http_status": String(response.statusCode), "response_bytes": String(data.count)])
			throw BrowserSyncError.http(response.statusCode)
		}
		BrowserLog.syncEvent("sync.transport.complete", metadata: ["method": body == nil ? "GET" : "PUT", "response_bytes": String(data.count), "request_bytes": String(body?.count ?? 0)])
		return data
	}

	nonisolated struct Decoded: Sendable {
		let documents: [BrowserSyncDocument]
		let own: BrowserSyncDocument?
	}

	func decode(_ snapshots: [BrowserSyncRemoteSnapshot], deviceID: UUID) throws -> Decoded {
		let started = BrowserLog.clock()
		BrowserLog.syncEvent("sync.decode.begin", metadata: ["documents": String(snapshots.count)])
		let phase = BrowserLog.beginSyncPhase("sync.decode-validate")
		defer { BrowserLog.endSyncPhase("sync.decode-validate", phase) }
		try Task.checkCancellation()
		guard snapshots.allSatisfy({ $0.payload.count <= BrowserSyncPayloadLimits.maximumOutgoingBytes }) else {
			BrowserLog.syncEvent("sync.decode.rejected", metadata: ["reason": "device-payload-limit"])
			throw BrowserSyncError.invalidResponse
		}
		let decoder = JSONDecoder()
		var documents: [BrowserSyncDocument] = []
		var own: BrowserSyncDocument?
		for snapshot in snapshots {
			try Task.checkCancellation()
			let document = try decoder.decode(BrowserSyncDocument.self, from: snapshot.payload)
			guard document.hasSupportedVersion else {
				BrowserLog.syncEvent("sync.decode.rejected", metadata: ["reason": "unsupported-version"])
				throw BrowserSyncError.unsupportedVersion
			}
			guard document.hasValidStructure else {
				BrowserLog.syncEvent("sync.decode.rejected", metadata: ["reason": "invalid-structure"])
				throw BrowserSyncError.invalidResponse
			}
			documents.append(document)
			if snapshot.deviceID == deviceID {
				own = document
			}
		}
		BrowserLog.syncEvent("sync.decode.complete", metadata: ["documents": String(documents.count), "own_present": String(own != nil), "elapsed_ms": String(Int((BrowserLog.clock() - started) * 1000))])
		return Decoded(documents: documents, own: own)
	}

	func merge(_ local: [BrowserSyncDocument], keys: [SnapshotKey], remote: Decoded) throws -> (local: BrowserSyncDocument, merged: BrowserSyncDocument, changed: Bool, prepared: [Prepared]) {
		let started = BrowserLog.clock()
		var cacheHits = 0
		BrowserLog.syncEvent("sync.merge.begin", metadata: ["windows": String(local.count), "remote_documents": String(remote.documents.count)])
		let phase = BrowserLog.beginSyncPhase("sync.project-merge")
		defer { BrowserLog.endSyncPhase("sync.project-merge", phase) }
		try Task.checkCancellation()
		let liveWindows = Set(keys.map(\.window))
		projectionCache = projectionCache.filter { liveWindows.contains($0.key) }
		let projected = zip(local, keys).map { document, key in
			if let cached = projectionCache[key.window], cached.key == key {
				cacheHits += 1; return cached.document
			}
			let portable = document.portableProjection()
			projectionCache[key.window] = (key, portable)
			return portable
		}
		let combined = projected.dropFirst().reduce(projected[0]) { $0.merging($1) }
		let merged = remote.documents.reduce(combined) { $0.merging($1) }
		let changed = merged != combined
		var prepared: [Prepared] = []
		if changed {
			prepared.reserveCapacity(local.count)
			for (raw, portable) in zip(local, projected) {
				let preserved = merged.preservingLocalOnlyData(from: raw)
				let tabIndex: [UUID: OpenTab] = Dictionary(
					portable.tabs.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }
				)
				prepared.append(Prepared(document: preserved,
				                         localPortableTabs: tabIndex,
				                         bookmarksChanged: preserved.bookmarks != raw.bookmarks,
				                         readingListChanged: preserved.readingList != raw.readingList,
				                         historyChanged: preserved.history != raw.history,
				                         workspaceChanged: preserved.workspace != raw.workspace))
			}
		}
		BrowserLog.syncEvent("sync.merge.complete", metadata: ["cache_hits": String(cacheHits), "cache_misses": String(local.count - cacheHits), "changed": String(changed), "prepared_windows": String(prepared.count), "elapsed_ms": String(Int((BrowserLog.clock() - started) * 1000))])
		return (combined, merged, changed, prepared)
	}

	func upload(_ document: BrowserSyncDocument, own: BrowserSyncDocument?, deviceID: UUID) throws -> Data? {
		let phase = BrowserLog.beginSyncPhase("sync.compare-encode")
		defer { BrowserLog.endSyncPhase("sync.compare-encode", phase) }
		try Task.checkCancellation()
		guard own != document else { BrowserLog.syncEvent("sync.upload.skipped", metadata: ["reason": "unchanged"]); return nil }
		let started = BrowserLog.clock()
		BrowserLog.syncEvent("sync.encode.begin")
		let body = try BrowserSyncPayloadLimits.makeEncodedUpload(deviceID: deviceID, document: document)
		BrowserLog.syncEvent("sync.encode.complete", metadata: ["bytes": String(body.count), "elapsed_ms": String(Int((BrowserLog.clock() - started) * 1000))])
		return body
	}
}
