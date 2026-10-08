import Defaults
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

#if os(macOS)
	import DockProgress
#endif

@MainActor
@Observable
final class BrowserDownloadManager: NSObject, WKDownloadDelegate {
	static let shared = BrowserDownloadManager()
	private static let unsafeFilenameCharacters = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)

	var aiSuggestedNames: [UUID: String] = [:]
	@ObservationIgnored private var aiRenameTasks: [UUID: Task<Void, Never>] = [:]
	@ObservationIgnored private var revertRenameTasks: [UUID: Task<Void, Never>] = [:]
	@ObservationIgnored private var finalizationTasks: [UUID: Task<Void, Never>] = [:]
	private var downloads: [ObjectIdentifier: WKDownload] = [:]
	private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
	private var destinations: [ObjectIdentifier: URL] = [:]
	private var itemIDs: [ObjectIdentifier: UUID] = [:]
	private var previousTemporaryURLs: [UUID: URL] = [:]
	private var finalDestinations: [UUID: URL] = [:]
	private var scopedDirectories: [UUID: URL] = [:]
	private var previewScopes: [URL: (directory: URL, count: Int)] = [:]
	private var accelerationAbandoned: Set<UUID> = []
	private(set) var accelerationPending: Set<UUID> = []
	private var resumeWebView: WKWebView?
	@ObservationIgnored private lazy var segmented = SegmentedDownloadEngine()
	private var isClosing = false
	private var deletingItems: Set<UUID> = []
	private var downloadCacheReadCompleted = false
	private var downloadCacheIsUnreadable = false
	private var restorationStarted = false
	private var lastPersistedAt = Date.distantPast
	@ObservationIgnored private var downloadPersistTask: Task<Void, Never>?
	@ObservationIgnored private var pauseTasks: [UUID: Task<Void, Never>] = [:]
	@ObservationIgnored private var rateSamples: [UUID: [(bytes: Int64, at: Date)]] = [:]
	@ObservationIgnored private var lastProgressForward: [UUID: (fraction: Double, at: Date)] = [:]

	/// Progress chunks arrive far more often than the eye (or dock) can use.
	/// Coalesce sub-half-percent ticks within 250 ms; completion always forwards.
	private func shouldForwardProgress(_ itemID: UUID, fraction: Double) -> Bool {
		guard fraction < 1 else {
			lastProgressForward[itemID] = nil
			return true
		}
		if let last = lastProgressForward[itemID],
		   abs(fraction - last.fraction) < 0.005,
		   Date.now.timeIntervalSince(last.at) < 0.25
		{
			return false
		}
		lastProgressForward[itemID] = (fraction, .now)
		return true
	}

	private let storeURL: URL
	private let stagingDirectory: URL
	private let privateDataStore: WKWebsiteDataStore?
	private let toastManager: ToastManager
	private(set) var items: [BrowserDownload] = []
	private(set) var selectedDownloadFolderName = ""
	private(set) var latestStart: (id: UUID, source: UnitPoint)?
	@ObservationIgnored private var downloadHydrationTask: Task<Void, Never>?

	var activeProgress: Double? {
		let active = items.filter { $0.status == .downloading || $0.status == .finalizing }
		guard !active.isEmpty else { return nil }
		return active.reduce(0) { $0 + $1.progress } / Double(active.count)
	}

	var buttonSymbol: String {
		items.first(where: { $0.status == .downloading })?.symbol
			?? items.first?.symbol
			?? "arrow.down.circle"
	}

	func transferModeDescription(for item: BrowserDownload) -> String {
		if let segments = item.segments, !segments.isEmpty {
			return "\(segments.count) download pieces"
		}
		if accelerationPending.contains(item.id) {
			return "Checking connections…"
		}
		return "Single connection"
	}

	override private convenience init() {
		self.init(privateDataStore: nil, toastManager: .shared)
	}

	init(privateDataStore: WKWebsiteDataStore?, toastManager: ToastManager) {
		BrowserLog.info(.downloads, "downloads.manager-init", metadata: ["private": String(privateDataStore != nil)])
		self.privateDataStore = privateDataStore
		self.toastManager = toastManager
		let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent(Bundle.main.bundleIdentifier ?? "browser", isDirectory: true)
		if privateDataStore == nil {
			try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		}
		storeURL = directory.appendingPathComponent("downloads.json")
		stagingDirectory = privateDataStore == nil
			? directory.appendingPathComponent("download-staging", isDirectory: true)
			: FileManager.default.temporaryDirectory.appendingPathComponent("astra-private-downloads-\(UUID().uuidString)", isDirectory: true)
		super.init()
		selectedDownloadFolderName = Self.defaultDownloadDirectory.lastPathComponent
		if privateDataStore == nil {
			hydrateSelectedDownloadFolderName()
			hydrateItems()
		}
		#if DEBUG
			assert(Self.safeStem("../unsafe\\name") == "unsafename")
		#endif
		updateDockProgress()
	}

	#if os(macOS)
		private nonisolated static func resolvedDownloadFolderDisplay(
			_ data: Data
		) -> (name: String, renewedBookmark: Data?)? {
			var stale = false
			guard let url = try? URL(
				resolvingBookmarkData: data,
				options: [.withSecurityScope, .withoutUI],
				relativeTo: nil,
				bookmarkDataIsStale: &stale
			) else { return nil }
			let renewed = stale
				? try? url.bookmarkData(
					options: [.withSecurityScope],
					includingResourceValuesForKeys: nil,
					relativeTo: nil
				)
				: nil
			return (url.lastPathComponent, renewed)
		}
	#endif

	private func hydrateSelectedDownloadFolderName() {
		#if os(macOS)
			guard let data = Data(base64Encoded: Defaults[.downloadsFolderBookmark]),
			      !data.isEmpty else { return }
			let resolveTask = Task.detached(priority: .utility) {
				Self.resolvedDownloadFolderDisplay(data)
			}
			Task { @MainActor [weak self] in
				guard let result = await resolveTask.value, let self else { return }
				selectedDownloadFolderName = result.name
				if let renewed = result.renewedBookmark {
					Defaults[.downloadsFolderBookmark] = renewed.base64EncodedString()
				}
			}
		#endif
	}

	private func hydrateItems() {
		let logStarted = BrowserLog.clock()
		BrowserLog.debug(.downloads, "downloads.hydrate.begin", metadata: ["store": BrowserLog.path(storeURL)])
		let url = storeURL
		downloadHydrationTask = Task.detached(priority: .utility) {
			guard let data = try? Data(contentsOf: url) else {
				if FileManager.default.fileExists(atPath: url.path) {
					await MainActor.run { [weak self] in self?.preserveUnreadableDownloadCache() }
				} else {
					await MainActor.run { [weak self] in
						guard let self else { return }
						downloadCacheReadCompleted = true
						if !isClosing, !items.isEmpty {
							persist()
						}
					}
				}
				return
			}
			guard let saved = try? JSONDecoder().decode([BrowserDownload].self, from: data) else {
				await MainActor.run { [weak self] in self?.preserveUnreadableDownloadCache() }
				return
			}
			let restored = saved.map { item -> BrowserDownload in
				var item = item
				item.throughput = nil
				item.estimatedTimeRemaining = nil
				if item.status == .downloading, item.segments == nil {
					item.status = .paused
					item.errorMessage = "Download interrupted."
				} else if item.status == .finalizing && !FileManager.default.fileExists(atPath: item.fileURL.path) {
					item.status = .failed
					item.errorMessage = "The temporary download disappeared during finalization."
				}
				return item
			}
			await MainActor.run { [weak self] in
				guard let self else { return }
				let liveIDs = Set(items.map(\.id))
				items = items + restored.filter { !liveIDs.contains($0.id) }
				for item in items where item.status == .downloading || item.status == .finalizing {
					if let destinationURL = item.destinationURL {
						finalDestinations[item.id] = destinationURL
					}
				}
				downloadCacheReadCompleted = true
				restorationStarted = false
				BrowserLog.duration(.downloads, "downloads.hydrate.end", since: logStarted, warnAboveMilliseconds: 250, metadata: ["items": String(items.count)])
				if !isClosing {
					Task { @MainActor [weak self] in
						try? await Task.sleep(for: .milliseconds(750))
						guard !Task.isCancelled else { return }
						self?.resumeAvailableDownloads()
					}
				}
				updateDockProgress()
				if !isClosing {
					persist()
				}
			}
		}
	}

	private func preserveUnreadableDownloadCache() {
		BrowserLog.error(.downloads, "downloads.cache-unreadable", metadata: ["store": BrowserLog.path(storeURL)])
		downloadCacheReadCompleted = true
		downloadCacheIsUnreadable = true
		downloadPersistTask?.cancel()
		downloadPersistTask = nil
		showToast(symbol: "exclamationmark.triangle", message: "Saved downloads could not be read. Existing download data was preserved.")
	}

	func start(_ download: WKDownload, sourceURL: URL? = nil, source: UnitPoint = .center) {
		BrowserLog.info(.downloads, "download.start", metadata: ["source": BrowserLog.url(sourceURL ?? download.webView?.url), "request": BrowserLog.request(download.originalRequest), "private": String(privateDataStore != nil)])
		guard !isClosing else {
			Task { @MainActor in
				_ = await download.cancel()
			}
			return
		}
		let id = ObjectIdentifier(download)
		guard downloads[id] == nil else { return }
		let itemID = UUID()
		let request = download.originalRequest
		let requestURL = credentialFreeURL(request?.url)
		let name = BrowserDownload.safeFilename(requestURL?.lastPathComponent ?? "")
		let provisionalURL = stagingDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("astradownload")
		items.insert(
			BrowserDownload(
				id: itemID,
				createdAt: .now,
				sourceURL: siteURL(for: sourceURL ?? download.webView?.url ?? requestURL),
				requestURL: requestURL,
				retryURL: requestURL,
				requestMethod: request?.httpMethod,
				requestHasBody: request.map(BrowserDownload.requestHasBody) ?? false,
				requestHasAuthorization: request.map(BrowserDownload.requestMayCarryCredentials) ?? false,
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
		BrowserLog.debug(.downloads, "download.attach", metadata: ["item": BrowserLog.id(itemID)])
		guard !isClosing,
		      !deletingItems.contains(itemID),
		      items.contains(where: { $0.id == itemID && $0.status == .downloading })
		else {
			Task { @MainActor in
				_ = await download.cancel()
			}
			return
		}
		let id = ObjectIdentifier(download)
		downloads[id] = download
		itemIDs[id] = itemID
		download.delegate = self
		observations[id] = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
			let fraction = progress.fractionCompleted
			let received = progress.completedUnitCount
			let total = progress.totalUnitCount
			let throughput = progress.throughput
			let estimatedTimeRemaining = progress.estimatedTimeRemaining
			Task { @MainActor [weak self] in
				self?.updateProgress(
					itemID,
					downloadID: id,
					fraction: fraction,
					received: received,
					total: total,
					throughput: throughput,
					estimatedTimeRemaining: estimatedTimeRemaining
				)
			}
		}
		updateDockProgress()
	}

	private func presentationWindow(for download: WKDownload) -> AnyObject? {
		#if os(macOS)
			download.webView?.window
				?? (BrowserWindowRegistry.shared.activeBrowser?.session.downloads === self ? NSApp.keyWindow : nil)
		#else
			download.webView?.window
		#endif
	}

	func download(
		_ download: WKDownload,
		decideDestinationUsing response: URLResponse,
		suggestedFilename: String,
		completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
	) {
		Task { @MainActor in
			let downloadID = ObjectIdentifier(download)
			let originalRequest = download.originalRequest
			guard !isClosing,
			      let itemID = itemIDs[downloadID],
			      downloads[downloadID] != nil,
			      items.contains(where: { $0.id == itemID && $0.status == .downloading })
			else {
				completionHandler(nil)
				return
			}
			let original = URL(fileURLWithPath: suggestedFilename).lastPathComponent
			let safeOriginal = BrowserDownload.safeFilename(original)
			let originalExtension = String(String.UnicodeScalarView(
				URL(fileURLWithPath: safeOriginal).pathExtension.unicodeScalars.filter {
					!Self.unsafeFilenameCharacters.contains($0)
				}
			))
			let originalStem = URL(fileURLWithPath: safeOriginal).deletingPathExtension().lastPathComponent
			var stem = Self.safeStem(originalStem)
			let repeatedExtension = ".\(originalExtension)"
			if !originalExtension.isEmpty,
			   stem.lowercased().hasSuffix(repeatedExtension.lowercased())
			{
				stem = String(stem.dropLast(repeatedExtension.count))
			}
			let fileName = BrowserDownload.safeFilename(originalExtension.isEmpty ? stem : "\(stem).\(originalExtension)")
			do {
				guard let finalURL = await self.selectedFinalDestination(
					fileName: fileName,
					window: presentationWindow(for: download),
					itemID: itemID,
					downloadID: downloadID
				) else {
					completionHandler(nil)
					if !isClosing,
					   downloads[downloadID] != nil,
					   let liveIndex = items.firstIndex(where: { $0.id == itemID && $0.status == .downloading })
					{
						markFailed(at: liveIndex)
						items[liveIndex].resumeData = nil
						items[liveIndex].throughput = nil
						items[liveIndex].estimatedTimeRemaining = nil
						items[liveIndex].errorMessage = "Download cancelled because no destination was selected."
						try? FileManager.default.removeItem(at: items[liveIndex].fileURL)
					}
					finish(download)
					persist()
					return
				}
				guard !isClosing,
				      let currentIndex = items.firstIndex(where: { $0.id == itemID && $0.status == .downloading }),
				      downloads[downloadID] != nil
				else {
					releaseScope(for: itemID)
					completionHandler(nil)
					return
				}
				try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
				let destination = stagingDirectory
					.appendingPathComponent(UUID().uuidString)
					.appendingPathExtension("astradownload")
				if FileManager.default.fileExists(atPath: items[currentIndex].fileURL.path) {
					previousTemporaryURLs[itemID] = items[currentIndex].fileURL
				}
				items[currentIndex].fileURL = destination
				items[currentIndex].destinationURL = finalURL
				items[currentIndex].originalName = safeOriginal
				items[currentIndex].requestURL = credentialFreeURL(response.url)
				items[currentIndex].totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
				if items[currentIndex].destinationIsFileScoped != true,
				   items[currentIndex].fileAccessBookmark == nil,
				   items[currentIndex].folderBookmark == nil,
				   let folderBookmark = Data(base64Encoded: Defaults[.downloadsFolderBookmark]),
				   !folderBookmark.isEmpty
				{
					items[currentIndex].folderBookmark = folderBookmark
				}
				items[currentIndex].renamedByAppleIntelligence = false
				items[currentIndex].resumeData = nil
				items[currentIndex].throughput = nil
				items[currentIndex].estimatedTimeRemaining = nil
				items[currentIndex].errorMessage = nil
				finalDestinations[itemID] = finalURL
				destinations[downloadID] = destination
				persist()
				completionHandler(destination)
				await maybeAccelerate(download, response: response, originalRequest: originalRequest)
			} catch {
				guard let liveIndex = items.firstIndex(where: { $0.id == itemID && $0.status == .downloading }),
				      downloads[ObjectIdentifier(download)] != nil
				else {
					completionHandler(nil)
					return
				}
				showToast(symbol: "exclamationmark.triangle", message: "Download failed: \(error.localizedDescription)")
				markFailed(at: liveIndex)
				items[liveIndex].errorMessage = error.localizedDescription
				completionHandler(nil)
				finish(download)
				persist()
			}
		}
	}

	func download(
		_ download: WKDownload,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		#if os(macOS)
			Task { @MainActor in
				let window = presentationWindow(for: download) as? NSWindow
				let response = await BrowserWebsiteUI.authenticate(challenge, in: window) { [self, download] in
					downloads[ObjectIdentifier(download)] != nil
				}
				guard downloads[ObjectIdentifier(download)] != nil else {
					completionHandler(.cancelAuthenticationChallenge, nil)
					return
				}
				completionHandler(response.0, response.1)
			}
		#elseif os(iOS)
			Task { @MainActor in
				guard let webView = download.webView else {
					completionHandler(.performDefaultHandling, nil)
					return
				}
				let response = await BrowserWebsiteUI.authenticate(challenge, in: webView) { [self, download] in
					downloads[ObjectIdentifier(download)] != nil
				}
				guard downloads[ObjectIdentifier(download)] != nil else {
					completionHandler(.cancelAuthenticationChallenge, nil)
					return
				}
				completionHandler(response.0, response.1)
			}
		#else
			completionHandler(.performDefaultHandling, nil)
		#endif
	}

	func download(
		_ download: WKDownload,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest: URLRequest,
		decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void
	) {
		guard let url = newRequest.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
			decisionHandler(.cancel)
			return
		}
		#if os(macOS)
			if response.url?.scheme == "https", url.scheme == "http" {
				Task { @MainActor in
					let alert = BrowserWebsiteUI.alert(title: "Download over an insecure connection?", message: "The download redirects from HTTPS to HTTP.", confirm: "Download")
					let choice = await BrowserWebsiteUI.present(alert, in: presentationWindow(for: download) as? NSWindow)
					guard downloads[ObjectIdentifier(download)] != nil else {
						decisionHandler(.cancel)
						return
					}
					decisionHandler(choice == .alertFirstButtonReturn ? .allow : .cancel)
				}
				return
			}
		#endif
		decisionHandler(.allow)
	}

	func downloadDidFinish(_ download: WKDownload) {
		BrowserLog.info(.downloads, "download.webkit-finished")
		if let itemID = itemIDs[ObjectIdentifier(download)],
		   let temporaryURL = destinations[ObjectIdentifier(download)] {
			beginFinalization(itemID, temporaryURL: temporaryURL)
		}
		// The file worker maintains its own scope (or retains the existing
		// selected-file scope) until publication and bookmark renewal finish.
		finish(download)
		persist()
	}

	/// Both WebKit and segmented transfers use exactly the same finalization
	/// state machine. The worker owns slow copies and atomic publication.
	private func beginFinalization(_ itemID: UUID, temporaryURL: URL) {
		guard !isClosing, finalizationTasks[itemID] == nil,
		      !deletingItems.contains(itemID),
		      let index = items.firstIndex(where: {
		      	$0.id == itemID && $0.fileURL == temporaryURL
		      		&& ($0.status == .downloading || $0.status == .finalizing)
		      }) else { return }
		let proposedURL = finalDestinations[itemID] ?? items[index].destinationURL ?? temporaryURL.deletingPathExtension()
		items[index].status = .finalizing
		items[index].destinationURL = proposedURL
		items[index].throughput = nil
		items[index].estimatedTimeRemaining = nil
		let snapshot = items[index]
		let bookmark = snapshot.fileAccessBookmark ?? snapshot.folderBookmark
		let hadScope = scopedDirectories[itemID] != nil
		persist()
		BrowserLog.info(.downloads, "download.finalization.begin", metadata: ["item": BrowserLog.id(itemID)])
		finalizationTasks[itemID] = Task { @MainActor [weak self] in
			defer { self?.finalizationTasks[itemID] = nil }
			do {
				let committedURL = try await BrowserDownloadFileWorker.shared.commit(
					source: temporaryURL,
					proposed: proposedURL,
					fileScoped: snapshot.destinationIsFileScoped == true,
					bookmark: bookmark,
					hasExistingAccess: hadScope,
					downloadURL: snapshot.requestURL,
					originURL: snapshot.sourceURL
				)
				guard let self else { return }
				guard !deletingItems.contains(itemID),
				      let currentIndex = items.firstIndex(where: {
				      	$0.id == itemID && $0.status == .finalizing && $0.fileURL == temporaryURL
				      })
				else {
					// Cancellation/deletion raced with destination publication.
					// The committed destination belongs to this operation.
					await BrowserDownloadFileWorker.shared.removeFiles([committedURL])
					return
				}
				items[currentIndex].fileURL = committedURL
				items[currentIndex].status = .completed
				items[currentIndex].progress = 1
				items[currentIndex].receivedBytes = items[currentIndex].totalBytes ?? items[currentIndex].receivedBytes
				items[currentIndex].resumeData = nil
				items[currentIndex].segments = nil
				items[currentIndex].destinationURL = nil
				items[currentIndex].throughput = nil
				items[currentIndex].estimatedTimeRemaining = nil
				#if os(macOS)
					if snapshot.destinationIsFileScoped == true {
						items[currentIndex].fileAccessBookmark = try? committedURL.bookmarkData(
							options: [.withSecurityScope],
							includingResourceValuesForKeys: nil,
							relativeTo: nil
						)
						if items[currentIndex].fileAccessBookmark == nil {
							showFileAccessToast()
						}
					}
				#endif
				if let oldURL = previousTemporaryURLs.removeValue(forKey: itemID), oldURL != temporaryURL {
					await BrowserDownloadFileWorker.shared.removeFiles([oldURL])
				}
				finalDestinations[itemID] = nil
				releaseScope(for: itemID)
				updateDockProgress()
				persist()
				BrowserLog.info(.downloads, "download.finalization.end", metadata: ["item": BrowserLog.id(itemID)])
				showToast(symbol: "arrow.down.circle", message: "Downloaded \(committedURL.lastPathComponent)")
				aiRenameTasks[itemID] = Task { @MainActor [weak self] in
					defer { self?.aiRenameTasks[itemID] = nil }
					await self?.renameWithAppleIntelligence(itemID, fileURL: committedURL)
				}
			} catch {
				guard let self,
				      let currentIndex = items.firstIndex(where: {
				      	$0.id == itemID && $0.fileURL == temporaryURL && $0.status == .finalizing
				      }) else { return }
				BrowserLog.error(.downloads, "download.finalization.failed", metadata: [
					"item": BrowserLog.id(itemID), "error": BrowserLog.errorDescription(error),
				])
				markFailed(at: currentIndex)
				items[currentIndex].errorMessage = error.localizedDescription
				finalDestinations[itemID] = nil
				releaseScope(for: itemID)
				updateDockProgress()
				persist()
				showToast(symbol: "exclamationmark.triangle", message: "Download finalization failed: \(error.localizedDescription)")
			}
		}
	}

	private func markFailed(at index: Int) {
		items[index].status = .failed
		BrowserDiagnosticEventStore.shared.record(.downloadFailure, code: "download.failed", isPrivate: privateDataStore != nil)
	}

	func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
		BrowserLog.error(.downloads, "download.transfer-failed", metadata: ["error": BrowserLog.errorDescription(error), "resume_bytes": String(resumeData?.count ?? 0)])
		guard downloads[ObjectIdentifier(download)] != nil else { return }
		if !isClosing {
			if let itemID = itemIDs[ObjectIdentifier(download)],
			   let index = items.firstIndex(where: { $0.id == itemID })
			{
				items[index].resumeData = resumeData
				items[index].status = resumeData == nil ? .failed : .paused
				BrowserDiagnosticEventStore.shared.record(.downloadFailure, code: "download.transfer", isPrivate: privateDataStore != nil)
				items[index].errorMessage = error.localizedDescription
				items[index].throughput = nil
				items[index].estimatedTimeRemaining = nil
				if resumeData == nil {
					try? FileManager.default.removeItem(at: items[index].fileURL)
				}
			}
			showToast(symbol: "exclamationmark.triangle", message: "Download failed: \(error.localizedDescription)")
		}
		finish(download)
		persist()
	}

	private func finish(_ download: WKDownload) {
		let id = ObjectIdentifier(download)
		let itemID = itemIDs[id]
		observations[id] = nil
		downloads[id] = nil
		itemIDs[id] = nil
		destinations[id] = nil
		if let itemID, finalizationTasks[itemID] == nil,
		   items.first(where: { $0.id == itemID })?.segments == nil {
			releaseScope(for: itemID)
		}
		updateDockProgress()
	}

	private func updateDockProgress() {
		#if os(macOS)
			if privateDataStore == nil {
				DockProgress.progress = activeProgress ?? 0
			}
		#endif
	}

	func resumeAvailableDownloads() {
		BrowserLog.info(.downloads, "downloads.resume-available", metadata: ["items": String(items.count)])
		guard !isClosing, !restorationStarted else { return }
		restorationStarted = true
		for item in items where item.status == .finalizing {
			beginFinalization(item.id, temporaryURL: item.fileURL)
		}
		for item in items where item.status == .downloading && item.segments != nil {
			if item.segments?.allSatisfy(\.completed) == true {
				beginFinalization(item.id, temporaryURL: item.fileURL)
			} else if item.destinationIsFileScoped == true, item.fileAccessBookmark == nil {
				segmentFailed(item.id)
			} else {
				segmented.start(item)
			}
		}

		persist()
	}

	func resume(_ itemID: UUID) {
		BrowserLog.info(.downloads, "download.resume", metadata: ["item": BrowserLog.id(itemID)])
		guard !isClosing,
		      !deletingItems.contains(itemID),
		      pauseTasks[itemID] == nil,
		      !itemIDs.values.contains(itemID),
		      let index = items.firstIndex(where: { $0.id == itemID && $0.canResume })
		else { return }
		if items[index].segments != nil {
			items[index].status = .downloading
			guard FileManager.default.fileExists(atPath: items[index].fileURL.path) else {
				segmentFailed(itemID)
				return
			}
			items[index].errorMessage = nil
			rateSamples[itemID] = nil
			segmented.start(items[index])
			updateDockProgress()
			persist()
			return
		}
		guard let data = items[index].resumeData else { return }
		rateSamples[itemID] = nil
		if resumeWebView == nil {
			let configuration = WKWebViewConfiguration()
			configuration.websiteDataStore = privateDataStore ?? .default()
			resumeWebView = WKWebView(frame: .zero, configuration: configuration)
		}
		items[index].status = .downloading
		items[index].errorMessage = nil
		items[index].throughput = nil
		items[index].estimatedTimeRemaining = nil
		persist()
		resumeWebView?.resumeDownload(fromResumeData: data) { [weak self] download in
			self?.attach(download, to: itemID)
		}
	}

	func retry(_ itemID: UUID) {
		BrowserLog.info(.downloads, "download.retry", metadata: ["item": BrowserLog.id(itemID)])
		guard !isClosing,
		      !deletingItems.contains(itemID),
		      pauseTasks[itemID] == nil,
		      !itemIDs.values.contains(itemID),
		      let index = items.firstIndex(where: { $0.id == itemID && $0.canRetry }),
		      let url = items[index].retryURL
		else { return }
		if resumeWebView == nil {
			let configuration = WKWebViewConfiguration()
			configuration.websiteDataStore = privateDataStore ?? .default()
			resumeWebView = WKWebView(frame: .zero, configuration: configuration)
		}
		rateSamples[itemID] = nil
		items[index].resumeData = nil
		items[index].status = .downloading
		items[index].progress = 0
		items[index].receivedBytes = 0
		items[index].errorMessage = nil
		items[index].throughput = nil
		items[index].estimatedTimeRemaining = nil
		persist()
		resumeWebView?.startDownload(using: URLRequest(url: url)) { [weak self] download in
			self?.attach(download, to: itemID)
		}
	}

	func pause(_ itemID: UUID) {
		guard !isClosing, pauseTasks[itemID] == nil else { return }
		pauseTasks[itemID] = Task { @MainActor in
			await pauseTransfer(itemID)
			pauseTasks[itemID] = nil
		}
	}

	private func pauseTransfer(_ itemID: UUID) async {
		guard let index = items.firstIndex(where: { $0.id == itemID && $0.status == .downloading }) else { return }
		items[index].status = .paused
		items[index].throughput = nil
		items[index].estimatedTimeRemaining = nil
		rateSamples[itemID] = nil
		if items[index].segments != nil {
			await segmented.pause(itemID)
		} else if let key = itemIDs.first(where: { $0.value == itemID })?.key,
		          let download = downloads[key]
		{
			finish(download)
			let data = await download.cancel()
			if let currentIndex = items.firstIndex(where: { $0.id == itemID && $0.status == .paused }) {
				items[currentIndex].resumeData = data
				items[currentIndex].errorMessage = data == nil ? "Cannot resume; restart required." : nil
			}
		}
		updateDockProgress()
		persist()
	}

	func cancel(_ itemID: UUID) {
		if !isClosing, let task = finalizationTasks[itemID],
		   let index = items.firstIndex(where: { $0.id == itemID && $0.status == .finalizing }) {
			items[index].status = .cancelled
			items[index].errorMessage = nil
			items[index].throughput = nil
			items[index].estimatedTimeRemaining = nil
			let temporary = items[index].fileURL
			task.cancel()
			persist()
			Task { @MainActor [weak self] in
				await task.value
				guard let self,
				      items.contains(where: { $0.id == itemID && $0.status == .cancelled }) else { return }
				await BrowserDownloadFileWorker.shared.removeFiles([temporary])
				releaseScope(for: itemID)
				updateDockProgress()
				persist()
			}
			return
		}
		guard !isClosing, pauseTasks[itemID] == nil, let item = items.first(where: { $0.id == itemID }),
		      item.status == .downloading || item.status == .paused else { return }
		pauseTasks[itemID] = Task { @MainActor in
			await pauseTransfer(itemID)
			guard let index = items.firstIndex(where: { $0.id == itemID }) else {
				pauseTasks[itemID] = nil
				return
			}
			items[index].status = .cancelled
			items[index].resumeData = nil
			items[index].errorMessage = nil
			if let segments = items[index].segments {
				await segmented.cancelAndWait([itemID])
				await segmented.removeParts(itemID, count: segments.count)
			}
			guard let index = items.firstIndex(where: { $0.id == itemID }) else {
				pauseTasks[itemID] = nil
				return
			}
			items[index].segments = nil
			items[index].rangeValidator = nil
			await BrowserDownloadFileWorker.shared.removeFiles([items[index].fileURL])
			releaseScope(for: itemID)
			pauseTasks[itemID] = nil
			persist()
		}
	}

	func pauseAllForQuit() async {
		BrowserLog.notice(.downloads, "downloads.pause-for-quit", metadata: ["active": String(downloads.count)])
		isClosing = true
		let pendingRenames = Array(aiRenameTasks.values) + Array(revertRenameTasks.values)
		for task in pendingRenames { task.cancel() }
		for task in pendingRenames { await task.value }
		aiRenameTasks.removeAll()
		revertRenameTasks.removeAll()
		// Quit awaits existing filesystem commits rather than interrupting the
		// atomic destination move or persisting a false completion state.
		for task in Array(finalizationTasks.values) {
			await task.value
		}
		let pendingWrite = downloadPersistTask
		pendingWrite?.cancel()
		downloadPersistTask = nil
		await pendingWrite?.value
		await downloadHydrationTask?.value
		for task in Array(pauseTasks.values) {
			await task.value
		}
		for item in items where item.status == .downloading {
			await pauseTransfer(item.id)
		}
		flushDownloads()
	}

	func endPrivateSession() async {
		guard privateDataStore != nil else { return }
		isClosing = true
		for item in items where item.status == .finalizing {
			if let index = items.firstIndex(where: { $0.id == item.id }) {
				items[index].status = .cancelled
			}
		}
		for task in Array(finalizationTasks.values) {
			task.cancel()
			await task.value
		}
		for download in Array(downloads.values) {
			_ = await download.cancel()
			finish(download)
		}
		for item in items where item.status != .completed {
			if let segments = item.segments {
				segmented.cancel(item.id)
				await segmented.removeParts(item.id, count: segments.count)
			}
			await BrowserDownloadFileWorker.shared.removeFiles([item.fileURL])
			if let previousURL = previousTemporaryURLs.removeValue(forKey: item.id), previousURL != item.fileURL {
				await BrowserDownloadFileWorker.shared.removeFiles([previousURL])
			}
			releaseScope(for: item.id)
		}
		items.removeAll()
		await BrowserDownloadFileWorker.shared.removeFiles([stagingDirectory])
		resumeWebView = nil
	}

	func delete(_ itemID: UUID) {
		BrowserLog.info(.downloads, "download.delete", metadata: ["item": BrowserLog.id(itemID)])
		// A file move may already have begun when the user deletes an entry.
		// Await that operation before resolving which path needs cleanup.
		let pendingRenames = [
			aiRenameTasks.removeValue(forKey: itemID),
			revertRenameTasks.removeValue(forKey: itemID),
		].compactMap { $0 }
		for task in pendingRenames { task.cancel() }
		guard pauseTasks[itemID] == nil, let index = items.firstIndex(where: { $0.id == itemID }) else { return }
		guard deletingItems.insert(itemID).inserted else { return }
		if !pendingRenames.isEmpty, items[index].status == .completed {
			Task { @MainActor [weak self] in
				for task in pendingRenames { await task.value }
				self?.removeStoredItem(itemID)
			}
			return
		}
		if let task = finalizationTasks[itemID] {
			task.cancel()
			items[index].status = .cancelled
			Task { @MainActor [weak self] in
				await task.value
				self?.removeStoredItem(itemID)
			}
			return
		}
		if let segments = items[index].segments {
			segmented.cancel(itemID)
			Task { @MainActor [weak self] in
				guard let self else { return }
				await segmented.removeParts(itemID, count: segments.count)
				removeStoredItem(itemID)
			}
			return
		}
		if let key = itemIDs.first(where: { $0.value == itemID })?.key,
		   let download = downloads[key]
		{
			itemIDs[key] = nil
			observations[key] = nil
			downloads[key] = nil
			destinations[key] = nil
			items[index].markCancellationPending()
			updateDockProgress()
			Task { @MainActor in
				_ = await download.cancel()
				releaseScope(for: itemID)
				removeStoredItem(itemID)
			}
			return
		}
		removeStoredItem(itemID)
	}

	private func removeStoredItem(_ itemID: UUID) {
		guard let index = items.firstIndex(where: { $0.id == itemID }) else {
			deletingItems.remove(itemID)
			return
		}
		let item = items[index]
		let older = previousTemporaryURLs[itemID]
		var files: [URL] = []
		if item.status != .completed {
			files.append(item.fileURL)
		}
		if let older, older != item.fileURL {
			files.append(older)
		}
		// Retain the current security scope while the background actor deletes
		// the temporary files. Do not remove the model before I/O succeeds.
		let bookmark = item.fileAccessBookmark ?? item.folderBookmark
		let hadScope = scopedDirectories[itemID] != nil
		Task { @MainActor [weak self] in
			do {
				try await BrowserDownloadFileWorker.shared.deleteTemporaryFiles(
					files,
					in: stagingDirectory,
					bookmark: bookmark,
					hasExistingAccess: hadScope
				)
			} catch {
				guard let self else { return }
				deletingItems.remove(itemID)
				showToast(symbol: "exclamationmark.triangle", message: "Could not delete download: \(error.localizedDescription)")
				return
			}
			guard let self, deletingItems.contains(itemID),
			      let currentIndex = items.firstIndex(where: { $0.id == itemID && $0.fileURL == item.fileURL })
			else { return }
			items.remove(at: currentIndex)
			previousTemporaryURLs[itemID] = nil
			deletingItems.remove(itemID)
			releaseScope(for: itemID)
			finalDestinations[itemID] = nil
			lastProgressForward[itemID] = nil
			updateDockProgress()
			persist()
		}
	}

	func revertName(_ itemID: UUID) {
		guard revertRenameTasks[itemID] == nil,
		      !deletingItems.contains(itemID),
		      let item = items.first(where: {
		      	$0.id == itemID && $0.status == .completed && $0.renamedByAppleIntelligence
		      }) else { return }
		let source = item.fileURL
		let bookmark = item.fileAccessBookmark ?? item.folderBookmark
		let hadScope = scopedDirectories[itemID] != nil
		revertRenameTasks[itemID] = Task { @MainActor [weak self] in
			defer { self?.revertRenameTasks[itemID] = nil }
			do {
				let destination = try await BrowserDownloadFileWorker.shared.renameExisting(
					source: source, fileName: item.originalName,
					bookmark: bookmark, hasExistingAccess: hadScope
				)
				guard let self, let index = items.firstIndex(where: {
					$0.id == itemID && $0.status == .completed && $0.fileURL == source
				}) else { return }
				items[index].fileURL = destination
				items[index].renamedByAppleIntelligence = false
				persist()
			} catch {
				self?.showToast(symbol: "exclamationmark.triangle", message: error.localizedDescription)
			}
		}
	}

	#if os(macOS)
		func dragProvider(_ itemID: UUID) -> NSItemProvider? {
			guard let item = items.first(where: { $0.id == itemID && $0.status == .completed }),
			      !deletingItems.contains(itemID),
			      !(item.destinationIsFileScoped == true && item.fileAccessBookmark == nil)
			else { return nil }
			let expectedURL = item.fileURL
			let expectedName = item.name
			let type = UTType(filenameExtension: expectedURL.pathExtension) ?? .data
			let lifetime = BrowserDownloadDragFile()
			let provider = NSItemProvider()
			provider.suggestedName = expectedName
			provider.registerFileRepresentation(
				forTypeIdentifier: type.identifier,
				fileOptions: [],
				visibility: .all
			) { [weak self, lifetime] completionHandler in
				let progress = Progress(totalUnitCount: 1)
				Task { @MainActor [weak self, lifetime] in
					guard let self else {
						completionHandler(nil, false, CocoaError(.userCancelled))
						progress.cancel()
						return
					}
					do {
						let file = try await prepareDragFile(
							itemID,
							expectedURL: expectedURL,
							expectedName: expectedName,
							lifetime: lifetime
						)
						completionHandler(file, false, nil)
						progress.completedUnitCount = 1
					} catch {
						completionHandler(nil, false, error)
						progress.cancel()
					}
				}
				return progress
			}
			return provider
		}

		private func prepareDragFile(
			_ itemID: UUID,
			expectedURL: URL,
			expectedName: String,
			lifetime: BrowserDownloadDragFile
		) async throws -> URL {
			guard let item = items.first(where: {
				$0.id == itemID
					&& $0.status == .completed
					&& $0.fileURL.standardizedFileURL == expectedURL.standardizedFileURL
					&& $0.name == expectedName
			}),
				!deletingItems.contains(itemID)
			else { throw CocoaError(.fileNoSuchFile) }
			let sourceURL = item.fileURL
			let bookmark = item.fileAccessBookmark ?? item.folderBookmark
			let fileBookmark = item.fileAccessBookmark != nil
			let copy = try await Task.detached(priority: .userInitiated) {
				try lifetime.copy(sourceURL, named: expectedName, bookmark: bookmark)
			}.value
			guard items.contains(where: {
				$0.id == itemID
					&& $0.status == .completed
					&& $0.fileURL.standardizedFileURL == expectedURL.standardizedFileURL
					&& $0.name == expectedName
			}),
				!deletingItems.contains(itemID)
			else {
				lifetime.discard(copy.fileURL)
				throw CocoaError(.fileNoSuchFile)
			}
			if let renewedBookmark = copy.renewedBookmark,
			   let index = items.firstIndex(where: { $0.id == itemID })
			{
				if fileBookmark {
					items[index].fileAccessBookmark = renewedBookmark
				} else {
					items[index].folderBookmark = renewedBookmark
				}
				persist()
			}
			return copy.fileURL
		}

		func beginPreview(_ itemID: UUID) -> Bool {
			guard let item = items.first(where: { $0.id == itemID && $0.status == .completed }) else { return false }
			let fileURL = item.fileURL.standardizedFileURL
			if var previewScope = previewScopes[fileURL] {
				previewScope.count += 1
				previewScopes[fileURL] = previewScope
				return true
			}
			guard let bookmark = item.fileAccessBookmark ?? item.folderBookmark else {
				return item.destinationIsFileScoped != true
			}
			var stale = false
			guard let folder = try? URL(
				resolvingBookmarkData: bookmark,
				options: [.withSecurityScope, .withoutUI],
				relativeTo: nil,
				bookmarkDataIsStale: &stale
			), folder.startAccessingSecurityScopedResource() else { return false }
			previewScopes[fileURL] = (folder, 1)
			if stale,
			   let renewed = try? folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
			   let index = items.firstIndex(where: { $0.id == itemID })
			{
				if item.fileAccessBookmark != nil {
					items[index].fileAccessBookmark = renewed
				} else {
					items[index].folderBookmark = renewed
				}
				persist()
			}
			return true
		}

		func endPreview(at fileURL: URL) {
			let key = fileURL.standardizedFileURL
			guard var previewScope = previewScopes[key] else { return }
			guard previewScope.count > 1 else {
				previewScopes.removeValue(forKey: key)
				previewScope.directory.stopAccessingSecurityScopedResource()
				return
			}
			previewScope.count -= 1
			previewScopes[key] = previewScope
		}

		func open(_ itemID: UUID) {
			guard let item = items.first(where: { $0.id == itemID && $0.status == .completed }) else { return }
			let fileURL = item.fileURL
			let riskyExtensions: Set = [
				"app", "bin", "com", "command", "dmg", "exe", "jar", "kext",
				"mobileconfig", "msi", "pkg", "plugin", "ps1", "scpt", "sh", "vbs", "workflow",
			]
			guard riskyExtensions.contains(fileURL.pathExtension.lowercased()) else {
				guard let didOpen = withFolderAccess(for: item, perform: {
					NSWorkspace.shared.open(fileURL)
				}), didOpen else {
					showFileAccessToast()
					return
				}
				return
			}
			Task { @MainActor [weak self] in
				guard let self else { return }
				let response = await BrowserWebsiteUI.present(
					BrowserWebsiteUI.alert(
						title: "Open a downloaded file?",
						message: "This file can install software or run code. Open it only if you trust its source.",
						confirm: "Open Anyway"
					),
					in: NSApp.keyWindow
				) { [weak self] in
					self?.items.contains(where: { $0.id == itemID && $0.status == .completed && $0.fileURL == fileURL }) == true
				}
				guard response == .alertFirstButtonReturn,
				      let current = items.first(where: { $0.id == itemID && $0.status == .completed && $0.fileURL == fileURL })
				else { return }
				guard let didOpen = withFolderAccess(for: current, perform: {
					NSWorkspace.shared.open(fileURL)
				}), didOpen else {
					showFileAccessToast()
					return
				}
			}
		}

		func revealInFolder(_ itemID: UUID) {
			guard let item = items.first(where: { $0.id == itemID }) else { return }
			guard withFolderAccess(for: item, perform: {
				NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
			}) != nil else {
				showFileAccessToast()
				return
			}
		}
	#endif

	private func showFileAccessToast() {
		showToast(symbol: "exclamationmark.triangle", message: "Astra needs renewed access to this saved file.")
	}

	private func maybeAccelerate(
		_ download: WKDownload,
		response: URLResponse,
		originalRequest: URLRequest?
	) async {
		guard privateDataStore == nil else { return }
		let key = ObjectIdentifier(download)
		guard let itemID = itemIDs[key],
		      !accelerationAbandoned.contains(itemID),
		      items.contains(where: { $0.id == itemID }),
		      let request = originalRequest ?? download.originalRequest,
		      (request.httpMethod ?? "GET").uppercased() == "GET",
		      !BrowserDownload.requestHasBody(request),
		      !BrowserDownload.requestHasSensitiveCredentials(request),
		      let url = response.url,
		      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
		      let http = response as? HTTPURLResponse,
		      http.statusCode == 200
		else {
			BrowserLog.debug(.downloads, "download.acceleration.ineligible", metadata: [
				"request": BrowserLog.request(originalRequest ?? download.originalRequest),
				"response_url": BrowserLog.url(response.url),
				"status": String((response as? HTTPURLResponse)?.statusCode ?? -1),
				"has_webview": String(download.webView != nil),
			])
			return
		}

		accelerationPending.insert(itemID)
		defer { accelerationPending.remove(itemID) }

		guard let probe = await probeRangeSupport(
			url: url,
			originalRequest: request,
			initialValidator: strongValidator(from: http)
		) else {
			BrowserLog.debug(.downloads, "download.acceleration.range-unsupported", metadata: [
				"item": BrowserLog.id(itemID),
				"url": BrowserLog.url(url),
			])
			return
		}
		let total = probe.total
		let plannedSegments = BrowserDownloadSegment.plan(total: total)
		guard !plannedSegments.isEmpty else {
			BrowserLog.debug(.downloads, "download.acceleration.too-small", metadata: [
				"item": BrowserLog.id(itemID),
				"total_bytes": String(total),
			])
			return
		}
		let initialValidator = strongValidator(from: http)
		let validator = probe.validator ?? (probe.url == url ? initialValidator : nil)

		guard downloads[key] != nil,
		      let currentIndex = items.firstIndex(where: { $0.id == itemID }),
		      items[currentIndex].status == .downloading
		else { return }

		BrowserLog.info(.downloads, "download.acceleration.enabled", metadata: [
			"item": BrowserLog.id(itemID),
			"segments": String(plannedSegments.count),
			"total_bytes": String(total),
			"validator": validator == nil ? "none" : "present",
			"url": BrowserLog.url(probe.url),
		])
		items[currentIndex].segments = plannedSegments
		items[currentIndex].rangeValidator = validator
		items[currentIndex].totalBytes = total
		items[currentIndex].throughput = nil
		items[currentIndex].estimatedTimeRemaining = nil
		items[currentIndex].requestURL = credentialFreeURL(probe.url)
		persist()
		finish(download)
		_ = await download.cancel()
		guard !isClosing,
		      !deletingItems.contains(itemID),
		      let resumedIndex = items.firstIndex(where: {
		      	$0.id == itemID && $0.status == .downloading && $0.segments != nil
		      })
		else { return }
		try? FileManager.default.removeItem(at: items[resumedIndex].fileURL)
		guard FileManager.default.createFile(atPath: items[resumedIndex].fileURL.path, contents: nil) else {
			segmentFailed(itemID)
			return
		}
		persist()
		segmented.start(items[resumedIndex], originalRequest: request)
	}

	private func probeRangeSupport(
		url: URL,
		originalRequest: URLRequest,
		initialValidator: String?
	) async -> (url: URL, total: Int64, validator: String?)? {
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		for (field, value) in SegmentedDownloadEngine.safeReplayHeaders(originalRequest) {
			request.setValue(value, forHTTPHeaderField: field)
		}
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.timeoutInterval = 8
		request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
		request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.urlCredentialStorage = nil
		let session = URLSession(configuration: configuration)
		defer { session.invalidateAndCancel() }

		do {
			let (bytes, response) = try await session.bytes(for: request)
			defer { bytes.task.cancel() }
			guard let http = response as? HTTPURLResponse,
			      http.statusCode == 206,
			      let finalURL = http.url,
			      ["http", "https"].contains(finalURL.scheme?.lowercased() ?? ""),
			      [nil, "identity"].contains(http.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()),
			      let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
			      let total = Self.totalLength(fromSingleByteContentRange: contentRange)
			else { return nil }
			var iterator = bytes.makeAsyncIterator()
			guard try await iterator.next() != nil else { return nil }

			let probeValidator = strongValidator(from: http)
			if let initialValidator, let probeValidator, initialValidator != probeValidator {
				BrowserLog.debug(.downloads, "download.acceleration.validator-mismatch", metadata: [
					"url": BrowserLog.url(finalURL),
				])
				return nil
			}
			return (finalURL, total, probeValidator)
		} catch {
			BrowserLog.debug(.downloads, "download.acceleration.probe-failed", metadata: [
				"url": BrowserLog.url(url),
				"error": BrowserLog.errorDescription(error),
			])
			return nil
		}
	}

	private static func totalLength(fromSingleByteContentRange value: String) -> Int64? {
		let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
		guard parts.count == 2 else { return nil }
		let range = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
		let total = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
		guard range.caseInsensitiveCompare("bytes 0-0") == .orderedSame,
		      let length = Int64(total),
		      length > 1
		else { return nil }
		return length
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
		guard !isClosing,
		      let itemIndex = items.firstIndex(where: { $0.id == itemID }),
		      items[itemIndex].status == .downloading,
		      items[itemIndex].segments?.indices.contains(index) == true,
		      let total = items[itemIndex].totalBytes,
		      total > 0
		else { return }
		let segment = items[itemIndex].segments?[index]
		let segmentSize = segment.map { $0.end - $0.start + 1 } ?? 0
		let received = min(max(received, 0), segmentSize)
		var item = items[itemIndex]
		item.segments?[index].received = received
		let downloaded = item.segments?.reduce(Int64(0)) { sum, segment in
			sum + (segment.completed ? segment.end - segment.start + 1 : segment.received)
		} ?? 0
		let fraction = min(Double(downloaded) / Double(total), 1)
		guard shouldForwardProgress(itemID, fraction: fraction) else {
			// Preserve segment receipts between visible progress updates.
			items[itemIndex] = item
			return
		}
		item.progress = fraction
		item.receivedBytes = downloaded
		updateRate(for: &item, received: downloaded)
		items[itemIndex] = item
		updateDockProgress()
		if Date.now.timeIntervalSince(lastPersistedAt) > 1 {
			persist()
		}
	}

	func completeSegment(_ itemID: UUID, index: Int, partURL: URL, response: HTTPURLResponse?) {
		guard !isClosing,
		      let itemIndex = items.firstIndex(where: { $0.id == itemID }),
		      items[itemIndex].status == .downloading,
		      let segments = items[itemIndex].segments,
		      segments.indices.contains(index),
		      let total = items[itemIndex].totalBytes,
		      let response,
		      response.statusCode == 206
		else {
			BrowserLog.error(.downloads, "download.segment-response-rejected", metadata: [
				"item": BrowserLog.id(itemID),
				"segment": String(index),
				"status": String(response?.statusCode ?? -1),
				"content_range": response?.value(forHTTPHeaderField: "Content-Range") == nil ? "missing" : "present",
			])
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
		let actualRange = response.value(forHTTPHeaderField: "Content-Range")
		let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
		let actualSize = try? partURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
		guard actualRange == expectedRange,
		      [nil, "identity"].contains(encoding),
		      responseValidator.map({ $0 == validator }) ?? true,
		      actualSize == Int(segment.end - segment.start + 1)
		else {
			BrowserLog.error(.downloads, "download.segment-validation-failed", metadata: [
				"item": BrowserLog.id(itemID),
				"segment": String(index),
				"range_matches": String(actualRange == expectedRange),
				"encoding": encoding ?? "identity",
				"validator_matches": String(responseValidator.map { $0 == validator } ?? true),
				"size_matches": String(actualSize == Int(segment.end - segment.start + 1)),
			])
			try? FileManager.default.removeItem(at: partURL)
			segmentFailed(itemID)
			return
		}
		let sourceURL = partURL
		let destinationURL = items[itemIndex].fileURL
		let operationURL = destinationURL
		let startOffset = segment.start
		let partSize = segment.end - segment.start + 1
		// 1 MiB-chunk file copy off-main; state updates below on main.
		Task.detached(priority: .utility) {
			do {
				let source = try FileHandle(forReadingFrom: sourceURL)
				let destination = try FileHandle(forWritingTo: destinationURL)
				try destination.seek(toOffset: UInt64(startOffset))
				while let data = try source.read(upToCount: 1024 * 1024), !data.isEmpty {
					try destination.write(contentsOf: data)
				}
				try source.close()
				try destination.close()
				try FileManager.default.removeItem(at: sourceURL)
				await MainActor.run { [weak self] in
					self?.finishSegment(itemID, index: index, partSize: partSize, fileURL: operationURL)
				}
			} catch {
				await MainActor.run { [weak self] in
					self?.segmentFailed(itemID, fileURL: operationURL)
				}
			}
		}
	}

	private func finishSegment(_ itemID: UUID, index: Int, partSize: Int64, fileURL: URL) {
		guard !isClosing,
		      let itemIndex = items.firstIndex(where: { $0.id == itemID }),
		      items[itemIndex].status == .downloading,
		      items[itemIndex].fileURL == fileURL,
		      items[itemIndex].segments?.indices.contains(index) == true,
		      let total = items[itemIndex].totalBytes
		else { return }
		items[itemIndex].segments?[index].completed = true
		items[itemIndex].segments?[index].received = partSize
		updateSegmentProgress(itemID, index: index, received: partSize)
		persist()
		guard items[itemIndex].segments?.allSatisfy(\.completed) == true else { return }
		beginFinalization(itemID, temporaryURL: fileURL)
	}

	func segmentFailed(_ itemID: UUID, fileURL: URL? = nil) {
		BrowserLog.error(.downloads, "download.segment-failed", metadata: ["item": BrowserLog.id(itemID), "file": BrowserLog.path(fileURL)])
		guard !isClosing,
		      let index = items.firstIndex(where: { $0.id == itemID }),
		      items[index].status == .downloading,
		      fileURL == nil || items[index].fileURL == fileURL,
		      let segments = items[index].segments
		else { return }
		segmented.cancel(itemID)
		accelerationAbandoned.insert(itemID)
		let failedFileURL = items[index].fileURL
		Task { @MainActor [weak self] in
			guard let self else { return }
			await segmented.removeParts(itemID, count: segments.count)
			await BrowserDownloadFileWorker.shared.removeFiles([failedFileURL])
		}
		items[index].segments = nil
		releaseScope(for: itemID)
		items[index].rangeValidator = nil
		items[index].totalBytes = nil
		items[index].receivedBytes = 0
		items[index].throughput = nil
		items[index].estimatedTimeRemaining = nil
		items[index].progress = 0
		guard let url = items[index].requestURL else {
			markFailed(at: index)
			items[index].errorMessage = "The download could not be restarted."
			persist()
			return
		}
		let fallbackRequest = segmented.fallbackRequest(for: items[index]) ?? URLRequest(url: url)
		persist()
		if resumeWebView == nil {
			let configuration = WKWebViewConfiguration()
			configuration.websiteDataStore = privateDataStore ?? .default()
			resumeWebView = WKWebView(frame: .zero, configuration: configuration)
		}
		resumeWebView?.startDownload(using: fallbackRequest) { [weak self] download in
			self?.attach(download, to: itemID)
		}
	}

	private static var defaultDownloadDirectory: URL {
		#if os(macOS)
			URL.downloadsDirectory
		#else
			URL.documentsDirectory
		#endif
	}

	#if os(macOS)
		func chooseDownloadFolder(in window: NSWindow?) {
			guard let window else { return }
			let panel = NSOpenPanel()
			panel.canChooseFiles = false
			panel.canChooseDirectories = true
			panel.allowsMultipleSelection = false
			panel.prompt = "Choose Downloads Folder"
			panel.beginSheetModal(for: window) { response in
				guard response == .OK, let url = panel.url else { return }
				defer { url.stopAccessingSecurityScopedResource() }
				do {
					let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
					Defaults[.downloadsFolderBookmark] = bookmark.base64EncodedString()
					self.selectedDownloadFolderName = url.lastPathComponent
				} catch {
					self.showToast(symbol: "exclamationmark.triangle", message: "Could not save downloads folder: \(error.localizedDescription)")
				}
			}
		}
	#endif

	private func preferredDownloadDirectory() -> URL? {
		#if os(macOS)
			guard let data = Data(base64Encoded: Defaults[.downloadsFolderBookmark]), !data.isEmpty else { return nil }
			return resolveDownloadFolderBookmark(data)
		#else
			return nil
		#endif
	}

	private func resolveDownloadFolderBookmark(_ data: Data, itemID: UUID? = nil) -> URL? {
		#if os(macOS)
			var stale = false
			guard let url = try? URL(
				resolvingBookmarkData: data,
				options: [.withSecurityScope, .withoutUI],
				relativeTo: nil,
				bookmarkDataIsStale: &stale
			) else { return nil }
			if stale, let renewed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
				if let itemID, let index = items.firstIndex(where: { $0.id == itemID }) {
					items[index].folderBookmark = renewed
					persist()
				} else {
					Defaults[.downloadsFolderBookmark] = renewed.base64EncodedString()
				}
			}
			return url
		#else
			return nil
		#endif
	}

	private func selectedFinalDestination(
		fileName: String,
		window: AnyObject?,
		itemID: UUID,
		downloadID: ObjectIdentifier
	) async -> URL? {
		#if os(macOS)
			guard !isClosing,
			      let savedIndex = items.firstIndex(where: { $0.id == itemID && $0.status == .downloading })
			else { return nil }
			let presentationWindow = window as? NSWindow
			let savedItem = items[savedIndex]
			let savedDestination = savedItem.destinationURL
			let shouldAskForFile = savedItem.destinationIsFileScoped == true
				|| (Defaults[.downloadsAskWhereToSave] && savedDestination == nil)

			if shouldAskForFile {
				guard let presentationWindow else { return nil }
				let panel = NSSavePanel()
				panel.directoryURL = savedDestination?.deletingLastPathComponent() ?? preferredDownloadDirectory()
				panel.nameFieldStringValue = savedDestination?.lastPathComponent ?? fileName
				panel.canCreateDirectories = true
				panel.prompt = "Save Download"
				let response = await withCheckedContinuation { continuation in
					panel.beginSheetModal(for: presentationWindow) { continuation.resume(returning: $0) }
				}
				guard response == .OK, let url = panel.url else { return nil }
				guard !isClosing,
				      downloads[downloadID] != nil,
				      let index = items.firstIndex(where: { $0.id == itemID && $0.status == .downloading })
				else {
					url.stopAccessingSecurityScopedResource()
					return nil
				}
				guard BrowserDownload.safeFilename(url.lastPathComponent) == url.lastPathComponent else {
					url.stopAccessingSecurityScopedResource()
					return nil
				}
				guard !FileManager.default.fileExists(atPath: url.path) else {
					url.stopAccessingSecurityScopedResource()
					showToast(symbol: "exclamationmark.triangle", message: "That file already exists. Choose a new name.")
					return nil
				}
				guard !finalDestinations.values.contains(url.standardizedFileURL) else {
					url.stopAccessingSecurityScopedResource()
					showToast(symbol: "exclamationmark.triangle", message: "Another download is using that destination. Choose a new name.")
					return nil
				}
				items[index].destinationIsFileScoped = true
				// Preserve authority at selection time. Otherwise a crash
				// between WebKit transfer completion and final file publication
				// leaves a resumable staging file but no way to reopen its
				// chosen security-scoped destination on the next launch.
				items[index].fileAccessBookmark = try? url.bookmarkData(
					options: [.withSecurityScope],
					includingResourceValuesForKeys: nil,
					relativeTo: nil
				)
				items[index].folderBookmark = nil
				scopedDirectories[itemID] = url
				return url
			}

			if let folderBookmark = savedItem.folderBookmark {
				if let folder = resolveDownloadFolderBookmark(folderBookmark, itemID: itemID) {
					return beginFolderScopedDownload(
						fileName: fileName,
						folder: folder,
						savedDestination: savedDestination,
						itemID: itemID
					)
				}
				guard let presentationWindow else { return nil }
				return await chooseDownloadFolder(
					in: presentationWindow,
					fileName: fileName,
					savedDestination: savedDestination,
					itemID: itemID,
					downloadID: downloadID
				)
			}

			let defaultFolder = Self.defaultDownloadDirectory
			if let previousFolder = savedDestination?.deletingLastPathComponent() {
				if previousFolder.standardizedFileURL == defaultFolder.standardizedFileURL {
					return beginFolderScopedDownload(
						fileName: fileName,
						folder: defaultFolder,
						savedDestination: savedDestination,
						itemID: itemID
					)
				}
				guard let presentationWindow else { return nil }
				return await chooseDownloadFolder(
					in: presentationWindow,
					fileName: fileName,
					savedDestination: savedDestination,
					itemID: itemID,
					downloadID: downloadID
				)
			}
			if let preferredFolder = preferredDownloadDirectory() {
				return beginFolderScopedDownload(
					fileName: fileName,
					folder: preferredFolder,
					savedDestination: nil,
					itemID: itemID
				)
			}
			if !Defaults[.downloadsFolderBookmark].isEmpty {
				guard let presentationWindow else { return nil }
				return await chooseDownloadFolder(
					in: presentationWindow,
					fileName: fileName,
					savedDestination: nil,
					itemID: itemID,
					downloadID: downloadID
				)
			}
			if let index = items.firstIndex(where: { $0.id == itemID }) {
				items[index].destinationIsFileScoped = false
				items[index].folderBookmark = nil
				items[index].fileAccessBookmark = nil
			}
			return preferredDestination(fileName: fileName, in: defaultFolder, itemID: itemID, saved: nil)
		#else
			return uniqueDestination(fileName: fileName, in: Self.defaultDownloadDirectory)
		#endif
	}

	#if os(macOS)
		private func chooseDownloadFolder(
			in window: NSWindow,
			fileName: String,
			savedDestination: URL?,
			itemID: UUID,
			downloadID: ObjectIdentifier
		) async -> URL? {
			let panel = NSOpenPanel()
			panel.canChooseFiles = false
			panel.canChooseDirectories = true
			panel.allowsMultipleSelection = false
			panel.directoryURL = savedDestination?.deletingLastPathComponent()
			panel.prompt = "Choose Download Folder"
			let response = await withCheckedContinuation { continuation in
				panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
			}
			guard response == .OK, let folder = panel.url else { return nil }
			guard !isClosing,
			      downloads[downloadID] != nil,
			      let index = items.firstIndex(where: { $0.id == itemID && $0.status == .downloading })
			else {
				folder.stopAccessingSecurityScopedResource()
				return nil
			}
			guard let bookmark = try? folder.bookmarkData(
				options: [.withSecurityScope],
				includingResourceValuesForKeys: nil,
				relativeTo: nil
			) else {
				folder.stopAccessingSecurityScopedResource()
				return nil
			}
			items[index].folderBookmark = bookmark
			items[index].destinationIsFileScoped = false
			items[index].fileAccessBookmark = nil
			scopedDirectories[itemID] = folder
			return preferredDestination(fileName: fileName, in: folder, itemID: itemID, saved: savedDestination)
		}

		private func beginFolderScopedDownload(
			fileName: String,
			folder: URL,
			savedDestination: URL?,
			itemID: UUID
		) -> URL? {
			let selectedBookmark = items.first(where: { $0.id == itemID })?.folderBookmark
			let usesDownloadsCapability = folder.standardizedFileURL == Self.defaultDownloadDirectory.standardizedFileURL
				&& selectedBookmark == nil
			if !usesDownloadsCapability {
				guard folder.startAccessingSecurityScopedResource() else { return nil }
				scopedDirectories[itemID] = folder
			}
			if let index = items.firstIndex(where: { $0.id == itemID }) {
				items[index].destinationIsFileScoped = false
				items[index].fileAccessBookmark = nil
				if items[index].folderBookmark == nil,
				   let bookmark = Data(base64Encoded: Defaults[.downloadsFolderBookmark]),
				   !bookmark.isEmpty,
				   preferredDownloadDirectory()?.standardizedFileURL == folder.standardizedFileURL
				{
					items[index].folderBookmark = bookmark
				}
			}
			return preferredDestination(fileName: fileName, in: folder, itemID: itemID, saved: savedDestination)
		}

		private func preferredDestination(fileName: String, in folder: URL, itemID: UUID, saved: URL?) -> URL {
			let reservations = Set(finalDestinations
				.filter { $0.key != itemID }
				.values
				.map(\.standardizedFileURL))
			if let saved,
			   saved.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
			   BrowserDownload.safeFilename(saved.lastPathComponent) == saved.lastPathComponent,
			   !FileManager.default.fileExists(atPath: saved.path),
			   !reservations.contains(saved.standardizedFileURL)
			{
				return saved
			}
			return BrowserDownload.collisionFreeURL(fileName: fileName, in: folder, reserved: reservations)
		}
	#endif

	private func releaseScope(for itemID: UUID) {
		if let directory = scopedDirectories.removeValue(forKey: itemID) {
			directory.stopAccessingSecurityScopedResource()
		}
	}

	private func withFolderAccess<T>(for item: BrowserDownload, perform: () throws -> T) rethrows -> T? {
		#if os(macOS)
			if scopedDirectories[item.id] != nil {
				return try perform()
			}
			if item.destinationIsFileScoped == true, item.fileAccessBookmark == nil {
				return nil
			}
			let bookmark = item.fileAccessBookmark ?? item.folderBookmark
			guard let bookmark else { return try perform() }
			var stale = false
			guard let folder = try? URL(
				resolvingBookmarkData: bookmark,
				options: [.withSecurityScope, .withoutUI],
				relativeTo: nil,
				bookmarkDataIsStale: &stale
			), folder.startAccessingSecurityScopedResource()
			else { return nil }
			defer { folder.stopAccessingSecurityScopedResource() }
			if stale,
			   let renewed = try? folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
			   let index = items.firstIndex(where: { $0.id == item.id })
			{
				if item.fileAccessBookmark != nil {
					items[index].fileAccessBookmark = renewed
				} else if item.folderBookmark != nil {
					items[index].folderBookmark = renewed
				} else {
					Defaults[.downloadsFolderBookmark] = renewed.base64EncodedString()
				}
				persist()
			}
			return try perform()
		#else
			return try perform()
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

	private func credentialFreeURL(_ url: URL?) -> URL? {
		guard let url,
		      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else { return nil }
		components.user = nil
		components.password = nil
		return components.url
	}

	private func updateRate(for item: inout BrowserDownload, received: Int64) {
		let itemID = item.id
		let now = Date.now
		var samples = rateSamples[itemID] ?? []
		let previousSampleTime = samples.last?.at
		if let last = samples.last, received < last.bytes {
			samples.removeAll()
			item.throughput = nil
			item.estimatedTimeRemaining = nil
		}
		samples.append((received, now))
		let cutoff = now.addingTimeInterval(-20)
		while samples.count > 2, samples[1].at <= cutoff {
			samples.removeFirst()
		}
		rateSamples[itemID] = samples

		guard let observedRate = BrowserDownload.averageThroughput(samples: samples),
		      observedRate.isFinite,
		      observedRate > 0
		else { return }

		let elapsed = max(previousSampleTime.map { now.timeIntervalSince($0) } ?? 0, 0.05)
		let sampleAge = now.timeIntervalSince(samples.first?.at ?? now)
		let smoothedRate = BrowserDownload.smoothedThroughput(
			previous: item.throughput.map(Double.init),
			observed: observedRate,
			elapsed: elapsed
		)
		item.throughput = smoothedRate < Double(Int.max) ? Int(smoothedRate.rounded()) : nil

		guard sampleAge >= 2,
		      samples.count >= 3,
		      let total = item.totalBytes,
		      total > received,
		      smoothedRate > 0
		else {
			item.estimatedTimeRemaining = nil
			return
		}

		let observedRemaining = Double(total - received) / smoothedRate
		item.estimatedTimeRemaining = BrowserDownload.smoothedTimeRemaining(
			previous: item.estimatedTimeRemaining,
			observed: observedRemaining,
			elapsed: elapsed
		)
	}

	private func updateProgress(
		_ itemID: UUID,
		downloadID: ObjectIdentifier,
		fraction: Double,
		received: Int64,
		total: Int64,
		throughput: Int?,
		estimatedTimeRemaining _: TimeInterval?
	) {
		guard let index = items.firstIndex(where: { $0.id == itemID }),
		      items[index].status == .downloading,
		      itemIDs[downloadID] == itemID,
		      downloads[downloadID] != nil
		else { return }
		let clamped = min(max(fraction, 0), 1)
		guard shouldForwardProgress(itemID, fraction: clamped) else { return }
		// Publish one observable array mutation instead of one for each
		// progress, byte count, rate and ETA field.
		var item = items[index]
		item.progress = clamped
		item.receivedBytes = max(0, received)
		item.totalBytes = total > 0 ? total : item.totalBytes
		updateRate(for: &item, received: received)
		if rateSamples[itemID]?.count == 1 {
			item.throughput = throughput.flatMap { $0 > 0 ? $0 : nil }
			item.estimatedTimeRemaining = nil
		}
		items[index] = item
		updateDockProgress()
		if Date.now.timeIntervalSince(lastPersistedAt) > 1 {
			persist()
		}
	}

	private func showToast(symbol: String, message: String) {
		toastManager.show(symbol: symbol, message: message)
	}

	private func persist() {
		persistSoon()
	}

	/// Encode + atomic write off-main; progress ticks arrive far more often
	/// than durability requires. Quit path uses flushDownloads() instead.
	private func persistSoon() {
		BrowserLog.trace(.downloads, "downloads.persist-schedule", metadata: ["items": String(items.count)])
		guard privateDataStore == nil,
		      downloadCacheReadCompleted,
		      !downloadCacheIsUnreadable,
		      !isClosing
		else { return }
		lastPersistedAt = .now
		let previousWrite = downloadPersistTask
		previousWrite?.cancel()
		let snapshot = items
		let url = storeURL
		downloadPersistTask = Task.detached(priority: .utility) {
			await previousWrite?.value
			try? await Task.sleep(for: .milliseconds(500))
			guard !Task.isCancelled else { return }
			do {
				let data = try JSONEncoder().encode(snapshot)
				try data.write(to: url, options: .atomic)
			} catch {
				BrowserLog.error(.downloads, "downloads.persist-failed", metadata: ["error": BrowserLog.errorDescription(error), "store": BrowserLog.path(url)])
				let message = error.localizedDescription
				await MainActor.run {
					self.showToast(symbol: "exclamationmark.triangle", message: "Could not save downloads: \(message)")
				}
			}
		}
	}

	/// Synchronous write for app termination, where background work may not finish.
	private func flushDownloads() {
		guard privateDataStore == nil, downloadCacheReadCompleted, !downloadCacheIsUnreadable else { return }
		downloadPersistTask?.cancel()
		downloadPersistTask = nil
		do {
			let data = try JSONEncoder().encode(items)
			try data.write(to: storeURL, options: .atomic)
			lastPersistedAt = .now
		} catch {
			showToast(symbol: "exclamationmark.triangle", message: "Could not save downloads: \(error.localizedDescription)")
		}
	}

	private func uniqueDestination(fileName: String, in directory: URL) -> URL {
		let safeName = BrowserDownload.safeFilename(fileName)
		let reserved = Set(destinations.values.map(\.standardizedFileURL)
			+ finalDestinations.values.map(\.standardizedFileURL))
		return BrowserDownload.collisionFreeURL(fileName: safeName, in: directory, reserved: reserved)
	}

	private func collisionSafeDestination(_ proposed: URL, excludingTemporary: URL, itemID: UUID) -> URL {
		let reservations = destinations.values
			.filter { $0 != excludingTemporary }
			.map(\.standardizedFileURL)
			+ finalDestinations.filter { $0.key != itemID }.values.map(\.standardizedFileURL)
		return BrowserDownload.collisionFreeURL(
			fileName: proposed.lastPathComponent,
			in: proposed.deletingLastPathComponent(),
			reserved: Set(reservations),
			excluding: excludingTemporary
		)
	}

	private func renameWithAppleIntelligence(_ itemID: UUID, fileURL: URL) async {
		guard !Task.isCancelled, !isClosing, privateDataStore == nil,
		      Defaults[.aiFeaturesEnabled],
		      Defaults[.renameDownloadsWithAppleIntelligence],
		      let index = items.firstIndex(where: {
		      	$0.id == itemID && $0.status == .completed && $0.fileURL == fileURL && $0.destinationIsFileScoped != true
		      })
		else { return }
		defer { aiSuggestedNames[itemID] = nil }
		let item = items[index]
		let original = URL(fileURLWithPath: item.originalName).deletingPathExtension().lastPathComponent
		guard let stem = await humanReadableStem(
			original: original,
			source: item.sourceURL?.host,
			fileType: item.fileURL.pathExtension,
			onSnapshot: { [weak self] snapshot in
				guard !Task.isCancelled, let self, self.items.contains(where: { $0.id == itemID && $0.fileURL == fileURL && $0.status == .completed }) else { return }
				let stem = BrowserDownloadNamingFeature.safeStem(BrowserAIOutput.title(snapshot))
				guard stem != "Download" else { return }
				let ext = fileURL.pathExtension
				self.aiSuggestedNames[itemID] = ext.isEmpty ? stem : "\(stem).\(ext)"
			}
		), !Task.isCancelled, !isClosing, Defaults[.aiFeaturesEnabled],
		let currentIndex = items.firstIndex(where: { $0.id == itemID && $0.status == .completed && $0.fileURL == fileURL })
		else { return }
		let ext = fileURL.pathExtension
		let name = BrowserDownload.safeFilename(ext.isEmpty ? stem : "\(stem).\(ext)")
		guard name != fileURL.lastPathComponent else { return }
		let destination: URL
		do {
			destination = try await BrowserDownloadFileWorker.shared.renameExisting(
				source: fileURL, fileName: name,
				bookmark: items[currentIndex].fileAccessBookmark ?? items[currentIndex].folderBookmark,
				hasExistingAccess: scopedDirectories[itemID] != nil
			)
		} catch {
			BrowserLog.warning(.downloads, "download.ai-rename.failed", metadata: [
				"item": BrowserLog.id(itemID), "error": BrowserLog.errorDescription(error),
			])
			return
		}
		guard let updatedIndex = items.firstIndex(where: {
			$0.id == itemID && $0.status == .completed && $0.fileURL == fileURL
		}) else { return }
		#if os(macOS)
			let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.25)
		#else
			let animation: Animation? = UIAccessibility.isReduceMotionEnabled ? nil : .smooth(duration: 0.25)
		#endif
		withAnimation(animation) {
			items[updatedIndex].fileURL = destination
			items[updatedIndex].renamedByAppleIntelligence = true
		}
		persist()
	}

	private func humanReadableStem(original: String, source: String?, fileType: String?, onSnapshot: @MainActor (String) -> Void) async -> String? {
		guard Defaults[.aiFeaturesEnabled], Defaults[.renameDownloadsWithAppleIntelligence] else { return nil }
		return try? await BrowserAI.shared.performStreaming(
			BrowserDownloadNamingFeature(),
			input: .init(original: original, source: source, fileType: fileType),
			onSnapshot: onSnapshot
		)
	}

	static func safeStem(_ name: String) -> String {
		BrowserDownloadNamingFeature.safeStem(name)
	}
}
