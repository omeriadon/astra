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
			registryURL = rootURL.appendingPathComponent("registry.json", isDirectory: false)
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
			guard fileManager.fileExists(atPath: templateURL.appendingPathComponent("Contents/MacOS").path) else {
				throw RegistryError.templateInvalid
			}
			let id = UUID()
			let appURL = rootURL.appendingPathComponent(BrowserWebsiteAppPolicy.bundleFilename(name: name, id: id), isDirectory: true)
			try fileManager.copyItem(at: templateURL, to: appURL)
			do {
				try configureBundle(at: appURL, id: id, name: name, launchURL: url, icon: icon)
				let now = Date()
				let installation = BrowserWebsiteAppInstallation(
					id: id,
					name: name,
					launchURL: url,
					bundlePath: appURL.path,
					createdAt: now,
					modifiedAt: now
				)
				installations.append(installation)
				try save()
				return installation
			} catch {
				installations.removeAll { $0.id == id }
				try? fileManager.removeItem(at: appURL)
				throw error
			}
		}

		func uninstall(_ id: UUID) throws {
			guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
			let installation = installations[index]
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			if fileManager.fileExists(atPath: installation.bundlePath) {
				_ = try fileManager.trashItem(at: installation.bundleURL, resultingItemURL: nil)
			}
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
			guard let installation = installation(for: id),
			      isOwnedInstallation(installation.bundleURL),
			      fileManager.fileExists(atPath: installation.bundlePath)
			else { throw RegistryError.installationOutsideOwnedDirectory }
			NSWorkspace.shared.openApplication(at: installation.bundleURL, configuration: .init())
		}

		func reveal(_ id: UUID) throws {
			guard let installation = installation(for: id) else { return }
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			NSWorkspace.shared.activateFileViewerSelecting([installation.bundleURL])
		}

		func beginKeepInDockFlow(_ id: UUID) throws {
			try launch(id)
			try reveal(id)
		}

		private func load() {
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

		private func save() throws {
			try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.sortedKeys]
			let data = try encoder.encode(installations.sorted { $0.id.uuidString < $1.id.uuidString })
			guard data.count <= 1_048_576 else { throw CocoaError(.fileWriteOutOfSpace) }
			try data.write(to: registryURL, options: .atomic)
		}

		private func isOwnedInstallation(_ url: URL) -> Bool {
			let rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
			let candidatePath = url.standardizedFileURL.resolvingSymlinksInPath().path
			return candidatePath.hasPrefix(rootPath + "/")
		}

		private func configureBundle(at appURL: URL, id: UUID, name: String, launchURL: URL, icon: NSImage?) throws {
			let entitlements = try signingEntitlements(from: appURL)
			let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
			let plistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
			guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
				throw RegistryError.templateInvalid
			}
			plist["CFBundleIdentifier"] = BrowserWebsiteAppPolicy.bundleIdentifier(for: id)
			plist["CFBundleName"] = name
			plist["CFBundleDisplayName"] = name
			plist["AstraWebsiteAppURL"] = launchURL.absoluteString
			let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
			try data.write(to: plistURL, options: .atomic)
			if let icon {
				NSWorkspace.shared.setIcon(icon, forFile: appURL.path)
			}
			try adHocSign(appURL, entitlements: entitlements)
		}

		private func signingEntitlements(from bundleURL: URL) throws -> Data {
			let process = Process()
			let output = Pipe()
			let error = Pipe()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
			process.arguments = ["-d", "--entitlements", ":-", bundleURL.path]
			process.standardOutput = output
			process.standardError = error
			try process.run()
			process.waitUntilExit()
			let stdout = output.fileHandleForReading.readDataToEndOfFile()
			let stderr = error.fileHandleForReading.readDataToEndOfFile()
			guard process.terminationStatus == 0,
			      let plist = entitlementPlist(in: stdout) ?? entitlementPlist(in: stderr),
			      (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) is [String: Any]
			else {
				throw RegistryError.templateInvalid
			}
			return plist
		}

		private func entitlementPlist(in data: Data) -> Data? {
			guard let text = String(data: data, encoding: .utf8),
			      let start = text.range(of: "<?xml"),
			      let end = text.range(of: "</plist>", options: .backwards)
			else { return nil }
			return String(text[start.lowerBound ..< end.upperBound]).data(using: .utf8)
		}

		private func adHocSign(_ bundleURL: URL, entitlements: Data) throws {
			let entitlementsURL = rootURL.appendingPathComponent("signing-\(UUID().uuidString).plist")
			try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
			try entitlements.write(to: entitlementsURL, options: [.atomic])
			defer { try? FileManager.default.removeItem(at: entitlementsURL) }

			let process = Process()
			let pipe = Pipe()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
			process.arguments = [
				"--force", "--sign", "-", "--entitlements", entitlementsURL.path, bundleURL.path,
			]
			process.standardError = pipe
			try process.run()
			process.waitUntilExit()
			guard process.terminationStatus == 0 else {
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown codesign failure"
				throw RegistryError.signingFailed(String(message.prefix(500)))
			}

			let verify = Process()
			let verifyPipe = Pipe()
			verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
			verify.arguments = ["--verify", "--strict", bundleURL.path]
			verify.standardError = verifyPipe
			try verify.run()
			verify.waitUntilExit()
			guard verify.terminationStatus == 0 else {
				let data = verifyPipe.fileHandleForReading.readDataToEndOfFile()
				let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "codesign verification failed"
				throw RegistryError.signingFailed(String(message.prefix(500)))
			}
		}
	}
#endif
