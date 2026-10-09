#if os(macOS)
	import AppKit
	import CoreServices
	import Darwin
	import Foundation
	import ImageIO
	import Observation
	import Security

	nonisolated struct BrowserWebsiteAppInstallation: Codable, Equatable, Identifiable, Sendable {
		let id: UUID
		var name: String
		let launchURL: URL
		var bundlePath: String
		let createdAt: Date
		var modifiedAt: Date

		var bundleURL: URL {
			URL(fileURLWithPath: bundlePath, isDirectory: true)
		}
	}

	nonisolated enum BrowserWebsiteAppPolicy {
		static let maximumNameBytes = 160
		static let maximumURLBytes = 8192

		static func validatedURL(_ url: URL) -> URL? {
			guard url.absoluteString.utf8.count <= maximumURLBytes,
			      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
			      let host = components.host, !host.isEmpty,
			      components.user == nil, components.password == nil,
			      components.port.map({ (1 ... 65535).contains($0) }) ?? true
			else { return nil }
			return components.url
		}

		static func validatedName(_ value: String) -> String? {
			let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty,
			      name != ".", name != "..",
			      name.utf8.count <= maximumNameBytes,
			      !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
			      !name.contains("/"), !name.contains(":"), !name.contains("\\")
			else { return nil }
			return name
		}

		static func bundleIdentifier(for id: UUID) -> String {
			"dev.omeriadon.astra.website.\(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
		}

		static func bundleFilename(name: String, id: UUID) -> String {
			let safe = name.unicodeScalars.map { scalar -> Character in
				if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" || scalar == " " {
					return Character(String(scalar))
				}
				return "-"
			}
			let stem = String(safe).trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
			return "\(stem.isEmpty ? "Website" : String(stem))-\(id.uuidString.prefix(8)).app"
		}
	}

	@MainActor
	@Observable
	final class BrowserWebsiteAppRegistry {
		static let shared = BrowserWebsiteAppRegistry()

		enum RegistryError: LocalizedError {
			case invalidName
			case invalidURL
			case templateMissing
			case templateInvalid
			case installationOutsideOwnedDirectory
			case signingFailed(String)
			case registrationFailed(OSStatus)
			case dockPinningFailed(String)
			case dockPinningUnavailable

			var errorDescription: String? {
				switch self {
					case .invalidName: "The website app name is invalid."
					case .invalidURL: "Only credential-free HTTP or HTTPS pages can become website apps."
					case .templateMissing: "The website-app helper template is not included in this build."
					case .templateInvalid: "The website-app helper template is invalid."
					case .installationOutsideOwnedDirectory: "Astra refused to modify a website app outside its owned installation directory."
					case let .signingFailed(message): "The generated website app could not be locally signed: \(message)"
					case let .registrationFailed(status): "macOS could not register the website app (\(status))."
					case let .dockPinningFailed(message): "The website app could not be pinned: \(message)"
					case .dockPinningUnavailable: "Dock pinning is unavailable on this version of macOS."
				}
			}
		}

		private let fileManager: FileManager
		private let rootURL: URL
		private let resourceBundle: Bundle
		private let registryURL: URL
		private(set) var installations: [BrowserWebsiteAppInstallation] = []
		@ObservationIgnored private var isOperating = false
		@ObservationIgnored private lazy var fileWorker = BrowserWebsiteAppFileWorker(
			rootURL: rootURL,
			templateURL: resourceBundle.url(forResource: "AstraWebsiteAppTemplate", withExtension: "app"),
			hostBundleURL: resourceBundle.bundleURL,
			hostBundleIdentifier: resourceBundle.bundleIdentifier
		)

		init(
			fileManager: FileManager = .default,
			rootDirectory: URL? = nil,
			resourceBundle: Bundle = .main
		) {
			self.fileManager = fileManager
			self.resourceBundle = resourceBundle
			let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
				?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			let rootURL = rootDirectory ?? applicationSupport
				.appendingPathComponent("Astra", isDirectory: true)
				.appendingPathComponent("Website Apps", isDirectory: true)
			self.rootURL = rootURL
			registryURL = rootURL.appendingPathComponent("registry.json", isDirectory: false)
			try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
			load()
		}

		func installation(for id: UUID) -> BrowserWebsiteAppInstallation? {
			installations.first(where: { $0.id == id })
		}

		/// MainActor owns input validation and UI observation only. The file
		/// worker owns the signed-bundle transaction and persisted registry.
		private func serialized<T>(_ action: () async throws -> T) async throws -> T {
			guard !isOperating else { throw BrowserWebsiteAppFileError.operationInProgress }
			isOperating = true
			defer { isOperating = false }
			return try await action()
		}

		func install(name: String, url: URL, icon: NSImage?) async throws -> BrowserWebsiteAppInstallation {
			try await serialized {
				BrowserLog.info(.websiteApps, "website-app.install", metadata: [
					"name": BrowserLog.value(name), "url": BrowserLog.url(url), "has_icon": String(icon != nil),
				])
				guard let name = BrowserWebsiteAppPolicy.validatedName(name) else { throw RegistryError.invalidName }
				guard let url = BrowserWebsiteAppPolicy.validatedURL(url) else { throw RegistryError.invalidURL }
				let id = UUID()
				let now = Date.now
				let appURL = rootURL.appendingPathComponent(
					BrowserWebsiteAppPolicy.bundleFilename(name: name, id: id), isDirectory: true
				)
				let installation = BrowserWebsiteAppInstallation(
					id: id, name: name, launchURL: url, bundlePath: appURL.path,
					createdAt: now, modifiedAt: now
				)
				let next = installations + [installation]
				let iconData = icon?.tiffRepresentation
				try await fileWorker.install(installation, iconData: iconData, nextRegistry: next)
				installations = next
				return installation
			}
		}

		func uninstall(_ id: UUID) async throws {
			try await serialized {
				BrowserLog.notice(.websiteApps, "website-app.uninstall", metadata: ["id": BrowserLog.id(id)])
				guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
				let installation = installations[index]
				let next = installations.filter { $0.id != id }
				try await fileWorker.uninstall(installation, nextRegistry: next)
				installations = next
			}
		}

		func rename(_ id: UUID, to newName: String) async throws {
			try await serialized {
				BrowserLog.info(.websiteApps, "website-app.rename", metadata: [
					"id": BrowserLog.id(id), "name": BrowserLog.value(newName),
				])
				guard let name = BrowserWebsiteAppPolicy.validatedName(newName) else { throw RegistryError.invalidName }
				guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
				var next = installations
				next[index].name = name
				next[index].modifiedAt = .now
				// Preserve the original path so existing Dock entries remain valid.
				try await fileWorker.replace(next[index], iconData: nil, nextRegistry: next)
				installations = next
			}
		}

		func updateIcon(_ id: UUID, icon: NSImage) async throws {
			try await serialized {
				BrowserLog.info(.websiteApps, "website-app.update-icon", metadata: ["id": BrowserLog.id(id)])
				guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
				var next = installations
				next[index].modifiedAt = .now
				guard let iconData = icon.tiffRepresentation else { throw RegistryError.templateInvalid }
				try await fileWorker.replace(next[index], iconData: iconData, nextRegistry: next)
				installations = next
			}
		}

		func launch(_ id: UUID) async throws {
			try await serialized {
				BrowserLog.info(.websiteApps, "website-app.launch", metadata: ["id": BrowserLog.id(id)])
				guard let installation = installation(for: id) else {
					throw RegistryError.installationOutsideOwnedDirectory
				}
				try await openInstalledApp(installation)
			}
		}

		private func openInstalledApp(_ installation: BrowserWebsiteAppInstallation) async throws {
			try await fileWorker.prepareLaunch(installation)
			_ = try await NSWorkspace.shared.openApplication(at: installation.bundleURL, configuration: .init())
		}

		func reveal(_ id: UUID) throws {
			guard let installation = installation(for: id) else { return }
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			NSWorkspace.shared.activateFileViewerSelecting([installation.bundleURL])
		}

		func beginKeepInDockFlow(_ id: UUID) async throws {
			try await serialized {
				guard let installation = installation(for: id) else {
					throw RegistryError.installationOutsideOwnedDirectory
				}
				try await fileWorker.prepareLaunch(installation)
				try await pinToDock(installation)
				try await openInstalledApp(installation)
			}
		}

		private func pinToDock(_ installation: BrowserWebsiteAppInstallation) async throws {
			let helperName = "AstraWebsiteAppInstaller.app"
			let helperURL = resourceBundle.bundleURL.appendingPathComponent("Contents/Resources").appendingPathComponent(helperName)
			guard fileManager.fileExists(atPath: helperURL.path) else { throw RegistryError.dockPinningUnavailable }
			let responseURL = rootURL.appendingPathComponent("dock-result-\(UUID().uuidString).json")
			defer { try? fileManager.removeItem(at: responseURL) }
			let configuration = NSWorkspace.OpenConfiguration()
			configuration.activates = false
			configuration.addsToRecentItems = false
			configuration.createsNewApplicationInstance = true
			configuration.arguments = ["--pin", installation.bundlePath, responseURL.path]
			let helper = try await NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)
			let deadline = ContinuousClock.now.advanced(by: .seconds(15))
			while ContinuousClock.now < deadline {
				if let data = try? Data(contentsOf: responseURL) {
					let message = try JSONDecoder().decode(String.self, from: data)
					guard message.isEmpty else { throw RegistryError.dockPinningFailed(message) }
					return
				}
				if helper.isTerminated {
					throw RegistryError.dockPinningFailed("The Dock installer exited without a result.")
				}
				try await Task.sleep(for: .milliseconds(100))
			}
			throw RegistryError.dockPinningFailed("The Dock installer did not respond.")
		}

		private func load() {
			BrowserLog.debug(.websiteApps, "website-app.registry-load")
			guard let data = try? Data(contentsOf: registryURL),
			      data.count <= 1_048_576,
			      let decoded = try? JSONDecoder().decode([BrowserWebsiteAppInstallation].self, from: data)
			else { return }
			installations = decoded.filter {
				isOwnedInstallation($0.bundleURL)
					&& BrowserWebsiteAppPolicy.validatedName($0.name) != nil
					&& BrowserWebsiteAppPolicy.validatedURL($0.launchURL) != nil
			}
		}

		private func isOwnedInstallation(_ url: URL) -> Bool {
			let rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
			let candidatePath = url.standardizedFileURL.resolvingSymlinksInPath().path
			return candidatePath.hasPrefix(rootPath + "/")
		}
	}
#endif
