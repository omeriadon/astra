import CryptoKit
import Foundation
import Observation

/// Installs the full upstream MV2 build, never uBlock Origin Lite or a store package.
@MainActor
@Observable
final class UBlockOriginInstaller {
	static let shared = UBlockOriginInstaller()
	private(set) var status: String?
	private(set) var progress: Double?
	private(set) var error: String?
	private(set) var isInstalling = false
	private(set) var isBusy = false
	private(set) var installedName: String?
	@ObservationIgnored private var task: Task<Void, Never>?
	@ObservationIgnored private var operationID = UUID()

	func start() {
		guard !isBusy else { return }
		isBusy = true
		error = nil
		status = "Checking the latest stable release…"
		progress = nil
		installedName = nil
		let operation = UUID()
		operationID = operation
		task = Task { [self] in
			defer {
				isBusy = false
				isInstalling = false
				progress = nil
				task = nil
			}
			do {
				let manager = BrowserExtensionManager.shared
				await manager.prepareAllContexts()
				try Task.checkCancellation()
				let release = try await UBlockOriginRelease.latest()
				let replacing = manager.uBlockOriginName
				if let replacing, manager.version(for: replacing) != "Unknown",
				   manager.version(for: replacing).compare(release.tag_name, options: .numeric) != .orderedAscending {
					status = "uBlock Origin is up to date (\(manager.version(for: replacing)))."
					return
				}
				status = "Downloading uBlock Origin \(release.tag_name)…"
				let delegate = UBlockOriginDownloadProgress { [weak self] fraction in
					Task { @MainActor in
						guard let self, self.operationID == operation, self.isBusy, !self.isInstalling else { return }
						self.progress = fraction
					}
				}
				let asset = try release.chromiumAsset()
				let (download, response) = try await URLSession.shared.download(from: asset.browser_download_url, delegate: delegate)
				// URLSession's temporary file has no .zip suffix; the normal installer validates it.
				let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
				defer {
					Task.detached(priority: .utility) {
						try? FileManager.default.removeItem(at: download)
						try? FileManager.default.removeItem(at: archive)
					}
				}
				try UBlockOriginRelease.validate(response: response, hosts: ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"])
				status = "Verifying download…"
				progress = nil
				try await Task.detached(priority: .utility) {
					try UBlockOriginRelease.verify(download, asset: asset)
					try FileManager.default.moveItem(at: download, to: archive)
				}.value
				try Task.checkCancellation()
				// Once installation begins, finish the commit or rollback before returning.
				// Cancel is unavailable during this phase.
				isInstalling = true
				status = "Installing uBlock Origin…"
				let installed = try await manager.installUBlockOriginArchive(from: archive, replacing: replacing)
				installedName = installed
				status = manager.isEnabled(installed)
					? "uBlock Origin updated to \(release.tag_name)."
					: "Installed. Review permissions to enable uBlock Origin."
			} catch is CancellationError {
				status = "Download cancelled."
			} catch let failure as URLError where failure.code == .cancelled {
				if Task.isCancelled {
					status = "Download cancelled."
				} else {
					self.error = UBlockOriginRelease.InstallError.invalidDownload.localizedDescription
					status = nil
				}
			} catch {
				self.error = error.localizedDescription
				status = nil
			}
		}
	}

	func cancel() {
		guard !isInstalling else { return }
		task?.cancel()
	}
}

nonisolated struct UBlockOriginRelease: Decodable, Sendable {
	let tag_name: String
	let draft: Bool
	let prerelease: Bool
	let assets: [Asset]

	nonisolated struct Asset: Decodable, Sendable {
		let name: String
		let browser_download_url: URL
		let size: Int
		let digest: String?
	}

	nonisolated enum InstallError: LocalizedError, Sendable {
		case invalidRelease, invalidDownload, checksumMismatch
		var errorDescription: String? {
			switch self {
			case .invalidRelease: "The official stable uBlock Origin release is unavailable. Try again later."
			case .invalidDownload: "The uBlock Origin download was incomplete or invalid. Try again."
			case .checksumMismatch: "The uBlock Origin download failed its SHA-256 check. Try again."
			}
		}
	}

	static func latest() async throws -> Self {
		var request = URLRequest(url: URL(string: "https://api.github.com/repos/gorhill/uBlock/releases/latest")!)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.setValue("Astra", forHTTPHeaderField: "User-Agent")
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.timeoutInterval = 30
		let (data, response) = try await URLSession.shared.data(for: request)
		try validate(response: response, hosts: ["api.github.com"])
		guard data.count <= 2_000_000 else { throw InstallError.invalidRelease }
		let release = try JSONDecoder().decode(Self.self, from: data)
		guard !release.draft, !release.prerelease,
		      release.tag_name.range(of: #"^\d+\.\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil
		else { throw InstallError.invalidRelease }
		return release
	}

	func chromiumAsset() throws -> Asset {
		guard let asset = assets.first(where: { $0.name == "uBlock0_\(tag_name).chromium.zip" }),
		      asset.size > 0, asset.size <= 50_000_000,
		      asset.browser_download_url.scheme == "https",
		      asset.browser_download_url.host == "github.com",
		      asset.browser_download_url.path == "/gorhill/uBlock/releases/download/\(tag_name)/\(asset.name)",
		      let digest = asset.digest,
		      digest.range(of: #"^sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil
		else { throw InstallError.invalidRelease }
		return asset
	}

	static func validate(response: URLResponse, hosts: Set<String>) throws {
		guard let response = response as? HTTPURLResponse,
		      response.statusCode == 200, response.url?.scheme == "https",
		      let host = response.url?.host, hosts.contains(host)
		else { throw InstallError.invalidDownload }
	}

	static func verify(_ url: URL, asset: Asset) throws {
		guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == asset.size else { throw InstallError.invalidDownload }
		let data = try Data(contentsOf: url)
		let digest = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
		guard digest == asset.digest else { throw InstallError.checksumMismatch }
	}
}

private nonisolated final class UBlockOriginDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
	let report: @Sendable (Double?) -> Void
	init(report: @escaping @Sendable (Double?) -> Void) { self.report = report }

	func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		guard totalBytesWritten <= 50_000_000, totalBytesExpectedToWrite <= 50_000_000 else {
			downloadTask.cancel()
			return
		}
		report(totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil)
	}

	func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo _: URL) {}
}
