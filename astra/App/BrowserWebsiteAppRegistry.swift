#if os(macOS)
	import AppKit
	import Foundation
	import Observation

	struct BrowserWebsiteAppInstallation: Codable, Equatable, Identifiable {
		let id: UUID
		var name: String
		let launchURL: URL
		var bundlePath: String
		let createdAt: Date
		var modifiedAt: Date

		var bundleURL: URL { URL(fileURLWithPath: bundlePath, isDirectory: true) }
	}

	nonisolated enum BrowserWebsiteAppPolicy {
		static let maximumNameBytes = 160
		static let maximumURLBytes = 8_192

		static func validatedURL(_ url: URL) -> URL? {
			guard url.absoluteString.utf8.count <= maximumURLBytes,
			      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
			      let host = components.host, !host.isEmpty,
			      components.user == nil, components.password == nil,
			      components.port.map({ (1 ... 65_535).contains($0) }) ?? true
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

			var errorDescription: String? {
				switch self {
					case .invalidName: "The website app name is invalid."
					case .invalidURL: "Only credential-free HTTP or HTTPS pages can become website apps."
					case .templateMissing: "The website-app helper template is not included in this build."
					case .templateInvalid: "The website-app helper template is invalid."
					case .installationOutsideOwnedDirectory: "Astra refused to modify a website app outside its owned installation directory."
					case let .signingFailed(message): "The generated website app could not be locally signed: \(message)"
				}
			}
		}

		private let fileManager: FileManager
		private let rootURL: URL
		private let registryURL: URL
		private(set) var installations: [BrowserWebsiteAppInstallation] = []

		init(fileManager: FileManager = .default) {
			self.fileManager = fileManager
			let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
				?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			let rootURL = applicationSupport
				.appendingPathComponent("Astra", isDirectory: true)
				.appendingPathComponent("Website Apps", isDirectory: true)
			self.rootURL = rootURL
			self.registryURL = rootURL.appendingPathComponent("registry.json", isDirectory: false)
			try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
			load()
		}

		func installation(for id: UUID) -> BrowserWebsiteAppInstallation? {
			installations.first(where: { $0.id == id })
		}

		func install(name: String, url: URL, icon: NSImage?) throws -> BrowserWebsiteAppInstallation {
			guard let name = BrowserWebsiteAppPolicy.validatedName(name) else { throw RegistryError.invalidName }
			guard let url = BrowserWebsiteAppPolicy.validatedURL(url) else { throw RegistryError.invalidURL }
			guard let templateURL = Bundle.main.url(forResource: "AstraWebsiteAppTemplate", withExtension: "app") else {
				throw RegistryError.templateMissing
			}
			let id = UUID()
			let appURL = rootURL.appendingPathComponent(BrowserWebsiteAppPolicy.bundleFilename(name: name, id: id), isDirectory: true)
			try fileManager.copyItem(at: templateURL, to: appURL)
			try configureBundle(at: appURL, id: id, name: name, launchURL: url, icon: icon)
			let now = Date()
			let installation = BrowserWebsiteAppInstallation(id: id, name: name, launchURL: url, bundlePath: appURL.path, createdAt: now, modifiedAt: now)
			installations.append(installation)
			try save()
			return installation
		}

		func uninstall(_ id: UUID) throws {
			guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
			let installation = installations[index]
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			try fileManager.removeItem(at: installation.bundleURL)
			installations.remove(at: index)
			try save()
		}

		func rename(_ id: UUID, to newName: String) throws {
			guard let name = BrowserWebsiteAppPolicy.validatedName(newName) else { throw RegistryError.invalidName }
			guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
			let old = installations[index]
			guard isOwnedInstallation(old.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			let newURL = rootURL.appendingPathComponent(BrowserWebsiteAppPolicy.bundleFilename(name: name, id: id), isDirectory: true)
			if old.bundleURL != newURL {
				if fileManager.fileExists(atPath: newURL.path) {
					try fileManager.removeItem(at: newURL)
				}
				try fileManager.moveItem(at: old.bundleURL, to: newURL)
			}
			try configureBundle(at: newURL, id: id, name: name, launchURL: old.launchURL, icon: nil)
			installations[index].name = name
			installations[index].bundlePath = newURL.path
			installations[index].modifiedAt = .now
			try save()
		}

		func updateIcon(_ id: UUID, icon: NSImage) throws {
			guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
			let installation = installations[index]
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			try configureBundle(at: installation.bundleURL, id: id, name: installation.name, launchURL: installation.launchURL, icon: icon)
			installations[index].modifiedAt = .now
			try save()
		}

		func launch(_ id: UUID) throws {
			guard let installation = installation(for: id) else { return }
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			NSWorkspace.shared.openApplication(at: installation.bundleURL, configuration: .init())
		}

		func reveal(_ id: UUID) throws {
			guard let installation = installation(for: id) else { return }
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			NSWorkspace.shared.activateFileViewerSelecting([installation.bundleURL])
		}

		func beginKeepInDockFlow(_ id: UUID) throws {
			guard let installation = installation(for: id) else { return }
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			NSWorkspace.shared.openApplication(at: installation.bundleURL, configuration: .init())
		}

		private func load() {
			guard let data = try? Data(contentsOf: registryURL),
			      let decoded = try? JSONDecoder().decode([BrowserWebsiteAppInstallation].self, from: data)
			else { return }
			installations = decoded.filter { isOwnedInstallation($0.bundleURL) }
		}

		private func save() throws {
			try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
			let data = try JSONEncoder().encode(installations)
			try data.write(to: registryURL, options: .atomic)
		}

		private func isOwnedInstallation(_ url: URL) -> Bool {
			let rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
			let candidatePath = url.standardizedFileURL.resolvingSymlinksInPath().path
			return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
		}

		private func configureBundle(at appURL: URL, id: UUID, name: String, launchURL: URL, icon: NSImage?) throws {
			let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
			let plistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
			guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
				throw RegistryError.templateInvalid
			}
			plist["CFBundleIdentifier"] = BrowserWebsiteAppPolicy.bundleIdentifier(for: id)
			plist["CFBundleName"] = name
			plist["CFBundleDisplayName"] = name
			plist["AstraWebsiteAppURL"] = launchURL.absoluteString
			if let icon {
				let iconURL = contentsURL.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent("AppIcon.icns", isDirectory: false)
				try writeICNS(icon, to: iconURL)
				plist["CFBundleIconFile"] = "AppIcon"
			}
			try (plist as NSDictionary).write(to: plistURL)
			try signLocally(appURL)
		}

		private func writeICNS(_ image: NSImage, to url: URL) throws {
			guard let tiff = image.tiffRepresentation,
			      let bitmap = NSBitmapImageRep(data: tiff),
			      let png = bitmap.representation(using: .png, properties: [:])
			else { throw RegistryError.templateInvalid }
			try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try png.write(to: url.deletingPathExtension().appendingPathExtension("png"), options: .atomic)
		}

		private func signLocally(_ appURL: URL) throws {
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
			process.arguments = ["--force", "--deep", "--sign", "-", appURL.path]
			let errorPipe = Pipe()
			process.standardError = errorPipe
			try process.run()
			process.waitUntilExit()
			guard process.terminationStatus == 0 else {
				let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
				let message = String(data: data, encoding: .utf8) ?? "codesign failed"
				throw RegistryError.signingFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
			}
		}
	}
#endif