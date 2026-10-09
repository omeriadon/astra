import Foundation

#if os(macOS) && ASTRA_WEBSITE_APP_RUNTIME
	import Darwin

	private nonisolated func browserResourcesImageAnchor() {}
#endif

@MainActor
enum BrowserResources {
	static let bundle: Bundle = {
		#if os(macOS) && ASTRA_WEBSITE_APP_RUNTIME
			if Bundle.main.bundleIdentifier == "com.omeriadon.astra" {
				return .main
			}
			let anchor: @convention(c) () -> Void = browserResourcesImageAnchor
			var image = Dl_info()
			guard dladdr(unsafeBitCast(anchor, to: UnsafeRawPointer.self), &image) != 0,
			      let path = image.dli_fname else { return .main }
			var hostURL = URL(fileURLWithPath: String(cString: path))
			while hostURL.path != "/" {
				if hostURL.pathExtension == "app", let bundle = Bundle(url: hostURL) {
					return bundle
				}
				hostURL.deleteLastPathComponent()
			}
			return .main
		#else
			return .main
		#endif
	}()
}
