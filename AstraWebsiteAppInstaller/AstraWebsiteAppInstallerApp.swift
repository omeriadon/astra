import AppKit
import Foundation
import Security

@main
enum AstraWebsiteAppInstallerApp {
	@MainActor
	static func main() {
		let application = NSApplication.shared
		application.setActivationPolicy(.prohibited)
		application.finishLaunching()
		guard CommandLine.arguments.count == 4,
		      ["--pin", "--prepare"].contains(CommandLine.arguments[1]),
		      let response = validatedResponse(CommandLine.arguments[3])
		else { return }

		let message: String
		do {
			let appURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
			if CommandLine.arguments[1] == "--pin" {
				try pin(appURL)
			} else {
				_ = try prepareWebsiteApp(at: appURL)
			}
			message = ""
		} catch {
			message = error.localizedDescription
		}
		try? JSONEncoder().encode(message).write(to: response, options: .atomic)
	}

	private static var installationRoot: URL {
		FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Containers/com.omeriadon.astra/Data/Library/Application Support/Astra/Website Apps", isDirectory: true)
			.resolvingSymlinksInPath()
	}

	private static func validatedResponse(_ path: String) -> URL? {
		let url = URL(fileURLWithPath: path).standardizedFileURL
		guard url.deletingLastPathComponent().resolvingSymlinksInPath().path == installationRoot.path,
		      url.lastPathComponent.hasPrefix("dock-result-"),
		      url.pathExtension == "json",
		      UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.dropFirst("dock-result-".count))) != nil,
		      !FileManager.default.fileExists(atPath: url.path)
		else { return nil }
		return url
	}

	@MainActor
	private static func pin(_ appURL: URL) throws {
		let websiteApp = try prepareWebsiteApp(at: appURL)

		let defaults = UserDefaults.standard
		defaults.synchronize()
		guard var preferences = defaults.persistentDomain(forName: "com.apple.dock"),
		      var apps = preferences["persistent-apps"] as? [[String: Any]]
		else { throw failure("Astra could not read the Dock's app list.") }

		func matches(_ tile: [String: Any]) -> Bool {
			guard let data = tile["tile-data"] as? [String: Any] else { return false }
			if data["bundle-identifier"] as? String == websiteApp.identifier {
				return true
			}
			guard let file = data["file-data"] as? [String: Any],
			      let value = file["_CFURLString"] as? String else { return false }
			let url = (file["_CFURLStringType"] as? Int == 0)
				? URL(fileURLWithPath: value)
				: URL(string: value)
			return url?.standardizedFileURL.path == websiteApp.url.path
		}

		// Follow Chromium's dock.mm: preserve existing tiles, remove the matching
		// recent tile, and restart Dock only when its preferences changed.
		var changed = false
		if !apps.contains(where: matches) {
			apps.append([
				"tile-type": "file-tile",
				"tile-data": [
					"file-data": [
						"_CFURLString": websiteApp.url.absoluteString,
						"_CFURLStringType": 15,
					],
					"file-label": websiteApp.name,
					"bundle-identifier": websiteApp.identifier,
				],
			])
			preferences["persistent-apps"] = apps
			changed = true
		}
		if let recent = preferences["recent-apps"] as? [[String: Any]] {
			let filtered = recent.filter { !matches($0) }
			if filtered.count != recent.count {
				preferences["recent-apps"] = filtered
				changed = true
			}
		}
		guard changed else { return }
		defaults.setPersistentDomain(preferences, forName: "com.apple.dock")
		guard defaults.synchronize(),
		      let saved = defaults.persistentDomain(forName: "com.apple.dock"),
		      let savedApps = saved["persistent-apps"] as? [[String: Any]],
		      savedApps.contains(where: matches)
		else { throw failure("Astra could not save the website app in the Dock.") }

		guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
			return
		}
		guard kill(dock.processIdentifier, SIGTERM) == 0 else {
			throw failure("The website app was pinned, but the Dock could not refresh.")
		}
	}

	private static func prepareWebsiteApp(at inputURL: URL) throws -> (url: URL, identifier: String, name: String) {
		let appURL = inputURL.standardizedFileURL
		guard appURL.deletingLastPathComponent().resolvingSymlinksInPath().path == installationRoot.path,
		      appURL.resolvingSymlinksInPath().path == appURL.path,
		      appURL.pathExtension == "app",
		      let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
		      let identifier = info["CFBundleIdentifier"] as? String,
		      identifier.hasPrefix("dev.omeriadon.astra.website."),
		      let name = info["CFBundleDisplayName"] as? String,
		      let executable = info["CFBundleExecutable"] as? String,
		      !executable.isEmpty, !executable.contains("/"), executable != ".", executable != ".."
		else { throw failure("Astra refused to prepare an app outside its website-app directory.") }
		let executableURL = appURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
		guard executableURL.resolvingSymlinksInPath().path.hasPrefix(appURL.path + "/") else {
			throw failure("Astra refused to prepare an app with an executable outside its bundle.")
		}
		var code: SecStaticCode?
		let createStatus = SecStaticCodeCreateWithPath(appURL as CFURL, [], &code)
		guard createStatus == errSecSuccess, let code,
		      SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
		else { throw failure("The website app's signature is invalid.") }
		try removeQuarantineMetadata(from: appURL, executableURL: executableURL)
		return (appURL, identifier, name)
	}

	private static func removeQuarantineMetadata(from appURL: URL, executableURL: URL) throws {
		for path in [appURL, executableURL] where removexattr(path.path, "com.apple.quarantine", XATTR_NOFOLLOW) != 0 {
			let code = errno
			guard code == ENOATTR else {
				throw failure("Astra could not remove website app quarantine metadata: \(String(cString: strerror(code))).")
			}
		}
	}

	private static func failure(_ message: String) -> NSError {
		NSError(domain: "AstraWebsiteAppInstaller", code: 1, userInfo: [
			NSLocalizedDescriptionKey: message,
		])
	}
}
