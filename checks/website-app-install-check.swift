import AppKit
import Foundation

@main
struct WebsiteAppInstallCheck {
	@MainActor
	static func main() throws {
		guard CommandLine.arguments.count == 2,
		      let app = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))
		else {
			fatalError("Provide the built Astra app path")
		}
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("astra-website-app-check-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let registry = BrowserWebsiteAppRegistry(rootDirectory: root, resourceBundle: app)
		let destination = URL(string: "https://example.com/path")!
		let installation = try registry.install(name: "Disposable Website Fixture", url: destination, icon: nil)
		precondition(registry.installations.count == 1)
		let plistURL = installation.bundleURL.appendingPathComponent("Contents/Info.plist")
		let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
		precondition(plist["AstraWebsiteAppLaunchURL"] as? String == destination.absoluteString)
		precondition(plist["CFBundleIdentifier"] as? String == BrowserWebsiteAppPolicy.bundleIdentifier(for: installation.id))
		precondition(plist["AstraWebsiteAppHostBundlePath"] as? String == app.bundleURL.path)
		precondition(plist["AstraWebsiteAppHostBundleIdentifier"] as? String == app.bundleIdentifier)
		precondition(plist["AstraWebsiteAppHostCodeRequirement"] is String)
		precondition(plist["AstraWebsiteAppRuntimeVersion"] as? Int == 1)
		precondition(!FileManager.default.fileExists(atPath: installation.bundleURL.appendingPathComponent("Contents/Frameworks").path))
		let reloaded = BrowserWebsiteAppRegistry(rootDirectory: root, resourceBundle: app)
		precondition(reloaded.installations == registry.installations)
		try registry.rename(installation.id, to: "Renamed Website Fixture")
		precondition(registry.installations.first?.bundlePath == installation.bundlePath)
		let renamedPlist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
		precondition(renamedPlist["CFBundleDisplayName"] as? String == "Renamed Website Fixture")
		let image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
		try registry.updateIcon(installation.id, icon: image)
		precondition(registry.installations.count == 1)
		print("Production website-app install, launch metadata, persistence, rename and icon signing passed")
	}
}
