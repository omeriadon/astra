import Defaults
import Foundation
import FoundationModels
import Observation
import SwiftUI
import WebKit

#if os(macOS)
	import DockProgress
#endif

@MainActor
@Observable
final class BrowserDownloadManager: NSObject, WKDownloadDelegate {
	static let shared = BrowserDownloadManager()
	private static let unsafeFilenameCharacters = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)

	private var downloads: [ObjectIdentifier: WKDownload] = [:]
	private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
	private var destinations: [ObjectIdentifier: URL] = [:]
	private var itemIDs: [ObjectIdentifier: UUID] = [:]
	private var previousTemporaryURLs: [UUID: URL] = [:]
	private var accelerationAbandoned: Set<UUID> = []
	private var resumeWebView: WKWebView?
	@ObservationIgnored private lazy var segmented = SegmentedDownloadEngine()
	private var isClosing = false
	private var restorationStarted = false
	private var lastPersistedAt = Date.distantPast
	private let storeURL: URL
	private(set) var items: [BrowserDownload] = []
	private(set) var latestStart: (id: UUID, source: UnitPoint)?

	var activeProgress: Double? {
		let active = items.filter { $0.status == .downloading }
		guard !active.isEmpty else { return nil }
		return active.reduce(0) { $0 + $1.progress } / Double(active.count)
	}

	var buttonSymbol: String {
		items.first(where: { $0.status == .downloading })?.symbol
			?? items.first?.symbol
			?? "arrow.down.circle"
	}

	override private init() {
		let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent(Bundle.main.bundleIdentifier ?? "browser", isDirectory: true)
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		storeURL = directory.appendingPathComponent("downloads.json")
		super.init()
		if let data = try? Data(contentsOf: storeURL),
		   let saved = try? JSONDecoder().decode([BrowserDownload].self, from: data)
		{
			items = saved.map { item in
				var item = item
				if item.status == .downloading, item.segments == nil {
					item.status = .paused
					item.errorMessage = "Download interrupted."
				}
				return item
			}
		}
		#if DEBUG
			assert(Self.safeStem("../unsafe\\name") == "unsafename")
		#endif
		updateDockProgress()
	}

	func start(_ download: WKDownload, sourceURL: URL? = nil, source: UnitPoint = .center) {
		let id = ObjectIdentifier(download)
		guard downloads[id] == nil else { return }
		let itemID = UUID()
		let requestURL = download.originalRequest?.url
		let suggestedName = requestURL?.lastPathComponent ?? ""
		let name = suggestedName.isEmpty ? "Download" : suggestedName
		let provisionalURL = downloadDirectory.appendingPathComponent(name).appendingPathExtension("astradownload")
		items.insert(
			BrowserDownload(
				id: itemID,
				createdAt: .now,
				sourceURL: siteURL(for: sourceURL ?? download.webView?.url ?? requestURL),
				requestURL: requestURL,
				requestMethod: download.originalRequest?.httpMethod,
				originalName: name,
				fileURL: provisionalURL,
				status: .downloading,
				progress: 0,
				renamedByAppleIntelligence: false,
				resumeData: nil,
				errorMessage: nil
			),
			at: 0
		)
		attach(download, to: itemID)
		latestStart = (itemID, source)
		persist()
	}

	private func attach(_ download: WKDownload, to itemID: UUID) {
		let id = ObjectIdentifier(download)
		downloads[id] = download
		itemIDs[id] = itemID
		download.delegate = self
		observations[id] = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
			Task { @MainActor [weak self] in
				self?.updateProgress(itemID, fraction: progress.fractionCompleted)
			}
		}
		updateDockProgress()
	}

	func download(
		_ download: WKDownload,
		decideDestinationUsing response: URLResponse,
		suggestedFilename: String,
		completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
	) {
		Task { @MainActor in
			guard let itemID = itemIDs[ObjectIdentifier(download)],
			      let index = items.firstIndex(where: { $0.id == itemID })
			else {
				completionHandler(nil)
				return
			}
			let original = URL(fileURLWithPath: suggestedFilename).lastPathComponent
			let originalExtension = String(String.UnicodeScalarView(
				URL(fileURLWithPath: original).pathExtension.unicodeScalars.filter {
					!Self.unsafeFilenameCharacters.contains($0)
				}
			))
			let originalStem = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
			let suggestedStem = await humanReadableStem(
				original: originalStem,
				source: items[index].sourceURL?.host ?? response.url?.host,
				fileType: response.mimeType
			)
			var stem = Self.safeStem(suggestedStem ?? originalStem)
			let repeatedExtension = ".\(originalExtension)"
			if !originalExtension.isEmpty,
			   stem.lowercased().hasSuffix(repeatedExtension.lowercased())
			{
				stem = String(stem.dropLast(repeatedExtension.count))
			}
			let fileName = originalExtension.isEmpty ? stem : "\(stem).\(originalExtension)"
			do {
				try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
				let completedURL = uniqueDestination(fileName: fileName, in: downloadDirectory)
				let destination = completedURL.appendingPathExtension("astradownload")
				if items[index].resumeData != nil {
					previousTemporaryURLs[itemID] = items[index].fileURL
				}
				items[index].fileURL = destination
				items[index].originalName = original
				items[index].requestURL = response.url
				items[index].renamedByAppleIntelligence = suggestedStem != nil && stem != Self.safeStem(originalStem)
				items[index].resumeData = nil
				items[index].errorMessage = nil
				destinations[ObjectIdentifier(download)] = destination
				persist()
				completionHandler(destination)
				Task { @MainActor in
					await maybeAccelerate(download, response: response)
				}
			} catch {
				ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Download failed: \(error.localizedDescription)")
				items[index].status = .failed
				items[index].errorMessage = error.localizedDescription
				completionHandler(nil)
				finish(download)
				persist()
			}
		}
	}

	func downloadDidFinish(_ download: WKDownload) {
		if let itemID = itemIDs[ObjectIdentifier(download)],
		   let index = items.firstIndex(where: { $0.id == itemID }),
		   let temporaryURL = destinations[ObjectIdentifier(download)]
		{
			let completedURL = uniqueDestination(
				fileName: temporaryURL.deletingPathExtension().lastPathComponent,
				in: temporaryURL.deletingLastPathComponent(),
				excludingTemporary: temporaryURL
			)
			do {
				try FileManager.default.moveItem(at: temporaryURL, to: completedURL)
				items[index].fileURL = completedURL
				items[index].status = .completed
				items[index].progress = 1
				items[index].resumeData = nil
				if let oldURL = previousTemporaryURLs.removeValue(forKey: itemID), oldURL != temporaryURL {
					try? FileManager.default.removeItem(at: oldURL)
				}
				ToastManager.shared.show(symbol: "arrow.down.circle", message: "Downloaded \(completedURL.lastPathComponent)")
			} catch {
				items[index].status = .failed
				items[index].errorMessage = error.localizedDescription
				ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Download failed: \(error.localizedDescription)")
			}
		}
		finish(download)
		persist()
	}

	func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
		guard downloads[ObjectIdentifier(download)] != nil else { return }
		if !isClosing {
			if let itemID = itemIDs[ObjectIdentifier(download)],
			   let index = items.firstIndex(where: { $0.id == itemID })
			{
				items[index].resumeData = resumeData
				items[index].status = resumeData == nil ? .failed : .paused
				items[index].errorMessage = error.localizedDescription
			}
			ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Download failed: \(error.localizedDescription)")
		}
		finish(download)
		persist()
	}

	private func finish(_ download: WKDownload) {
		let id = ObjectIdentifier(download)
		observations[id] = nil
		downloads[id] = nil
		itemIDs[id] = nil
		destinations[id] = nil
		updateDockProgress()
	}

	private func updateDockProgress() {
		#if os(macOS)
			DockProgress.progress = activeProgress ?? 0
		#endif
	}

	func resumeAvailableDownloads() {
		guard !restorationStarted else { return }
		restorationStarted = true
		for item in items where item.status == .downloading && item.segments != nil {
			segmented.start(item)
		}
		for item in items where item.status == .paused && item.resumeData != nil {
			resume(item.id)
		}
		for item in items where item.status == .paused
			&& item.resumeData == nil
			&& item.requestMethod == "GET"
			&& ["http", "https"].contains(item.requestURL?.scheme ?? "")
		{
			restart(item.id)
		}
	}

	private func restart(_ itemID: UUID) {
		guard let index = items.firstIndex(where: { $0.id == itemID }),
		      let url = items[index].requestURL
		else { return }
		if resumeWebView == nil {
			resumeWebView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
		}
		previousTemporaryURLs[itemID] = items[index].fileURL
		items[index].status = .downloading
		items[index].progress = 0
		items[index].errorMessage = nil
		persist()
		resumeWebView?.startDownload(using: URLRequest(url: url)) { [weak self] download in
			self?.attach(download, to: itemID)
		}
	}

	func resume(_ itemID: UUID) {
		guard let index = items.firstIndex(where: { $0.id == itemID }),
		      let data = items[index].resumeData
		else { return }
		if resumeWebView == nil {
			resumeWebView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
		}
		items[index].status = .downloading
		items[index].errorMessage = nil
		persist()
		resumeWebView?.resumeDownload(fromResumeData: data) { [weak self] download in
			self?.attach(download, to: itemID)
		}
	}

	func pauseAllForQuit() async {
		isClosing = true
		for (key, download) in downloads {
			guard let itemID = itemIDs[key] else { continue }
			let data = await download.cancel()
			if let index = items.firstIndex(where: { $0.id == itemID && $0.status == .downloading }) {
				items[index].status = .paused
				items[index].resumeData = data
				items[index].errorMessage = data == nil ? "This download cannot resume." : nil
			}
		}
		persist()
	}

	func delete(_ itemID: UUID) {
		guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
		if let segments = items[index].segments {
			segmented.cancel(itemID)
			segmented.removeParts(itemID, count: segments.count)
		}
		if let key = itemIDs.first(where: { $0.value == itemID })?.key,
		   let download = downloads[key]
		{
			itemIDs[key] = nil
			observations[key] = nil
			downloads[key] = nil
			items[index].status = .paused
			updateDockProgress()
			Task { @MainActor in
				_ = await download.cancel()
				removeStoredItem(itemID)
			}
			return
		}
		removeStoredItem(itemID)
	}

	private func removeStoredItem(_ itemID: UUID) {
		guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
		let item = items[index]
		do {
			if FileManager.default.fileExists(atPath: item.fileURL.path) {
				try FileManager.default.removeItem(at: item.fileURL)
			}
			if let oldURL = previousTemporaryURLs.removeValue(forKey: itemID),
			   oldURL != item.fileURL,
			   FileManager.default.fileExists(atPath: oldURL.path)
			{
				try FileManager.default.removeItem(at: oldURL)
			}
		} catch {
			ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Could not delete download: \(error.localizedDescription)")
			return
		}
		items.remove(at: index)
		updateDockProgress()
		persist()
	}

	func revertName(_ itemID: UUID) {
		guard let index = items.firstIndex(where: { $0.id == itemID }),
		      items[index].status == .completed,
		      items[index].renamedByAppleIntelligence
		else { return }
		let source = items[index].fileURL
		let destination = uniqueDestination(fileName: items[index].originalName, in: source.deletingLastPathComponent())
		do {
			try FileManager.default.moveItem(at: source, to: destination)
			items[index].fileURL = destination
			items[index].renamedByAppleIntelligence = false
			persist()
		} catch {
			ToastManager.shared.show(symbol: "exclamationmark.triangle", message: error.localizedDescription)
		}
	}

	#if os(macOS)
		func open(_ itemID: UUID) {
			guard let item = items.first(where: { $0.id == itemID && $0.status == .completed }) else { return }
			NSWorkspace.shared.open(item.fileURL)
		}

		func revealInFolder(_ itemID: UUID) {
			guard let item = items.first(where: { $0.id == itemID }) else { return }
			NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
		}
	#endif

	private func maybeAccelerate(_ download: WKDownload, response: URLResponse) async {
		let key = ObjectIdentifier(download)
		guard let itemID = itemIDs[key],
		      !accelerationAbandoned.contains(itemID),
		      items.contains(where: { $0.id == itemID }),
		      let request = download.originalRequest,
		      let webView = download.webView,
		      request.httpMethod == "GET",
		      request.httpBody == nil,
		      request.value(forHTTPHeaderField: "Authorization") == nil,
		      request.value(forHTTPHeaderField: "Cookie") == nil,
		      let url = response.url,
		      url.scheme == "http" || url.scheme == "https",
		      let http = response as? HTTPURLResponse,
		      http.statusCode == 200,
		      response.expectedContentLength >= 2 * BrowserDownloadSegment.minimumSegmentBytes,
		      http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes",
		      [nil, "identity"].contains(http.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()),
		      let validator = strongValidator(from: http)
		else { return }

		let total = response.expectedContentLength
		let plannedSegments = BrowserDownloadSegment.plan(total: total)
		guard !plannedSegments.isEmpty else { return }

		let cookies = await withCheckedContinuation { continuation in
			webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
				continuation.resume(returning: cookies)
			}
		}
		let host = url.host?.lowercased() ?? ""
		let path = url.path.isEmpty ? "/" : url.path
		guard !cookies.contains(where: { cookie in
			let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
			return (host == domain || host.hasSuffix("." + domain))
				&& path.hasPrefix(cookie.path)
				&& (!cookie.isSecure || url.scheme == "https")
		}) else { return }
		guard downloads[key] != nil,
		      let currentIndex = items.firstIndex(where: { $0.id == itemID }),
		      items[currentIndex].status == .downloading
		else { return }

		items[currentIndex].segments = plannedSegments
		items[currentIndex].rangeValidator = validator
		items[currentIndex].totalBytes = total
		items[currentIndex].requestURL = url
		persist()
		finish(download)
		_ = await download.cancel()
		guard let resumedIndex = items.firstIndex(where: { $0.id == itemID && $0.segments != nil }) else { return }
		try? FileManager.default.removeItem(at: items[resumedIndex].fileURL)
		guard FileManager.default.createFile(atPath: items[resumedIndex].fileURL.path, contents: nil) else {
			segmentFailed(itemID)
			return
		}
		persist()
		segmented.start(items[resumedIndex])
	}

	private func strongValidator(from response: HTTPURLResponse) -> String? {
		if let etag = response.value(forHTTPHeaderField: "ETag"),
		   !etag.isEmpty,
		   !etag.hasPrefix("W/")
		{
			return etag
		}
		guard let lastModified = response.value(forHTTPHeaderField: "Last-Modified"),
		      !lastModified.isEmpty
		else { return nil }
		return lastModified
	}

	func updateSegmentProgress(_ itemID: UUID, index: Int, received: Int64) {
		guard let itemIndex = items.firstIndex(where: { $0.id == itemID }),
		      items[itemIndex].status == .downloading,
		      items[itemIndex].segments?.indices.contains(index) == true,
		      let total = items[itemIndex].totalBytes,
		      total > 0
		else { return }
		items[itemIndex].segments?[index].received = received
		let downloaded = items[itemIndex].segments?.reduce(Int64(0)) { sum, segment in
			sum + (segment.completed ? segment.end - segment.start + 1 : segment.received)
		} ?? 0
		items[itemIndex].progress = min(Double(downloaded) / Double(total), 1)
		updateDockProgress()
		if Date.now.timeIntervalSince(lastPersistedAt) > 1 {
			persist()
		}
	}

	func completeSegment(_ itemID: UUID, index: Int, partURL: URL, response: HTTPURLResponse?) {
		guard let itemIndex = items.firstIndex(where: { $0.id == itemID }),
		      items[itemIndex].status == .downloading,
		      let segments = items[itemIndex].segments,
		      segments.indices.contains(index),
		      let total = items[itemIndex].totalBytes,
		      let response,
		      response.statusCode == 206
		else {
			try? FileManager.default.removeItem(at: partURL)
			segmentFailed(itemID)
			return
		}
		let segment = segments[index]
		let expectedRange = "bytes \(segment.start)-\(segment.end)/\(total)"
		let validator = items[itemIndex].rangeValidator
		let responseValidator = validator?.hasPrefix("\"") == true
			? response.value(forHTTPHeaderField: "ETag")
			: response.value(forHTTPHeaderField: "Last-Modified")
		guard response.value(forHTTPHeaderField: "Content-Range") == expectedRange,
		      [nil, "identity"].contains(response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()),
		      responseValidator.map({ $0 == validator }) ?? true,
		      (try? partURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(segment.end - segment.start + 1)
		else {
			try? FileManager.default.removeItem(at: partURL)
			segmentFailed(itemID)
			return
		}
		do {
			let source = try FileHandle(forReadingFrom: partURL)
			let destination = try FileHandle(forWritingTo: items[itemIndex].fileURL)
			try destination.seek(toOffset: UInt64(segment.start))
			while let data = try source.read(upToCount: 1024 * 1024), !data.isEmpty {
				try destination.write(contentsOf: data)
			}
			try source.close()
			try destination.close()
			try FileManager.default.removeItem(at: partURL)
			items[itemIndex].segments?[index].completed = true
			items[itemIndex].segments?[index].received = segment.end - segment.start + 1
			updateSegmentProgress(itemID, index: index, received: segment.end - segment.start + 1)
			persist()
			if items[itemIndex].segments?.allSatisfy(\.completed) == true {
				let temporaryURL = items[itemIndex].fileURL
				let completedURL = uniqueDestination(
					fileName: temporaryURL.deletingPathExtension().lastPathComponent,
					in: temporaryURL.deletingLastPathComponent(),
					excludingTemporary: temporaryURL
				)
				try FileManager.default.moveItem(at: temporaryURL, to: completedURL)
				items[itemIndex].fileURL = completedURL
				items[itemIndex].status = .completed
				items[itemIndex].progress = 1
				items[itemIndex].segments = nil
				updateDockProgress()
				persist()
				ToastManager.shared.show(symbol: "arrow.down.circle", message: "Downloaded \(completedURL.lastPathComponent)")
			}
		} catch {
			segmentFailed(itemID)
		}
	}

	func segmentFailed(_ itemID: UUID) {
		guard let index = items.firstIndex(where: { $0.id == itemID }),
		      items[index].status == .downloading,
		      let segments = items[index].segments
		else { return }
		segmented.cancel(itemID)
		accelerationAbandoned.insert(itemID)
		segmented.removeParts(itemID, count: segments.count)
		try? FileManager.default.removeItem(at: items[index].fileURL)
		items[index].segments = nil
		items[index].rangeValidator = nil
		items[index].totalBytes = nil
		items[index].progress = 0
		guard let url = items[index].requestURL else {
			items[index].status = .failed
			items[index].errorMessage = "The download could not be restarted."
			persist()
			return
		}
		persist()
		if resumeWebView == nil {
			resumeWebView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
		}
		resumeWebView?.startDownload(using: URLRequest(url: url)) { [weak self] download in
			self?.attach(download, to: itemID)
		}
	}

	private var downloadDirectory: URL {
		#if os(macOS)
			URL.downloadsDirectory
		#else
			URL.documentsDirectory
		#endif
	}

	private func siteURL(for url: URL?) -> URL? {
		guard let url,
		      var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      components.host != nil
		else { return nil }
		components.user = nil
		components.password = nil
		components.path = ""
		components.query = nil
		components.fragment = nil
		return components.url
	}

	private func updateProgress(_ itemID: UUID, fraction: Double) {
		guard let index = items.firstIndex(where: { $0.id == itemID }),
		      items[index].status == .downloading
		else { return }
		items[index].progress = min(max(fraction, 0), 1)
		updateDockProgress()
		if Date.now.timeIntervalSince(lastPersistedAt) > 1 {
			persist()
		}
	}

	private func persist() {
		do {
			let data = try JSONEncoder().encode(items)
			try data.write(to: storeURL, options: .atomic)
			lastPersistedAt = .now
		} catch {
			ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Could not save downloads: \(error.localizedDescription)")
		}
	}

	private func uniqueDestination(fileName: String, in directory: URL, excludingTemporary: URL? = nil) -> URL {
		let source = URL(fileURLWithPath: fileName)
		let stem = source.deletingPathExtension().lastPathComponent
		let fileExtension = source.pathExtension
		var destination = directory.appending(path: fileName)
		var number = 2
		while FileManager.default.fileExists(atPath: destination.path)
			|| (destination.appendingPathExtension("astradownload") != excludingTemporary
				&& FileManager.default.fileExists(atPath: destination.appendingPathExtension("astradownload").path))
			|| (destination.appendingPathExtension("astradownload") != excludingTemporary
				&& destinations.values.contains(destination.appendingPathExtension("astradownload")))
		{
			let name = fileExtension.isEmpty
				? "\(stem) (\(number))"
				: "\(stem) (\(number)).\(fileExtension)"
			destination = directory.appending(path: name)
			number += 1
		}
		return destination
	}

	private func humanReadableStem(original: String, source: String?, fileType: String?) async -> String? {
		guard Defaults[.renameDownloadsWithAppleIntelligence],
		      SystemLanguageModel.default.isAvailable
		else { return nil }

		let session = LanguageModelSession {
			"Create short, descriptive file names. Return only a filename stem, without an extension or explanation."
		}
		let prompt = "Original filename: \(original)\nWebsite: \(source ?? "Unknown")\nFile type: \(fileType ?? "Unknown")"
		guard let response = try? await session.respond(to: prompt) else { return nil }
		let stem = Self.safeStem(response.content)
		return stem == "Download" ? nil : stem
	}

	private static func safeStem(_ name: String) -> String {
		let scalars = name.unicodeScalars.filter { !unsafeFilenameCharacters.contains($0) }
		let cleaned = String(String.UnicodeScalarView(scalars))
			.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
		let limited = String(cleaned.prefix(100))
		return limited.isEmpty ? "Download" : limited
	}
}
