import Foundation

@MainActor
final class SegmentedDownloadEngine: NSObject, URLSessionDownloadDelegate {
	private let progressThrottle = NSLock()
	private nonisolated(unsafe) var lastProgressHop: [String: Date] = [:]
	private lazy var session: URLSession = {
		let identifier = (Bundle.main.bundleIdentifier ?? "browser") + ".segmentedDownloads"
		let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
		configuration.isDiscretionary = false
		configuration.httpMaximumConnectionsPerHost = BrowserDownloadSegment.maximumConnections
		return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
	}()

	func start(_ item: BrowserDownload) {
		guard let url = item.requestURL,
		      let segments = item.segments,
		      let validator = item.rangeValidator
		else { return }
		session.getAllTasks { [weak self] tasks in
			Task { @MainActor [weak self] in
				guard let self else { return }
				for (index, segment) in segments.enumerated() where !segment.completed {
					let description = "\(item.id.uuidString):\(index)"
					guard !tasks.contains(where: { $0.taskDescription == description }) else { continue }
					var request = URLRequest(url: url)
					request.cachePolicy = .reloadIgnoringLocalCacheData
					request.setValue("bytes=\(segment.start)-\(segment.end)", forHTTPHeaderField: "Range")
					request.setValue(validator, forHTTPHeaderField: "If-Range")
					request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
					let task = self.session.downloadTask(with: request)
					task.taskDescription = description
					task.resume()
				}
			}
		}
	}

	func cancel(_ itemID: UUID) {
		session.getAllTasks { tasks in
			for task in tasks where task.taskDescription?.hasPrefix(itemID.uuidString + ":") == true {
				task.cancel()
			}
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

	func removeParts(_ itemID: UUID, count: Int) {
		for index in 0 ..< count {
			try? FileManager.default.removeItem(at: Self.partURL(itemID, index: index))
		}
	}
}
