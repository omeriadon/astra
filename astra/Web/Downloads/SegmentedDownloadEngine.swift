import Foundation
import Network

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
	private weak var manager: BrowserDownloadManager?
	private var monitoredItems: Set<UUID> = []
	private var activeTaskIDs: [String: Int] = [:]
	private var lastActivity: [String: Date] = [:]
	private var finishingSegments: Set<String> = []
	private var retryAttempts: [UUID: Int] = [:]
	private var retryJobs: [UUID: Task<Void, Never>] = [:]
	private var watchdog: Task<Void, Never>?
	private var pathMonitor: NWPathMonitor?
	private var pathAvailable = true

	init(manager: BrowserDownloadManager) {
		self.manager = manager
		super.init()
	}

	private func beginMonitoring() {
		if pathMonitor == nil {
			let monitor = NWPathMonitor()

			monitor.pathUpdateHandler = { [weak self] path in
				let available = path.status == .satisfied
				Task { @MainActor [weak self] in
					guard let self else { return }
					let recovered = !pathAvailable && available
					pathAvailable = available
					for itemID in monitoredItems {
						manager?.setSegmentConnectionMessage(
							itemID, message: available ? nil : "Waiting for network…"
						)
					}
					if recovered {
						BrowserLog.notice(.downloads, "segmented.network-restored")
						await checkForStalls(threshold: 0)
					}
				}
			}
			pathMonitor = monitor
			monitor.start(queue: DispatchQueue(label: "com.omeriadon.astra.download-network", qos: .utility))
		}
		if watchdog == nil {
			watchdog = Task { @MainActor [weak self] in
				while !Task.isCancelled {
					try? await Task.sleep(for: .seconds(15))
					guard !Task.isCancelled, let self else { return }
					await checkForStalls(threshold: 90)
				}
			}
		}
	}

	func stopMonitoring(_ itemID: UUID) {
		monitoredItems.remove(itemID)
		retryJobs.removeValue(forKey: itemID)?.cancel()
		retryAttempts[itemID] = nil
		startTokens[itemID] = UUID()
		let prefix = itemID.uuidString + ":"
		for key in activeTaskIDs.keys.filter({ $0.hasPrefix(prefix) }) {
			activeTaskIDs[key] = nil
			lastActivity[key] = nil
			finishingSegments.remove(key)
		}
		if monitoredItems.isEmpty {
			watchdog?.cancel()
			watchdog = nil
			pathMonitor?.cancel()
			pathMonitor = nil
			pathAvailable = true
		}
	}

	func forget(_ itemID: UUID) {
		stopMonitoring(itemID)
		replayHeaders[itemID] = nil
	}

	private func recordActivity(_ itemID: UUID, index: Int, taskID: Int) {
		let key = "\(itemID.uuidString):\(index)"
		guard activeTaskIDs[key] == taskID else { return }
		lastActivity[key] = .now
		retryAttempts[itemID] = 0
		manager?.setSegmentConnectionMessage(itemID, message: nil)
	}

	private func markFinishing(_ itemID: UUID, index: Int, taskID: Int) {
		let key = "\(itemID.uuidString):\(index)"
		guard activeTaskIDs[key] == taskID else { return }
		finishingSegments.insert(key)
		lastActivity[key] = .now
	}

	func acceptsCompletion(_ itemID: UUID, index: Int, taskID: Int) -> Bool {
		let key = "\(itemID.uuidString):\(index)"
		return monitoredItems.contains(itemID) && activeTaskIDs[key] == taskID
	}

	func segmentCommitted(_ itemID: UUID, index: Int) {
		let key = "\(itemID.uuidString):\(index)"
		activeTaskIDs[key] = nil
		lastActivity[key] = nil
		finishingSegments.remove(key)
		retryAttempts[itemID] = 0
	}

	private func scheduleRetry(_ itemID: UUID, immediately: Bool = false) {
		guard monitoredItems.contains(itemID),
		      manager?.activeSegmentedDownload(itemID) != nil
		else {
			stopMonitoring(itemID)
			return
		}
		if !pathAvailable {
			manager?.setSegmentConnectionMessage(itemID, message: "Waiting for network…")
			return
		}

		if immediately {
			retryJobs.removeValue(forKey: itemID)?.cancel()
		}
		guard retryJobs[itemID] == nil else { return }
		let attempt = retryAttempts[itemID, default: 0]
		retryAttempts[itemID] = min(attempt + 1, 6)
		let delay = immediately ? 0 : min(2.0 * pow(2.0, Double(min(attempt, 5))), 60.0)
		manager?.setSegmentConnectionMessage(itemID, message: "Reconnecting…")
		BrowserLog.notice(.downloads, "segmented.retry-scheduled", metadata: [
			"item": BrowserLog.id(itemID), "delay_seconds": String(delay),
		])
		retryJobs[itemID] = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(delay))
			guard let self, !Task.isCancelled else { return }
			retryJobs[itemID] = nil
			guard pathAvailable, let item = manager?.activeSegmentedDownload(itemID) else { return }
			start(item)
		}
	}

	private func checkForStalls(threshold: TimeInterval) async {
		guard pathAvailable, !monitoredItems.isEmpty else { return }
		let tasks = await withCheckedContinuation { continuation in
			session.getAllTasks { continuation.resume(returning: $0) }
		}
		let now = Date.now
		for itemID in Array(monitoredItems) {
			guard let item = manager?.activeSegmentedDownload(itemID),
			      let segments = item.segments
			else {
				stopMonitoring(itemID)
				continue
			}
			var restartNeeded = false
			for (index, segment) in segments.enumerated() where !segment.completed {
				let key = "\(itemID.uuidString):\(index)"
				guard !finishingSegments.contains(key) else { continue }
				if let task = tasks.first(where: {
					$0.taskDescription == key && $0.state != .canceling && $0.state != .completed
				}) {
					let age = now.timeIntervalSince(lastActivity[key] ?? now)
					if age >= threshold {
						BrowserLog.notice(.downloads, "segmented.stalled", metadata: [
							"item": BrowserLog.id(itemID), "segment": String(index),
							"idle_seconds": String(Int(age)),
						])
						activeTaskIDs[key] = nil // Ignore the cancelled task's late delegate callbacks.
						lastActivity[key] = nil
						task.cancel()
						restartNeeded = true
					}
				} else {
					activeTaskIDs[key] = nil
					restartNeeded = true
				}
			}
			if restartNeeded {
				scheduleRetry(itemID, immediately: threshold == 0)
			}
		}
	}

	private func failed(_ itemID: UUID, index: Int, taskID: Int, error: any Error) {
		let key = "\(itemID.uuidString):\(index)"
		guard activeTaskIDs[key] == taskID else { return }
		activeTaskIDs[key] = nil
		lastActivity[key] = nil
		finishingSegments.remove(key)
		guard manager?.activeSegmentedDownload(itemID) != nil else { return }
		let failure = error as NSError
		if failure.domain == NSURLErrorDomain, [
			NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
			NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed,
			NSURLErrorNotConnectedToInternet, NSURLErrorInternationalRoamingOff,
			NSURLErrorDataNotAllowed,
		].contains(failure.code) {
			scheduleRetry(itemID)
		} else {
			BrowserLog.error(.downloads, "segmented.nonrecoverable-error", metadata: [
				"item": BrowserLog.id(itemID), "error": BrowserLog.errorDescription(error),
			])
			manager?.segmentFailed(itemID)
		}
	}

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

		guard let url = item.requestURL, item.segments != nil else { return }
		if let originalRequest {
			replayHeaders[item.id] = Self.safeReplayHeaders(originalRequest)
		}

		monitoredItems.insert(item.id)
		beginMonitoring()
		let token = UUID()
		startTokens[item.id] = token
		session.getAllTasks { [weak self] tasks in
			Task { @MainActor [weak self] in
				guard let self, startTokens[item.id] == token,
				      pathAvailable,
				      let current = manager?.activeSegmentedDownload(item.id),
				      let segments = current.segments else { return }
				for (index, segment) in segments.enumerated() where !segment.completed {
					let description = "\(item.id.uuidString):\(index)"

					guard !finishingSegments.contains(description) else { continue }
					if let task = tasks.first(where: { $0.taskDescription == description && $0.state != .canceling && $0.state != .completed }) {
						activeTaskIDs[description] = task.taskIdentifier
						if lastActivity[description] == nil {
							lastActivity[description] = .now
						}
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
					activeTaskIDs[description] = task.taskIdentifier
					lastActivity[description] = .now
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
		stopMonitoring(itemID)
		let tasks = await withCheckedContinuation { continuation in
			session.getAllTasks { continuation.resume(returning: $0) }
		}
		for task in tasks where task.taskDescription?.hasPrefix(itemID.uuidString + ":") == true && task.state == .running {
			task.suspend()
		}
	}

	func cancel(_ itemID: UUID) {
		BrowserLog.notice(.downloads, "segmented.cancel", metadata: ["item": BrowserLog.id(itemID)])
		forget(itemID)
		session.getAllTasks { tasks in
			for task in tasks where task.taskDescription?.hasPrefix(itemID.uuidString + ":") == true {
				task.cancel()
			}
		}
	}

	func cancelAndWait(_ itemIDs: [UUID]) async {
		BrowserLog.notice(.downloads, "segmented.cancel-and-wait", metadata: ["count": String(itemIDs.count)])
		for itemID in itemIDs {
			forget(itemID)
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
		guard let (itemID, index) = Self.identify(task),
		      let sourceURL = response.url,
		      let destinationURL = newRequest.url,
		      sourceURL != destinationURL
		else {
			completionHandler(newRequest)
			return
		}
		completionHandler(nil)

		let taskID = task.taskIdentifier
		Task { @MainActor [weak self] in
			guard let self, acceptsCompletion(itemID, index: index, taskID: taskID) else { return }
			manager?.segmentFailed(itemID)
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
		if let last = unsafe lastProgressHop[key], now.timeIntervalSince(last) < 0.1 {
			due = false
		} else {
			unsafe lastProgressHop[key] = now
			due = true
		}
		progressThrottle.unlock()
		guard due else { return }

		let taskID = downloadTask.taskIdentifier
		Task { @MainActor [weak self] in
			guard let self else { return }
			recordActivity(itemID, index: index, taskID: taskID)
			guard acceptsCompletion(itemID, index: index, taskID: taskID) else { return }
			manager?.updateSegmentProgress(itemID, index: index, received: totalBytesWritten)
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
			unsafe lastProgressHop[description] = nil
			progressThrottle.unlock()
		}

		let taskID = downloadTask.taskIdentifier
		Task { @MainActor [weak self] in
			self?.markFinishing(itemID, index: index, taskID: taskID)
		}
		let partURL = Self.partURL(itemID, index: index, taskID: taskID)
		let response = downloadTask.response as? HTTPURLResponse
		do {
			try FileManager.default.createDirectory(at: partURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			try? FileManager.default.removeItem(at: partURL)
			try FileManager.default.moveItem(at: location, to: partURL)

			Task { @MainActor [weak self] in
				self?.manager?.completeSegment(itemID, index: index, taskID: taskID, partURL: partURL, response: response)
			}
		} catch {
			BrowserLog.error(.downloads, "segmented.part-move.failed", metadata: [
				"item": BrowserLog.id(itemID), "segment": String(index),
				"part": BrowserLog.path(partURL), "error": BrowserLog.errorDescription(error),
			])
			Task { @MainActor [weak self] in
				guard let self else { return }
				if acceptsCompletion(itemID, index: index, taskID: taskID) {
					manager?.segmentFailed(itemID)
				}
			}
		}
	}

	nonisolated func urlSession(
		_: URLSession,
		task: URLSessionTask,
		didCompleteWithError error: (any Error)?
	) {
		guard let error,
		      let (itemID, index) = Self.identify(task)
		else { return }
		if let description = task.taskDescription {
			progressThrottle.lock()
			unsafe lastProgressHop[description] = nil
			progressThrottle.unlock()
		}

		let taskID = task.taskIdentifier
		Task { @MainActor [weak self] in
			self?.failed(itemID, index: index, taskID: taskID, error: error)
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

	private nonisolated static func partURL(_ itemID: UUID, index: Int, taskID: Int) -> URL {
		let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent(Bundle.main.bundleIdentifier ?? "browser", isDirectory: true)
			.appendingPathComponent("download-parts", isDirectory: true)
		return directory.appendingPathComponent("\(itemID.uuidString)-\(index)-\(taskID).part")
	}

	static func safeReplayHeaders(_ request: URLRequest) -> [String: String] {
		guard !BrowserDownload.requestHasSensitiveCredentials(request) else { return [:] }
		return (request.allHTTPHeaderFields ?? [:]).filter { field, _ in
			!blockedReplayHeaders.contains(field.lowercased())
		}
	}

	func removeParts(_ itemID: UUID, count: Int) async {
		BrowserLog.debug(.downloads, "segmented.remove-parts", metadata: ["item": BrowserLog.id(itemID), "count": String(count)])

		let directory = Self.partURL(itemID, index: 0, taskID: 0).deletingLastPathComponent()
		let prefix = itemID.uuidString + "-"
		// Enumerate on a utility thread; attempts have unique part names so a
		// late cancelled callback cannot replace the next attempt's data.
		let paths = await Task.detached(priority: .utility) {
			(try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
				.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "part" } ?? []
		}.value
		await BrowserDownloadFileWorker.shared.removeFiles(paths)
	}
}
