import Foundation

@MainActor
final class SegmentedDownloadEngine: NSObject, URLSessionDownloadDelegate {
	private static let blockedReplayHeaders: Set<String> = [
		"accept-encoding",
		"authorization",
		"connection",
		"content-length",
		"cookie",
		"cookie2",
		"host",
		"if-range",
		"keep-alive",
		"proxy-authorization",
		"proxy-connection",
		"range",
		"te",
		"trailer",
		"transfer-encoding",
		"upgrade",
	]

	private let progressThrottle = NSLock()
	private nonisolated(unsafe) var lastProgressHop: [String: Date] = [:]
	private var startTokens: [UUID: UUID] = [:]
	private var replayHeaders: [UUID: [String: String]] = [:]
	/// URLSession download completion moves files synchronously before its
	/// delegate callback returns. Never execute those filesystem operations on
	/// the UI thread. The delegate methods already explicitly hop to MainActor
	/// when they publish progress/completion into BrowserDownloadManager.
	private let delegateQueue: OperationQueue = {
		let queue = OperationQueue()
		queue.name = "com.omeriadon.astra.segmented-download-delegate"
		queue.qualityOfService = .utility
		queue.maxConcurrentOperationCount = 1
		return queue
	}()

	private lazy var session: URLSession = {
		let identifier = (Bundle.main.bundleIdentifier ?? "browser") + ".segmentedDownloads"
		let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
		configuration.isDiscretionary = false
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.urlCredentialStorage = nil
		configuration.httpMaximumConnectionsPerHost = BrowserDownloadSegment.maximumConnections
		return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
	}()

	func start(_ item: BrowserDownload, originalRequest: URLRequest? = nil) {
		BrowserLog.info(.downloads, "segmented.start", metadata: ["item": BrowserLog.id(item.id), "request": BrowserLog.request(originalRequest), "url": BrowserLog.url(item.requestURL)])
		guard let url = item.requestURL,
		      let segments = item.segments
		else { return }
		if let originalRequest {
			replayHeaders[item.id] = Self.safeReplayHeaders(originalRequest)
		}
		let token = UUID()
		startTokens[item.id] = token
		session.getAllTasks { [weak self] tasks in
			Task { @MainActor [weak self] in
				guard let self, startTokens[item.id] == token else { return }
				for (index, segment) in segments.enumerated() where !segment.completed {
					let description = "\(item.id.uuidString):\(index)"
					if let task = tasks.first(where: { $0.taskDescription == description && $0.state != .canceling && $0.state != .completed }) {
						if task.state == .suspended {
							task.resume()
						}
						continue
					}
					var request = URLRequest(url: url)
					for (field, value) in replayHeaders[item.id] ?? [:] {
						request.setValue(value, forHTTPHeaderField: field)
					}
					request.cachePolicy = .reloadIgnoringLocalCacheData
					request.setValue("bytes=\(segment.start)-\(segment.end)", forHTTPHeaderField: "Range")
					if let validator = item.rangeValidator {
						request.setValue(validator, forHTTPHeaderField: "If-Range")
					}
					request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
					let task = self.session.downloadTask(with: request)
					task.taskDescription = description
					task.resume()
				}
			}
		}
	}

	func fallbackRequest(for item: BrowserDownload) -> URLRequest? {
		BrowserLog.debug(.downloads, "segmented.fallback-request", metadata: ["item": BrowserLog.id(item.id)])
		guard let url = item.requestURL else { return nil }
		var request = URLRequest(url: url)
		for (field, value) in replayHeaders[item.id] ?? [:] {
			request.setValue(value, forHTTPHeaderField: field)
		}
		return request
	}

	func pause(_ itemID: UUID) async {
		startTokens[itemID] = UUID()
		let tasks = await withCheckedContinuation { continuation in
			session.getAllTasks { continuation.resume(returning: $0) }
		}
		for task in tasks where task.taskDescription?.hasPrefix(itemID.uuidString + ":") == true && task.state == .running {
			task.suspend()
		}
	}

	func cancel(_ itemID: UUID) {
		BrowserLog.notice(.downloads, "segmented.cancel", metadata: ["item": BrowserLog.id(itemID)])
		startTokens[itemID] = UUID()
		session.getAllTasks { tasks in
			for task in tasks where task.taskDescription?.hasPrefix(itemID.uuidString + ":") == true {
				task.cancel()
			}
		}
	}

	func cancelAndWait(_ itemIDs: [UUID]) async {
		BrowserLog.notice(.downloads, "segmented.cancel-and-wait", metadata: ["count": String(itemIDs.count)])
		for itemID in itemIDs {
			startTokens[itemID] = UUID()
		}
		let tasks = await withCheckedContinuation { continuation in
			session.getAllTasks { continuation.resume(returning: $0) }
		}
		let itemIDSet = Set(itemIDs)
		for task in tasks {
			guard let (itemID, _) = Self.identify(task), itemIDSet.contains(itemID) else { continue }
			task.cancel()
		}
	}

	nonisolated func urlSession(
		_: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest: URLRequest,
		completionHandler: @escaping (URLRequest?) -> Void
	) {
		guard let (itemID, _) = Self.identify(task),
		      let sourceURL = response.url,
		      let destinationURL = newRequest.url,
		      sourceURL != destinationURL
		else {
			completionHandler(newRequest)
			return
		}
		completionHandler(nil)
		Task { @MainActor in
			BrowserDownloadManager.shared.segmentFailed(itemID)
		}
	}

	nonisolated func urlSession(
		_: URLSession,
		downloadTask: URLSessionDownloadTask,
		didWriteData _: Int64,
		totalBytesWritten: Int64,
		totalBytesExpectedToWrite _: Int64
	) {
		guard let (itemID, index) = Self.identify(downloadTask) else { return }
		// Disk chunks arrive far more often than progress UI can use; the
		// manager coalesces values too, this just avoids the MainActor hop.
		let key = downloadTask.taskDescription ?? ""
		let now = Date()
		progressThrottle.lock()
		let due: Bool
		if let last = lastProgressHop[key], now.timeIntervalSince(last) < 0.1 {
			due = false
		} else {
			lastProgressHop[key] = now
			due = true
		}
		progressThrottle.unlock()
		guard due else { return }
		Task { @MainActor in
			BrowserDownloadManager.shared.updateSegmentProgress(itemID, index: index, received: totalBytesWritten)
		}
	}

	nonisolated func urlSession(
		_: URLSession,
		downloadTask: URLSessionDownloadTask,
		didFinishDownloadingTo location: URL
	) {
		guard let (itemID, index) = Self.identify(downloadTask) else { return }
		if let description = downloadTask.taskDescription {
			progressThrottle.lock()
			lastProgressHop[description] = nil
			progressThrottle.unlock()
		}
		let partURL = Self.partURL(itemID, index: index)
		let response = downloadTask.response as? HTTPURLResponse
		do {
			try FileManager.default.createDirectory(at: partURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			try? FileManager.default.removeItem(at: partURL)
			try FileManager.default.moveItem(at: location, to: partURL)
			Task { @MainActor in
				BrowserDownloadManager.shared.completeSegment(itemID, index: index, partURL: partURL, response: response)
			}
		} catch {
			Task { @MainActor in
				BrowserDownloadManager.shared.segmentFailed(itemID)
			}
		}
	}

	nonisolated func urlSession(
		_: URLSession,
		task: URLSessionTask,
		didCompleteWithError error: (any Error)?
	) {
		guard error != nil,
		      let (itemID, _) = Self.identify(task)
		else { return }
		if let description = task.taskDescription {
			progressThrottle.lock()
			lastProgressHop[description] = nil
			progressThrottle.unlock()
		}
		Task { @MainActor in
			BrowserDownloadManager.shared.segmentFailed(itemID)
		}
	}

	private nonisolated static func identify(_ task: URLSessionTask) -> (UUID, Int)? {
		guard let description = task.taskDescription else { return nil }
		let parts = description.split(separator: ":")
		guard parts.count == 2,
		      let id = UUID(uuidString: String(parts[0])),
		      let index = Int(parts[1])
		else { return nil }
		return (id, index)
	}

	private nonisolated static func partURL(_ itemID: UUID, index: Int) -> URL {
		let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent(Bundle.main.bundleIdentifier ?? "browser", isDirectory: true)
			.appendingPathComponent("download-parts", isDirectory: true)
		return directory.appendingPathComponent("\(itemID.uuidString)-\(index).part")
	}

	static func safeReplayHeaders(_ request: URLRequest) -> [String: String] {
		guard !BrowserDownload.requestHasSensitiveCredentials(request) else { return [:] }
		return (request.allHTTPHeaderFields ?? [:]).filter { field, _ in
			!blockedReplayHeaders.contains(field.lowercased())
		}
	}

	func removeParts(_ itemID: UUID, count: Int) async {
		BrowserLog.debug(.downloads, "segmented.remove-parts", metadata: ["item": BrowserLog.id(itemID), "count": String(count)])
		let paths = (0 ..< count).map { Self.partURL(itemID, index: $0) }
		await BrowserDownloadFileWorker.shared.removeFiles(paths)
	}
}
