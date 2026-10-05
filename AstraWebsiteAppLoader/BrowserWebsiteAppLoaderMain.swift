import AppKit
import Darwin
import Foundation
import Security

@main
enum BrowserWebsiteAppLoaderMain {
	@MainActor
	static func main() {
		do {
			let host = try verifiedHost()
			let runtime = host.appendingPathComponent("Contents/Frameworks/AstraWebsiteAppRuntime.framework/AstraWebsiteAppRuntime")
			guard let library = dlopen(runtime.path, RTLD_NOW | RTLD_LOCAL) else {
				throw failure("Astra's website-app runtime could not load. Reinstall the website app from Astra.")
			}
			defer { dlclose(library) }
			guard let symbol = dlsym(library, "AstraWebsiteAppMain") else {
				throw failure("Astra's website-app runtime is incompatible. Reinstall the website app from Astra.")
			}
			typealias RuntimeMain = @convention(c) () -> Void
			let run = unsafeBitCast(symbol, to: RuntimeMain.self)
			run()
		} catch {
			let alert = NSAlert()
			alert.messageText = "Website App Could Not Open"
			alert.informativeText = error.localizedDescription
			alert.addButton(withTitle: "OK")
			alert.runModal()
		}
	}

	@MainActor
	private static func verifiedHost() throws -> URL {
		guard let requirementText = Bundle.main.object(forInfoDictionaryKey: "AstraWebsiteAppHostCodeRequirement") as? String,
		      let identifier = Bundle.main.object(forInfoDictionaryKey: "AstraWebsiteAppHostBundleIdentifier") as? String
		else { throw failure("This website app has no Astra installation. Reinstall it from Astra.") }
		var requirement: SecRequirement?
		guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
		      let requirement
		else { throw failure("The website app's Astra signing requirement is invalid.") }

		var candidates: [URL] = []
		if let path = Bundle.main.object(forInfoDictionaryKey: "AstraWebsiteAppHostBundlePath") as? String {
			candidates.append(URL(fileURLWithPath: path, isDirectory: true))
		}
		if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
			candidates.append(registered)
		}
		for candidate in candidates {
			var code: SecStaticCode?
			guard Bundle(url: candidate)?.bundleIdentifier == identifier,
			      SecStaticCodeCreateWithPath(candidate as CFURL, [], &code) == errSecSuccess,
			      let code,
			      SecStaticCodeCheckValidity(
			      	code,
			      	SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode),
			      	requirement
			      ) == errSecSuccess
			else { continue }
			return candidate
		}
		throw failure("Astra is missing or its signature does not match. Reinstall this website app from Astra.")
	}

	private static func failure(_ message: String) -> NSError {
		NSError(domain: "AstraWebsiteAppLoader", code: 1, userInfo: [
			NSLocalizedDescriptionKey: message,
		])
	}
}
