import SwiftUI

struct BrowserRootView: View {
	@State private var browser = Browser()
	@Environment(\.scenePhase) private var scenePhase

	#if os(iOS)
		@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	#endif

	var body: some View {
		#if os(macOS)
			DesktopBrowserShell(browser: browser)
		#elseif os(iOS)
			Group {
				if horizontalSizeClass == .compact {
					CompactBrowserShell(browser: browser)
				} else {
					DesktopBrowserShell(browser: browser)
				}
			}
		#else
			DesktopBrowserShell(browser: browser)
		#endif
			.onChange(of: scenePhase) { _, phase in
				if phase != .active {
					browser.flushPersistence()
				}
			}
	}
}

#Preview {
	BrowserRootView()
}
