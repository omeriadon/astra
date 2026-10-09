import Foundation

@MainActor
enum BrowserResources {
	static let bundle: Bundle = {
		#if os(macOS) && ASTRA_WEBSITE_APP_RUNTIME
			let frameworkURL = Bundle(for: BrowserController.self).bundleURL
			let hostURL = frameworkURL
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent()
			guard let bundle = Bundle(url: hostURL) else {
				preconditionFailure("Unable to locate the host app bundle for AstraWebsiteAppRuntime")
			}
			return bundle
		#else
			return .main
		#endif
	}()
}
