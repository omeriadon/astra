#if os(macOS)
	import AppKit
	import CoreServices
	import Darwin
	import Foundation
	import ImageIO
	import Observation
	import Security

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

		func install(name: String, url: URL, icon: NSImage?) throws -> BrowserWebsiteAppInstallation {
			BrowserLog.info(.websiteApps, "website-app.install", metadata: ["name": BrowserLog.value(name), "url": BrowserLog.url(url), "has_icon": String(icon != nil)])
			guard let name = BrowserWebsiteAppPolicy.validatedName(name) else { throw RegistryError.invalidName }
			guard let url = BrowserWebsiteAppPolicy.validatedURL(url) else { throw RegistryError.invalidURL }
			guard let templateURL = resourceBundle.url(forResource: "AstraWebsiteAppTemplate", withExtension: "app") else {
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
			BrowserLog.notice(.websiteApps, "website-app.uninstall", metadata: ["id": BrowserLog.id(id)])
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
			BrowserLog.info(.websiteApps, "website-app.rename", metadata: ["id": BrowserLog.id(id), "name": BrowserLog.value(newName)])
			guard let name = BrowserWebsiteAppPolicy.validatedName(newName) else { throw RegistryError.invalidName }
			guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
			let old = installations[index]
			guard isOwnedInstallation(old.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			// Keep the installed path stable so existing Dock tiles continue to resolve.
			try configureBundle(at: old.bundleURL, id: id, name: name, launchURL: old.launchURL, icon: nil)
			installations[index].name = name
			installations[index].modifiedAt = .now
			try save()
		}

		func updateIcon(_ id: UUID, icon: NSImage) throws {
			BrowserLog.info(.websiteApps, "website-app.update-icon", metadata: ["id": BrowserLog.id(id)])
			guard let index = installations.firstIndex(where: { $0.id == id }) else { return }
			let installation = installations[index]
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			try configureBundle(at: installation.bundleURL, id: id, name: installation.name, launchURL: installation.launchURL, icon: icon)
			installations[index].modifiedAt = .now
			try save()
		}

		func launch(_ id: UUID) throws {
			BrowserLog.info(.websiteApps, "website-app.launch", metadata: ["id": BrowserLog.id(id)])
			guard let installation = installation(for: id),
			      isOwnedInstallation(installation.bundleURL),
			      fileManager.fileExists(atPath: installation.bundlePath)
			else { throw RegistryError.installationOutsideOwnedDirectory }
			try migrateToSharedRuntime(installation)
			try registerGeneratedApp(at: installation.bundleURL)
			NSWorkspace.shared.openApplication(at: installation.bundleURL, configuration: .init())
		}

		func reveal(_ id: UUID) throws {
			guard let installation = installation(for: id) else { return }
			guard isOwnedInstallation(installation.bundleURL) else { throw RegistryError.installationOutsideOwnedDirectory }
			NSWorkspace.shared.activateFileViewerSelecting([installation.bundleURL])
		}

		func beginKeepInDockFlow(_ id: UUID) async throws {
			guard let installation = installation(for: id),
			      isOwnedInstallation(installation.bundleURL),
			      fileManager.fileExists(atPath: installation.bundlePath)
			else { throw RegistryError.installationOutsideOwnedDirectory }
			try migrateToSharedRuntime(installation)
			try registerGeneratedApp(at: installation.bundleURL)
			try await pinToDock(installation)
			try launch(id)
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

		private func registerGeneratedApp(at appURL: URL) throws {
			// Match Chromium's generated-shim installation: copied quarantine belongs
			// to the downloaded template, not to an app assembled locally by Astra.
			let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
			guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any],
			      let executable = plist["CFBundleExecutable"] as? String,
			      !executable.isEmpty, !executable.contains("/"),
			      executable != ".", executable != ".."
			else { throw RegistryError.templateInvalid }
			let executableURL = appURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
			for url in [appURL, executableURL] {
				if removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW) != 0 {
					let error = errno
					guard error == ENOATTR else {
						throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
					}
				}
			}
			let status = LSRegisterURL(appURL as CFURL, true)
			guard status == noErr else { throw RegistryError.registrationFailed(status) }
		}

		private func migrateToSharedRuntime(_ installation: BrowserWebsiteAppInstallation) throws {
			let plistURL = installation.bundleURL.appendingPathComponent("Contents/Info.plist")
			let plist = NSDictionary(contentsOf: plistURL) as? [String: Any]
			guard plist?["AstraWebsiteAppRuntimeVersion"] as? Int != 1 else { return }
			try configureBundle(
				at: installation.bundleURL,
				id: installation.id,
				name: installation.name,
				launchURL: installation.launchURL,
				icon: nil
			)
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

		private func save() throws {
			BrowserLog.debug(.websiteApps, "website-app.registry-save", metadata: ["count": String(installations.count)])
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
			guard let templateURL = resourceBundle.url(forResource: "AstraWebsiteAppTemplate", withExtension: "app"),
			      let templatePlist = NSDictionary(contentsOf: templateURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
			      let executable = templatePlist["CFBundleExecutable"] as? String
			else { throw RegistryError.templateMissing }
			let entitlements = try signingEntitlements(from: templateURL)
			let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
			let plistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
			guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
				throw RegistryError.templateInvalid
			}
			plist["CFBundleIdentifier"] = BrowserWebsiteAppPolicy.bundleIdentifier(for: id)
			plist["CFBundleName"] = name
			plist["CFBundleDisplayName"] = name
			plist["CFBundleExecutable"] = executable
			plist["AstraWebsiteAppRuntimeVersion"] = 1
			plist["AstraWebsiteAppLaunchURL"] = launchURL.absoluteString
			plist["AstraWebsiteAppURL"] = launchURL.absoluteString
			var hostCode: SecStaticCode?
			var requirement: SecRequirement?
			var requirementText: CFString?
			guard let hostIdentifier = resourceBundle.bundleIdentifier,
			      SecStaticCodeCreateWithPath(resourceBundle.bundleURL as CFURL, [], &hostCode) == errSecSuccess,
			      let hostCode,
			      SecCodeCopyDesignatedRequirement(hostCode, [], &requirement) == errSecSuccess,
			      let requirement,
			      SecRequirementCopyString(requirement, [], &requirementText) == errSecSuccess,
			      let requirementText
			else { throw RegistryError.templateInvalid }
			plist["AstraWebsiteAppHostBundlePath"] = resourceBundle.bundleURL.path
			plist["AstraWebsiteAppHostBundleIdentifier"] = hostIdentifier
			plist["AstraWebsiteAppHostCodeRequirement"] = requirementText as String
			// Replace legacy browser binaries with the bundled launcher. The browser
			// implementation and its frameworks now stay inside Astra.app.
			let executableDirectory = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
			try fileManager.removeItem(at: executableDirectory)
			try fileManager.copyItem(at: templateURL.appendingPathComponent("Contents/MacOS"), to: executableDirectory)
			let frameworksDirectory = contentsURL.appendingPathComponent("Frameworks", isDirectory: true)
			if fileManager.fileExists(atPath: frameworksDirectory.path) {
				try fileManager.removeItem(at: frameworksDirectory)
			}
			if let icon {
				let iconURL = contentsURL.appendingPathComponent("Resources/WebsiteIcon.icns")
				try writeIcon(icon, to: iconURL)
				plist["CFBundleIconFile"] = "WebsiteIcon"
				plist.removeValue(forKey: "CFBundleIconName")
			}
			let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
			try data.write(to: plistURL, options: .atomic)
			try adHocSign(appURL, entitlements: entitlements)
			try registerGeneratedApp(at: appURL)
		}

		private func writeIcon(_ image: NSImage, to url: URL) throws {
			guard let bitmap = NSBitmapImageRep(
				bitmapDataPlanes: nil,
				pixelsWide: 256,
				pixelsHigh: 256,
				bitsPerSample: 8,
				samplesPerPixel: 4,
				hasAlpha: true,
				isPlanar: false,
				colorSpaceName: .deviceRGB,
				bytesPerRow: 0,
				bitsPerPixel: 0
			), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw RegistryError.templateInvalid }
			NSGraphicsContext.saveGraphicsState()
			NSGraphicsContext.current = context
			image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256), from: .zero, operation: .copy, fraction: 1)
			NSGraphicsContext.restoreGraphicsState()
			try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			guard let cgImage = bitmap.cgImage,
			      let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.apple.icns" as CFString, 1, nil)
			else {
				throw RegistryError.templateInvalid
			}
			CGImageDestinationAddImage(destination, cgImage, nil)
			guard CGImageDestinationFinalize(destination) else { throw RegistryError.templateInvalid }
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
				"--force", "--sign", "-", "--options", "runtime", "--entitlements", entitlementsURL.path, bundleURL.path,
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
