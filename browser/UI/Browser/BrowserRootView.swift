import SwiftUI

struct BrowserRootView: View {
	@State private var browser = Browser()
	@State private var sync = BrowserSync.shared
	@Environment(\.scenePhase) private var scenePhase

	#if os(iOS)
		@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	#endif

	var body: some View {
		shell
		#if os(macOS)
			.focusedSceneValue(\.browser, browser)
		#endif
			.onAppear {
				sync.attach(browser)
			}
			.onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
				sync.settingsDidChange()
			}
			.onChange(of: scenePhase) { _, phase in
				if phase != .active {
					browser.flushPersistence()
				}
			}
	}

	@ViewBuilder
	private var shell: some View {
		#if os(macOS)
			DesktopBrowserShell(browser: browser)
		#elseif os(iOS)
			if horizontalSizeClass == .compact {
				CompactBrowserShell(browser: browser)
			} else {
				DesktopBrowserShell(browser: browser)
			}
		#else
			DesktopBrowserShell(browser: browser)
		#endif
	}
}

#Preview {
	BrowserRootView()
}
