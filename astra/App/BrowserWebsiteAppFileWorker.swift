#if os(macOS)
	import AppKit
	import Darwin
	import Foundation
	import ImageIO
	import Security

	nonisolated enum BrowserWebsiteAppFileError: LocalizedError {
		case templateMissing
		case templateInvalid
		case malformedTemplate(String)
		case outsideOwnedDirectory
		case signingFailed(String)
		case operationInProgress

		var errorDescription: String? {
			switch self {
				case .templateMissing: "The website-app helper template is not included in this build."
				case .templateInvalid: "The website-app helper template is invalid."
				case let .malformedTemplate(reason): "The website-app helper template is invalid: \(reason)"
				case .outsideOwnedDirectory: "Astra refused to modify a website app outside its owned installation directory."
				case let .signingFailed(message): "Website app signing failed: \(message)"
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
				try await registerGeneratedApp(at: appURL)
				try saveRegistry(nextRegistry)
			} catch {
				BrowserLog.error(.websiteApps, "website-app.install.failed", metadata: [
					"app": BrowserLog.id(installation.id),
					"published": String(published),
					"error": BrowserLog.errorDescription(error),
				])
				// If bundle creation or registry persistence fails, remove the unpublished app.
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
				try await registerGeneratedApp(at: original)
				if let nextRegistry {
					try saveRegistry(nextRegistry)
				}
				try? FileManager.default.removeItem(at: backupURL)
			} catch {
				BrowserLog.error(.websiteApps, "website-app.replace.failed", metadata: [
					"app": BrowserLog.id(installation.id),
					"replaced": String(replaced),
					"error": BrowserLog.errorDescription(error),
				])
				try? FileManager.default.removeItem(at: staging)
				if replaced, FileManager.default.fileExists(atPath: backupURL.path) {
					// A signed, previously valid bundle remains recoverable even
					// when replacing it or writing the registry fails.
					do {
						_ = try FileManager.default.replaceItemAt(
							original, withItemAt: backupURL, backupItemName: nil
						)
					} catch {
						BrowserLog.fault(.websiteApps, "website-app.replace.rollback-failed", metadata: [
							"app": BrowserLog.id(installation.id),
							"original": BrowserLog.path(original),
							"backup": BrowserLog.path(backupURL),
							"error": BrowserLog.errorDescription(error),
						])
					}
					do {
						try await registerGeneratedApp(at: original)
					} catch {
						BrowserLog.fault(.websiteApps, "website-app.replace.rollback-registration-failed", metadata: [
							"app": BrowserLog.id(installation.id),
							"original": BrowserLog.path(original),
							"error": BrowserLog.errorDescription(error),
						])
					}
				}
				throw error
			}
		}

		func uninstall(_ installation: BrowserWebsiteAppInstallation, nextRegistry: [BrowserWebsiteAppInstallation]) throws {
			let url = installation.bundleURL
			guard isOwned(url) else { throw BrowserWebsiteAppFileError.outsideOwnedDirectory }
			var trashURL: NSURL?
			if FileManager.default.fileExists(atPath: url.path) {
				_ = try unsafe FileManager.default.trashItem(at: url, resultingItemURL: &trashURL)
			}
			do {
				try saveRegistry(nextRegistry)
			} catch {
				BrowserLog.error(.websiteApps, "website-app.uninstall.registry-failed", metadata: [
					"app": BrowserLog.id(installation.id),
					"error": BrowserLog.errorDescription(error),
				])
				if let trashURL, !FileManager.default.fileExists(atPath: url.path) {
					do {
						try FileManager.default.moveItem(at: trashURL as URL, to: url)
					} catch {
						BrowserLog.fault(.websiteApps, "website-app.uninstall.rollback-failed", metadata: [
							"app": BrowserLog.id(installation.id),
							"trash": BrowserLog.path(trashURL as URL),
							"destination": BrowserLog.path(url),
							"error": BrowserLog.errorDescription(error),
						])
					}
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
			} else {
				try await registerGeneratedApp(at: url)
			}
		}

		private func registerGeneratedApp(at url: URL) async throws {
			try await runInstaller(operation: "--prepare", appURL: url) { message in
				BrowserWebsiteAppRegistry.RegistryError.launchPreparationFailed(message)
			}
		}

		@MainActor
		func runInstaller(
			operation: String,
			appURL: URL,
			failure: @Sendable (String) -> BrowserWebsiteAppRegistry.RegistryError
		) async throws {
			let helperName = "AstraWebsiteAppInstaller.app"
			let helperURL = hostBundleURL.appendingPathComponent("Contents/Resources")
				.appendingPathComponent(helperName)
			guard FileManager.default.fileExists(atPath: helperURL.path) else {
				BrowserLog.error(.websiteApps, "website-app.installer.unavailable", metadata: [
					"operation": operation,
					"helper": BrowserLog.path(helperURL),
				])
				throw failure("The website-app installer is unavailable.")
			}
			let responseURL = rootURL.appendingPathComponent("dock-result-\(UUID().uuidString).json")
			defer { try? FileManager.default.removeItem(at: responseURL) }
			BrowserLog.info(.websiteApps, "website-app.installer.start", metadata: [
				"operation": operation,
				"app": BrowserLog.path(appURL),
				"helper": BrowserLog.path(helperURL),
			])
			let configuration = NSWorkspace.OpenConfiguration()
			configuration.activates = false
			configuration.addsToRecentItems = false
			configuration.createsNewApplicationInstance = true
			configuration.arguments = [operation, appURL.path, responseURL.path]
			do {
				let helper = try await NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)
				let deadline = ContinuousClock.now.advanced(by: .seconds(15))
				while ContinuousClock.now < deadline {
					if let data = try? Data(contentsOf: responseURL) {
						let message = try JSONDecoder().decode(String.self, from: data)
						guard message.isEmpty else {
							BrowserLog.error(.websiteApps, "website-app.installer.failure", metadata: [
								"operation": operation,
								"app": BrowserLog.path(appURL),
								"error": BrowserLog.value(message),
							])
							throw failure(message)
						}
						BrowserLog.info(.websiteApps, "website-app.installer.success", metadata: [
							"operation": operation,
							"app": BrowserLog.path(appURL),
						])
						return
					}
					if helper.isTerminated {
						throw failure("The website-app installer exited without a result.")
					}
					try await Task.sleep(for: .milliseconds(100))
				}
				throw failure("The website-app installer did not respond.")
			} catch {
				BrowserLog.error(.websiteApps, "website-app.installer.transport-failed", metadata: [
					"operation": operation,
					"app": BrowserLog.path(appURL),
					"error": BrowserLog.errorDescription(error),
				])
				throw error
			}
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
			guard let templateURL else { throw BrowserWebsiteAppFileError.templateMissing }
			guard let template = NSDictionary(contentsOf: templateURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
				throw BrowserWebsiteAppFileError.malformedTemplate("The embedded app has no readable Contents/Info.plist.")
			}
			guard let executable = template["CFBundleExecutable"] as? String,
			      !executable.isEmpty, executable != ".", executable != "..", !executable.contains("/"),
			      FileManager.default.isExecutableFile(atPath: templateURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).path)
			else {
				throw BrowserWebsiteAppFileError.malformedTemplate("Its CFBundleExecutable is missing or not executable.")
			}
			let entitlements = try signingEntitlements(from: templateURL)
			let contents = url.appendingPathComponent("Contents", isDirectory: true)
			let plistURL = contents.appendingPathComponent("Info.plist")
			guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
				throw BrowserWebsiteAppFileError.malformedTemplate("The copied app's Info.plist could not be read.")
			}
			guard let hostBundleIdentifier else {
				throw BrowserWebsiteAppFileError.malformedTemplate("Astra's host bundle identifier is missing.")
			}
			let requirement = try hostCodeRequirement()
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
			guard unsafe SecStaticCodeCreateWithPath(hostBundleURL as CFURL, [], &hostCode) == errSecSuccess,
			      let hostCode
			else {
				throw BrowserWebsiteAppFileError.malformedTemplate("Astra's host app has no readable code signature.")
			}
			guard unsafe SecCodeCopyDesignatedRequirement(hostCode, [], &requirement) == errSecSuccess,
			      let requirement,
			      unsafe SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
			      let text
			else {
				throw BrowserWebsiteAppFileError.malformedTemplate("Astra's host signing requirement could not be obtained.")
			}
			return text as String
		}

		private func writeIcon(_ data: Data, to url: URL) throws {
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			guard let source = CGImageSourceCreateWithData(data as CFData, nil),
			      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
			      	kCGImageSourceCreateThumbnailFromImageAlways: true,
			      	kCGImageSourceThumbnailMaxPixelSize: 256,
			      ] as CFDictionary),
			      let context = unsafe CGContext(
			      	data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
			      	space: CGColorSpaceCreateDeviceRGB(),
			      	bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			      ),
			      let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.apple.icns" as CFString, 1, nil)
			else { throw BrowserWebsiteAppFileError.malformedTemplate("The website icon could not be converted to ICNS.") }
			// ICNS rejects some favicon dimensions; fit every image into a supported square.
			let scale = 256 / CGFloat(max(image.width, image.height))
			let width = CGFloat(image.width) * scale
			let height = CGFloat(image.height) * scale
			context.interpolationQuality = .high
			context.draw(image, in: CGRect(x: (256 - width) / 2, y: (256 - height) / 2, width: width, height: height))
			guard let icon = context.makeImage() else {
				throw BrowserWebsiteAppFileError.malformedTemplate("The website icon could not be converted to ICNS.")
			}
			CGImageDestinationAddImage(destination, icon, nil)
			guard CGImageDestinationFinalize(destination) else {
				throw BrowserWebsiteAppFileError.malformedTemplate("The website icon ICNS could not be written.")
			}
		}

		/// Read the signed entitlement dictionary directly from Security.framework.
		/// codesign -d --entitlements output isn't guaranteed to be UTF-8 XML;
		/// it may contain binary data or diagnostic text on different macOS releases.
		private func signingEntitlements(from url: URL) throws -> Data {
			var code: SecStaticCode?
			guard unsafe SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
			      let code
			else {
				throw BrowserWebsiteAppFileError.malformedTemplate("The embedded helper has no readable code signature.")
			}
			var signingInfo: CFDictionary?
			let status = unsafe SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo)
			guard status == errSecSuccess,
			      let info = signingInfo as? [String: Any],
			      let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
			      !entitlements.isEmpty
			else {
				throw BrowserWebsiteAppFileError.malformedTemplate("The signed helper's entitlements are missing or unreadable (Security status: \(status)).")
			}
			return try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
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
