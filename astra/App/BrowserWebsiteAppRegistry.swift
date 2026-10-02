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
			      !name.unicodeScalars.contains(where: { $0.properties.isControl }),
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

		private(set) var installations: [BrowserWebsiteAppInstallation] = []
		private let rootURL: URL
		private let registryURL: URL
		private let appsURL: URL

		private init() {
			let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
				?? FileManager.default.temporaryDirectory
			let root = support
				.appendingPathComponent(Bundle.main.bundleIdentifier ?? "astra", isDirectory: true)
				.appendingPathComponent("WebsiteApps", isDirectory: true)
			rootURL = root.standardizedFileURL
			registryURL = root.appendingPathComponent("registry.json")
			appsURL = root.appendingPathComponent("Apps", isDirectory: true)
			try? FileManager.default.createDirectory(at: appsURL, withIntermediateDirectories: true)
			installations = Self.loadRegistry(from: registryURL)
		}

		func installation(id: UUID) -> BrowserWebsiteAppInstallation? {
			installations.first { $0.id == id }
		}

		@discardableResult
		func install(name proposedName: String, url proposedURL: URL, icon: NSImage? = nil) throws -> BrowserWebsiteAppInstallation {
			guard let name = BrowserWebsiteAppPolicy.validatedName(proposedName) else { throw RegistryError.invalidName }
			guard let launchURL = BrowserWebsiteAppPolicy.validatedURL(proposedURL) else { throw RegistryError.invalidURL }
			guard let template = Bundle.main.url(forResource: "AstraWebsiteAppTemplate", withExtension: "app") else {
				throw RegistryError.templateMissing
			}
			guard FileManager.default.fileExists(atPath: template.appendingPathComponent("Contents/MacOS").path) else {
				throw RegistryError.templateInvalid
			}
			let signingEntitlements = try signingEntitlements(from: template)

			let id = UUID()
			let destination = appsURL.appendingPathComponent(
				BrowserWebsiteAppPolicy.bundleFilename(name: name, id: id),
				isDirectory: true
			)
			try FileManager.default.copyItem(at: template, to: destination)
			do {
				try writeBundleMetadata(id: id, name: name, launchURL: launchURL, bundleURL: destination)
				if let icon {
					NSWorkspace.shared.setIcon(icon, forFile: destination.path)
				}
				try adHocSign(destination, entitlements: signingEntitlements)
				let now = Date.now
				let installation = BrowserWebsiteAppInstallation(
					id: id,
					name: name,
					launchURL: launchURL,
					bundlePath: destination.path,
					createdAt: now,
					modifiedAt: now
				)
				installations.append(installation)
				try persist()
				return installation
			} catch {
				try? FileManager.default.removeItem(at: destination)
				throw error
			}
		}

		func launch(_ id: UUID) throws {
			guard let installation = installation(id: id), owns(installation.bundleURL),
			      FileManager.default.fileExists(atPath: installation.bundlePath)
			else { throw RegistryError.installationOutsideOwnedDirectory }
			let configuration = NSWorkspace.OpenConfiguration()
			configuration.activates = true
			NSWorkspace.shared.openApplication(at: installation.bundleURL, configuration: configuration)
		}

		func reveal(_ id: UUID) throws {
			guard let installation = installation(id: id), owns(installation.bundleURL) else {
				throw RegistryError.installationOutsideOwnedDirectory
			}
			NSWorkspace.shared.activateFileViewerSelecting([installation.bundleURL])
		}

		/// There is no supported public API for silently pinning another app permanently in the Dock.
		/// Launch it so its Dock icon exists, then reveal the app for the system/user-assisted Keep in Dock flow.
		func beginKeepInDockFlow(_ id: UUID) throws {
			try launch(id)
			try reveal(id)
		}

		func rename(_ id: UUID, to proposedName: String) throws {
			guard let index = installations.firstIndex(where: { $0.id == id }),
			      owns(installations[index].bundleURL)
			else { throw RegistryError.installationOutsideOwnedDirectory }
			guard let name = BrowserWebsiteAppPolicy.validatedName(proposedName) else { throw RegistryError.invalidName }
			let oldURL = installations[index].bundleURL
			let signingEntitlements = try signingEntitlements(from: oldURL)
			let newURL = appsURL.appendingPathComponent(BrowserWebsiteAppPolicy.bundleFilename(name: name, id: id), isDirectory: true)
			if oldURL != newURL {
				try FileManager.default.moveItem(at: oldURL, to: newURL)
				installations[index].bundlePath = newURL.path
			}
			try writeBundleMetadata(id: id, name: name, launchURL: installations[index].launchURL, bundleURL: newURL)
			try adHocSign(newURL, entitlements: signingEntitlements)
			installations[index].name = name
			installations[index].modifiedAt = .now
			try persist()
		}

		func updateIcon(_ id: UUID, icon: NSImage) throws {
			guard let index = installations.firstIndex(where: { $0.id == id }), owns(installations[index].bundleURL) else {
				throw RegistryError.installationOutsideOwnedDirectory
			}
			let bundleURL = installations[index].bundleURL
			let signingEntitlements = try signingEntitlements(from: bundleURL)
			NSWorkspace.shared.setIcon(icon, forFile: installations[index].bundlePath)
			try adHocSign(bundleURL, entitlements: signingEntitlements)
			installations[index].modifiedAt = .now
			try persist()
		}

		func uninstall(_ id: UUID) throws {
			guard let index = installations.firstIndex(where: { $0.id == id }), owns(installations[index].bundleURL) else {
				throw RegistryError.installationOutsideOwnedDirectory
			}
			let bundleURL = installations[index].bundleURL
			if FileManager.default.fileExists(atPath: bundleURL.path) {
				_ = try FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)
			}
			installations.remove(at: index)
			try persist()
		}

		private func writeBundleMetadata(id: UUID, name: String, launchURL: URL, bundleURL: URL) throws {
			let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
			guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
				throw RegistryError.templateInvalid
			}
			plist["CFBundleName"] = name
			plist["CFBundleDisplayName"] = name
			plist["CFBundleIdentifier"] = BrowserWebsiteAppPolicy.bundleIdentifier(for: id)
			plist["AstraWebsiteAppID"] = id.uuidString
			plist["AstraWebsiteAppLaunchURL"] = launchURL.absoluteString
			let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
			try data.write(to: plistURL, options: .atomic)
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

		private func owns(_ url: URL) -> Bool {
			let rootPath = appsURL.standardizedFileURL.path
			let path = url.standardizedFileURL.path
			return path.hasPrefix(rootPath + "/") && path != rootPath
		}

		private func persist() throws {
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.sortedKeys]
			let data = try encoder.encode(installations.sorted { $0.id.uuidString < $1.id.uuidString })
			guard data.count <= 1_048_576 else { throw CocoaError(.fileWriteOutOfSpace) }
			try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
			try data.write(to: registryURL, options: .atomic)
		}

		private static func loadRegistry(from url: URL) -> [BrowserWebsiteAppInstallation] {
			guard let data = try? Data(contentsOf: url), data.count <= 1_048_576,
			      let decoded = try? JSONDecoder().decode([BrowserWebsiteAppInstallation].self, from: data)
			else { return [] }
			return decoded.filter {
				BrowserWebsiteAppPolicy.validatedName($0.name) != nil
					&& BrowserWebsiteAppPolicy.validatedURL($0.launchURL) != nil
			}
		}
	}
#endif
