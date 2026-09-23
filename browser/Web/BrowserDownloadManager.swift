import Defaults
import Foundation
import FoundationModels
import WebKit

#if os(macOS)
	import DockProgress
#endif

@MainActor
final class BrowserDownloadManager: NSObject, WKDownloadDelegate {
	static let shared = BrowserDownloadManager()
	private static let unsafeFilenameCharacters = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)

	private var downloads: [ObjectIdentifier: WKDownload] = [:]
	private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
	private var destinations: [ObjectIdentifier: URL] = [:]

	override private init() {
		super.init()
		#if DEBUG
			assert(Self.safeStem("../unsafe\\name") == "unsafename")
		#endif
	}

	func start(_ download: WKDownload) {
		let id = ObjectIdentifier(download)
		guard downloads[id] == nil else { return }
		downloads[id] = download
		download.delegate = self
		observations[id] = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
			Task { @MainActor in
				self?.updateDockProgress()
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
			let original = URL(fileURLWithPath: suggestedFilename).lastPathComponent
			let originalExtension = String(String.UnicodeScalarView(
				URL(fileURLWithPath: original).pathExtension.unicodeScalars.filter {
					!Self.unsafeFilenameCharacters.contains($0)
				}
			))
			let originalStem = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
			let suggestedStem = await humanReadableStem(
				original: originalStem,
				source: response.url?.host,
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
			#if os(macOS)
				let directory = URL.downloadsDirectory
			#else
				let directory = URL.documentsDirectory
			#endif
			do {
				let writableDirectory: URL
				do {
					try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
					writableDirectory = directory
				} catch {
					writableDirectory = URL.documentsDirectory
					try FileManager.default.createDirectory(at: writableDirectory, withIntermediateDirectories: true)
				}
				let destination = uniqueDestination(fileName: fileName, in: writableDirectory)
				destinations[ObjectIdentifier(download)] = destination
				completionHandler(destination)
			} catch {
				ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Download failed: \(error.localizedDescription)")
				completionHandler(nil)
				finish(download)
			}
		}
	}

	func downloadDidFinish(_ download: WKDownload) {
		if let destination = destinations[ObjectIdentifier(download)] {
			ToastManager.shared.show(symbol: "arrow.down.circle", message: "Downloaded \(destination.lastPathComponent)")
		}
		finish(download)
	}

	func download(_ download: WKDownload, didFailWithError error: any Error, resumeData _: Data?) {
		guard downloads[ObjectIdentifier(download)] != nil else { return }
		ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Download failed: \(error.localizedDescription)")
		finish(download)
	}

	private func finish(_ download: WKDownload) {
		let id = ObjectIdentifier(download)
		observations[id] = nil
		downloads[id] = nil
		destinations[id] = nil
		updateDockProgress()
	}

	private func updateDockProgress() {
		#if os(macOS)
			guard !downloads.isEmpty else {
				DockProgress.progress = 0
				return
			}
			let completed = downloads.values.reduce(0.0) { total, download in
				total + max(0.01, min(download.progress.fractionCompleted, 1))
			}
			DockProgress.progress = completed / Double(downloads.count)
		#endif
	}

	private func uniqueDestination(fileName: String, in directory: URL) -> URL {
		let source = URL(fileURLWithPath: fileName)
		let stem = source.deletingPathExtension().lastPathComponent
		let fileExtension = source.pathExtension
		var destination = directory.appending(path: fileName)
		var number = 2
		while FileManager.default.fileExists(atPath: destination.path) || destinations.values.contains(destination) {
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
