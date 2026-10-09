#if os(macOS)
	import CoreServices
	import Darwin
	import Foundation
	import ImageIO
	import Security

	nonisolated enum BrowserWebsiteAppFileError: LocalizedError {
		case templateMissing
		case templateInvalid
		case outsideOwnedDirectory
		case signingFailed(String)
		case registrationFailed(OSStatus)
		case operationInProgress

		var errorDescription: String? {
			switch self {
				case .templateMissing: "The website-app helper template is not included in this build."
				case .templateInvalid: "The website-app helper template is invalid."
				case .outsideOwnedDirectory: "Astra refused to modify a website app outside its owned installation directory."
				case let .signingFailed(message): "Website app signing failed: \(message)"
				case let .registrationFailed(status): "macOS could not register the website app (\(status))."
				case .operationInProgress: "Another website-app operation is still running."
			}
		}
	}

	/// Owned bundle operations execute on an actor, not the UI executor.
	/// Registry persistence is part of each operation; observed UI state changes
	/// only after the disk transaction has completed successfully.
	actor BrowserWebsiteAppFileWorker {
		private let rootURL: URL
		private let templateURL: URL?
		private let hostBundleURL: URL
		private let hostBundleIdentifier: String?

		init(rootURL: URL, templateURL: URL?, hostBundleURL: URL, hostBundleIdentifier: String?) {
			self.rootURL = rootURL
			self.templateURL = templateURL
			self.hostBundleURL = hostBundleURL
			self.hostBundleIdentifier = hostBundleIdentifier
		}

		func install(
			_ installation: BrowserWebsiteAppInstallation,
			iconData: Data?,
			nextRegistry: [BrowserWebsiteAppInstallation]
		) async throws {
			guard let templateURL else { throw BrowserWebsiteAppFileError.templateMissing }
			let appURL = installation.bundleURL
			guard isOwned(appURL) else { throw BrowserWebsiteAppFileError.outsideOwnedDirectory }
			let staging = rootURL.appendingPathComponent(".installing-\(installation.id.uuidString).app", isDirectory: true)
			try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
			guard !FileManager.default.fileExists(atPath: appURL.path),
			      !FileManager.default.fileExists(atPath: staging.path)
			else { throw CocoaError(.fileWriteFileExists) }
			var published = false
			do {
				try FileManager.default.copyItem(at: templateURL, to: staging)
				try await configureBundle(at: staging, id: installation.id, name: installation.name,
				                          launchURL: installation.launchURL, iconData: iconData)
				try Task.checkCancellation()
				try FileManager.default.moveItem(at: staging, to: appURL)
				published = true
				try registerGeneratedApp(at: appURL)
				try saveRegistry(nextRegistry)
			} catch {
				// If persistence or registration fails, never publish a broken app.
				try? FileManager.default.removeItem(at: staging)
				if published {
					try? FileManager.default.removeItem(at: appURL)
				}
				throw error
			}
		}

		func replace(
			_ installation: BrowserWebsiteAppInstallation,
			iconData: Data?,
			nextRegistry: [BrowserWebsiteAppInstallation]?
		) async throws {
			let original = installation.bundleURL
			guard isOwned(original) else { throw BrowserWebsiteAppFileError.outsideOwnedDirectory }
			guard FileManager.default.fileExists(atPath: original.path) else { throw CocoaError(.fileNoSuchFile) }
			let staging = rootURL.appendingPathComponent(".replacing-\(UUID().uuidString).app", isDirectory: true)
			let backupName = ".app-backup-\(UUID().uuidString).app"
			let backupURL = rootURL.appendingPathComponent(backupName, isDirectory: true)
			var replaced = false
			do {
				try FileManager.default.copyItem(at: original, to: staging)
				try await configureBundle(at: staging, id: installation.id, name: installation.name,
				                          launchURL: installation.launchURL, iconData: iconData)
				try Task.checkCancellation()
				_ = try FileManager.default.replaceItemAt(original, withItemAt: staging, backupItemName: backupName)
				replaced = true
				try registerGeneratedApp(at: original)
				if let nextRegistry {
					try saveRegistry(nextRegistry)
				}
				try? FileManager.default.removeItem(at: backupURL)
			} catch {
				try? FileManager.default.removeItem(at: staging)
				if replaced, FileManager.default.fileExists(atPath: backupURL.path) {
					// A signed, previously valid bundle remains recoverable even
					// when replacing it or writing the registry fails.
					_ = try? FileManager.default.replaceItemAt(
						original, withItemAt: backupURL, backupItemName: nil
					)
					try? registerGeneratedApp(at: original)
				}
				throw error
			}
		}

		func uninstall(_ installation: BrowserWebsiteAppInstallation, nextRegistry: [BrowserWebsiteAppInstallation]) throws {
			let url = installation.bundleURL
			guard isOwned(url) else { throw BrowserWebsiteAppFileError.outsideOwnedDirectory }
			var trashURL: NSURL?
			if FileManager.default.fileExists(atPath: url.path) {
				_ = try FileManager.default.trashItem(at: url, resultingItemURL: &trashURL)
			}
			do {
				try saveRegistry(nextRegistry)
			} catch {
				if let trashURL, !FileManager.default.fileExists(atPath: url.path) {
					try? FileManager.default.moveItem(at: trashURL as URL, to: url)
				}
				throw error
			}
		}

		func prepareLaunch(_ installation: BrowserWebsiteAppInstallation) async throws {
			let url = installation.bundleURL
			guard isOwned(url), FileManager.default.fileExists(atPath: url.path) else {
				throw BrowserWebsiteAppFileError.outsideOwnedDirectory
			}
			let plistURL = url.appendingPathComponent("Contents/Info.plist")
			let plist = NSDictionary(contentsOf: plistURL) as? [String: Any]
			if plist?["AstraWebsiteAppRuntimeVersion"] as? Int != 1 {
				try await replace(installation, iconData: nil, nextRegistry: nil)
			}
			try registerGeneratedApp(at: url)
		}

		private func saveRegistry(_ records: [BrowserWebsiteAppInstallation]) throws {
			let destination = rootURL.appendingPathComponent("registry.json")
			let data = try JSONEncoder().encode(records.sorted { $0.id.uuidString < $1.id.uuidString })
			guard data.count <= 1_048_576 else { throw CocoaError(.fileWriteOutOfSpace) }
			try data.write(to: destination, options: .atomic)
		}

		private func isOwned(_ url: URL) -> Bool {
			let root = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
			return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root + "/")
		}

		private func configureBundle(at url: URL, id: UUID, name: String, launchURL: URL, iconData: Data?) async throws {
			guard let templateURL,
			      let template = NSDictionary(contentsOf: templateURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
			      let executable = template["CFBundleExecutable"] as? String,
			      !executable.isEmpty, !executable.contains("/")
			else { throw BrowserWebsiteAppFileError.templateInvalid }
			let entitlements = try await signingEntitlements(from: templateURL)
			let contents = url.appendingPathComponent("Contents", isDirectory: true)
			let plistURL = contents.appendingPathComponent("Info.plist")
			guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any],
			      let hostBundleIdentifier,
			      let requirement = try? hostCodeRequirement()
			else { throw BrowserWebsiteAppFileError.templateInvalid }
			plist["CFBundleIdentifier"] = BrowserWebsiteAppPolicy.bundleIdentifier(for: id)
			plist["CFBundleName"] = name
			plist["CFBundleDisplayName"] = name
			plist["CFBundleExecutable"] = executable
			plist["AstraWebsiteAppRuntimeVersion"] = 1
			plist["AstraWebsiteAppLaunchURL"] = launchURL.absoluteString
			plist["AstraWebsiteAppURL"] = launchURL.absoluteString
			plist["AstraWebsiteAppHostBundlePath"] = hostBundleURL.path
			plist["AstraWebsiteAppHostBundleIdentifier"] = hostBundleIdentifier
			plist["AstraWebsiteAppHostCodeRequirement"] = requirement
			let executableDirectory = contents.appendingPathComponent("MacOS", isDirectory: true)
			try FileManager.default.removeItem(at: executableDirectory)
			try FileManager.default.copyItem(at: templateURL.appendingPathComponent("Contents/MacOS"), to: executableDirectory)
			let frameworks = contents.appendingPathComponent("Frameworks", isDirectory: true)
			if FileManager.default.fileExists(atPath: frameworks.path) {
				try FileManager.default.removeItem(at: frameworks)
			}
			if let iconData {
				let target = contents.appendingPathComponent("Resources/WebsiteIcon.icns")
				try writeIcon(iconData, to: target)
				plist["CFBundleIconFile"] = "WebsiteIcon"
				plist.removeValue(forKey: "CFBundleIconName")
			}
			let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
			try data.write(to: plistURL, options: .atomic)
			try await signBundle(url, entitlements: entitlements)
		}

		private func hostCodeRequirement() throws -> String {
			var hostCode: SecStaticCode?
			var requirement: SecRequirement?
			var text: CFString?
			guard SecStaticCodeCreateWithPath(hostBundleURL as CFURL, [], &hostCode) == errSecSuccess,
			      let hostCode,
			      SecCodeCopyDesignatedRequirement(hostCode, [], &requirement) == errSecSuccess,
			      let requirement,
			      SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
			      let text else { throw BrowserWebsiteAppFileError.templateInvalid }
			return text as String
		}

		private func writeIcon(_ data: Data, to url: URL) throws {
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			guard let source = CGImageSourceCreateWithData(data as CFData, nil),
			      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
			      	kCGImageSourceCreateThumbnailFromImageAlways: true,
			      	kCGImageSourceThumbnailMaxPixelSize: 256,
			      ] as CFDictionary),
			      let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.apple.icns" as CFString, 1, nil)
			else { throw BrowserWebsiteAppFileError.templateInvalid }
			CGImageDestinationAddImage(destination, image, nil)
			guard CGImageDestinationFinalize(destination) else { throw BrowserWebsiteAppFileError.templateInvalid }
		}

		private func registerGeneratedApp(at url: URL) throws {
			let plistURL = url.appendingPathComponent("Contents/Info.plist")
			guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any],
			      let executable = plist["CFBundleExecutable"] as? String,
			      !executable.isEmpty, !executable.contains("/"), executable != ".", executable != ".."
			else { throw BrowserWebsiteAppFileError.templateInvalid }
			let executableURL = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
			for path in [url, executableURL] {
				if removexattr(path.path, "com.apple.quarantine", XATTR_NOFOLLOW) != 0 {
					let code = errno
					guard code == ENOATTR else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
				}
			}
			let status = LSRegisterURL(url as CFURL, true)
			guard status == noErr else { throw BrowserWebsiteAppFileError.registrationFailed(status) }
		}

		private func signingEntitlements(from url: URL) async throws -> Data {
			let result = try await runCodesign(["-d", "--entitlements", ":-", url.path])
			guard result.status == 0,
			      let plist = entitlementPlist(result.stdout) ?? entitlementPlist(result.stderr),
			      (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) is [String: Any]
			else { throw BrowserWebsiteAppFileError.templateInvalid }
			return plist
		}

		private func entitlementPlist(_ bytes: Data) -> Data? {
			guard let text = String(data: bytes, encoding: .utf8),
			      let start = text.range(of: "<?xml"),
			      let end = text.range(of: "</plist>", options: .backwards)
			else { return nil }
			return String(text[start.lowerBound ..< end.upperBound]).data(using: .utf8)
		}

		private func signBundle(_ url: URL, entitlements: Data) async throws {
			let entitlementsURL = rootURL.appendingPathComponent(".signing-\(UUID().uuidString).plist")
			try entitlements.write(to: entitlementsURL, options: .atomic)
			defer { try? FileManager.default.removeItem(at: entitlementsURL) }
			let sign = try await runCodesign([
				"--force", "--sign", "-", "--options", "runtime",
				"--entitlements", entitlementsURL.path, url.path,
			])
			guard sign.status == 0 else {
				let message = String(data: sign.stderr, encoding: .utf8) ?? "codesign failed"
				throw BrowserWebsiteAppFileError.signingFailed(String(message.prefix(500)))
			}
			let verify = try await runCodesign(["--verify", "--strict", url.path])
			guard verify.status == 0 else {
				let message = String(data: verify.stderr, encoding: .utf8) ?? "codesign verification failed"
				throw BrowserWebsiteAppFileError.signingFailed(String(message.prefix(500)))
			}
		}

		/// Disk-backed output avoids pipe-buffer deadlocks and does not run a
		/// blocking waitUntilExit on MainActor or the file actor.
		private func runCodesign(_ arguments: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data) {
			try Task.checkCancellation()
			let outputURL = rootURL.appendingPathComponent(".codesign-output-\(UUID().uuidString)")
			let errorURL = rootURL.appendingPathComponent(".codesign-error-\(UUID().uuidString)")
			FileManager.default.createFile(atPath: outputURL.path, contents: nil)
			FileManager.default.createFile(atPath: errorURL.path, contents: nil)
			defer {
				try? FileManager.default.removeItem(at: outputURL)
				try? FileManager.default.removeItem(at: errorURL)
			}
			let stdout = try FileHandle(forWritingTo: outputURL)
			let stderr = try FileHandle(forWritingTo: errorURL)
			defer { try? stdout.close(); try? stderr.close() }
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
			process.arguments = arguments
			process.standardOutput = stdout
			process.standardError = stderr
			let status: Int32 = try await withCheckedThrowingContinuation { continuation in
				process.terminationHandler = { completed in
					continuation.resume(returning: completed.terminationStatus)
				}
				do {
					try process.run()
				} catch {
					process.terminationHandler = nil
					continuation.resume(throwing: error)
				}
			}
			try stdout.close()
			try stderr.close()
			try Task.checkCancellation()
			return try (
				status,
				Data(contentsOf: outputURL),
				Data(contentsOf: errorURL)
			)
		}
	}
#endif
