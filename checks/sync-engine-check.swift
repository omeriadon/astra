import Foundation

private actor RetryTransport {
    var attempts = 0
    let responseBody: Data
    init(responseBody: Data) { self.responseBody = responseBody }
    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        attempts += 1
        if attempts == 1 { throw URLError(.notConnectedToInternet) }
        return (responseBody, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@main
struct SyncEngineCheck {
    static func main() async throws {
        let engine = BrowserSyncEngine()
        let deviceID = UUID()
        let windowID = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let tab = OpenTab(url: URL(string: "https://initial.example/")!, modifiedAt: now)
        let workspace = BrowserWorkspace.migrated(tabs: [tab], selectedTabID: tab.id, theme: BrowserTheme())
        let original = BrowserSyncDocument(tabs: [tab], workspace: workspace, bookmarks: [], browser: BrowserSnapshot(selectedTabID: tab.id), settings: [:])
        func key(_ revision: UInt64, content: UInt64 = 0) -> BrowserSyncEngine.SnapshotKey {
            .init(window: windowID, revision: revision, settingsRevision: 0, contentRevision: content)
        }
        func wire(_ document: BrowserSyncDocument, device: UUID = UUID()) throws -> BrowserSyncRemoteSnapshot {
            .init(deviceID: device, payload: try JSONEncoder().encode(document))
        }
        let portable = original.portableProjection()
        let decoded = try await engine.decode([wire(portable, device: deviceID)], deviceID: deviceID)
        precondition(decoded.documents == [portable] && decoded.own == portable)
        let empty = try await engine.decode([], deviceID: deviceID)
        precondition(empty.own == nil && empty.documents.isEmpty)
        let unchanged = try await engine.merge([original], keys: [key(1)], remote: decoded)
        precondition(unchanged.merged == portable && unchanged.prepared.isEmpty)
        precondition(!unchanged.changed)
        let noUpload = try await engine.upload(unchanged.merged, own: decoded.own, deviceID: deviceID)
        precondition(noUpload == nil)
        let upload = try await engine.upload(portable, own: nil, deviceID: deviceID)
        precondition(upload != nil)
        // Same key reuses the immutable projection; changed source revisions
        // invalidate it. The coordinator must capture the key with the snapshot.
        let cached = try await engine.merge([original], keys: [key(1)], remote: empty)
        precondition(cached.local == portable)
        var edited = original
        edited.tabs[0].url = URL(string: "https://edited-during-fetch.example/")!
        edited.tabs[0].modifiedAt = now.addingTimeInterval(2)
        let afterEdit = try await engine.merge([edited], keys: [key(2)], remote: decoded)
        precondition(afterEdit.merged.tabs[0].url == edited.tabs[0].url)
        precondition(afterEdit.merged.tabs[0].id == tab.id)
        // A newer local edit made during merge must survive a subsequent merge
        // against the earlier merged result (the coordinator's revision recheck).
        var latest = edited
        latest.tabs[0].customTitle = "Latest title"
        latest.tabs[0].modifiedAt = now.addingTimeInterval(3)
        let previousMerge = try await engine.decode([wire(afterEdit.merged)], deviceID: deviceID)
        let reconciled = try await engine.merge([latest], keys: [key(3)], remote: previousMerge)
        precondition(reconciled.merged.tabs[0].customTitle == "Latest title")
        var deletion = portable
        deletion.tabs = []
        deletion.browser.closedTabIDs.insert(tab.id)
        deletion.browser.closedTabsAt[tab.id] = now.addingTimeInterval(4)
        let removed = try await engine.decode([wire(deletion)], deviceID: deviceID)
        let tombstoneMerge = try await engine.merge([latest], keys: [key(3)], remote: removed)
        precondition(tombstoneMerge.merged.tabs.isEmpty)
        // Recreating the same identity after its tombstone remains supported.
        latest.tabs[0].modifiedAt = now.addingTimeInterval(5)
        let recreated = try await engine.merge([latest], keys: [key(4)], remote: removed)
        precondition(recreated.merged.tabs.map(\.id) == [tab.id])
        var boosted = original
        let boost = BrowserBoost(name: "Test", domain: "example.org", css: "body { color: blue; }", modifiedAt: now)
        boosted.boosts = [boost]
        let updatedContent = try await engine.merge([boosted], keys: [key(4, content: 1)], remote: empty)
        precondition(updatedContent.merged.boosts == [boost])
        var deletedBoost = boosted
        deletedBoost.boosts = []
        deletedBoost.deletedBoostsAt[boost.id] = now.addingTimeInterval(1)
        let remoteBoostDeletion = try await engine.decode([wire(deletedBoost)], deviceID: deviceID)
        let boostMerge = try await engine.merge([boosted], keys: [key(4, content: 1)], remote: remoteBoostDeletion)
        precondition(boostMerge.merged.boosts.isEmpty)
        // Untrusted payloads are validated even if they belong to this device.
        var invalidDocuments: [BrowserSyncDocument] = []
        var invalid = portable
        invalid.tabs[0].url = URL(string: "https://user:secret@example.org")!
        invalidDocuments.append(invalid)
        invalid = portable
        invalid.tabs.append(invalid.tabs[0])
        invalidDocuments.append(invalid)
        invalid = portable
        invalid.boosts = [BrowserBoost(name: "Invalid", domain: "bad domain", modifiedAt: now)]
        invalidDocuments.append(invalid)
        for invalid in invalidDocuments {
            do {
                _ = try await engine.decode([wire(invalid, device: deviceID)], deviceID: deviceID)
                preconditionFailure("Invalid remote document accepted")
            } catch BrowserSyncError.invalidResponse {}
        }
        invalid = portable
        invalid.version = 99
        do {
            _ = try await engine.decode([wire(invalid)], deviceID: deviceID)
            preconditionFailure("Future version accepted")
        } catch BrowserSyncError.unsupportedVersion {}
        do {
            _ = try await engine.decode([.init(deviceID: deviceID, payload: Data("{bad json".utf8))], deviceID: deviceID)
            preconditionFailure("Malformed JSON accepted")
        } catch is DecodingError {}
        do {
            _ = try await engine.decode([.init(deviceID: deviceID, payload: Data(repeating: 32, count: BrowserSyncPayloadLimits.maximumOutgoingBytes + 1))], deviceID: deviceID)
            preconditionFailure("Oversize remote accepted")
        } catch BrowserSyncError.invalidResponse {}
        // Multiple windows combine shared identities instead of duplicating tabs.
        let otherKey = BrowserSyncEngine.SnapshotKey(window: UUID(), revision: 1, settingsRevision: 0, contentRevision: 0)
        let windows = try await engine.merge([original, latest], keys: [key(1), otherKey], remote: empty)
        precondition(windows.merged.tabs.count == 1 && windows.merged.tabs[0].customTitle == latest.tabs[0].customTitle)
        // Realistically large documents keep correctness across repeated cache hits.
        var large = original
        large.history = (0..<15_000).map { BrowserVisit(url: URL(string: "https://example.org/visit/\($0)")!, title: "Visit \($0)", visitedAt: now, modifiedAt: now) }
        let firstLarge = try await engine.merge([large], keys: [key(10)], remote: empty)
        for _ in 0..<5 {
            let repeated = try await engine.merge([large], keys: [key(10)], remote: empty)
            precondition(repeated.local == firstLarge.local)
            let skipped = try await engine.upload(repeated.merged, own: firstLarge.merged, deviceID: deviceID)
            precondition(skipped == nil)
        }
        // An encoding failure never mutates the pending immutable document;
        // retrying the same capture remains possible after transport failures too.
        var oversized = large
        oversized.history = (0..<40_000).map { BrowserVisit(url: URL(string: "https://example.org/long/\($0)")!, title: String(repeating: "x", count: 300), visitedAt: now, modifiedAt: now) }
        let pending = oversized
        do {
            _ = try await engine.upload(oversized, own: nil, deviceID: deviceID)
            preconditionFailure("Oversize outgoing document accepted")
        } catch BrowserSyncPayloadError.tooLarge {}
        precondition(oversized == pending)
        let retry = try await engine.upload(portable, own: nil, deviceID: deviceID)
        precondition(retry != nil)
        // Actual engine transport failure followed by retry preserves the
        // pending capture and produces no false completion on the first attempt.
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "deviceID": deviceID.uuidString,
            "payload": try JSONEncoder().encode(portable).base64EncodedString(),
        ])
        let transport = RetryTransport(responseBody: responseBody)
        let retryEngine = BrowserSyncEngine(network: { request in try await transport.send(request) })
        let server = URL(string: "https://sync.example.org")!
        do {
            try await retryEngine.publish(url: server, token: "test-token", body: retry!)
            preconditionFailure("Offline publish falsely completed")
        } catch let error as URLError {
            precondition(error.code == .notConnectedToInternet)
        }
        precondition(portable == original.portableProjection())
        try await retryEngine.publish(url: server, token: "test-token", body: retry!)
        let attempts = await transport.attempts
        precondition(attempts == 2)
        let fetchedBody = try JSONSerialization.data(withJSONObject: [[
            "deviceID": deviceID.uuidString,
            "payload": try JSONEncoder().encode(portable).base64EncodedString(),
        ]])
        let fetchEngine = BrowserSyncEngine(network: { request in
            precondition(request.httpMethod == "GET" && request.httpBody == nil)
            return (fetchedBody, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let fetched = try await fetchEngine.fetch(url: server, token: "test-token")
        let validatedFetch = try await fetchEngine.decode(fetched, deviceID: deviceID)
        precondition(validatedFetch.own == portable)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await engine.decode([], deviceID: deviceID)
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        let observedCancellation = await cancelled.value
        precondition(observedCancellation)
        print("Sync engine decode, revision reconciliation, tombstones, boost invalidation, cache and upload checks passed")
    }
}
