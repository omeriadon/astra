//
//  ContentView.swift
//  browser
//
//  Created by Adon Omeri on 20/9/2026.
//

import SwiftUI

struct ContentView: View {
	@State private var browser = Browser()
	#if os(iOS)
		@State private var sceneIntegration = BrowserIOSSceneIntegration()
		@Environment(\.scenePhase) private var scenePhase
	#endif

	var body: some View {
		BrowserRootView(browser: $browser)
			.onOpenURL { url in
				#if os(iOS)
					_ = sceneIntegration.openIncomingURL(url, in: browser)
				#else
					guard url.scheme == "http" || url.scheme == "https" else { return }
					let tab = browser.addTab()
					tab.controller?.load(url)
				#endif
			}
		#if os(iOS)
			.onAppear {
				sceneIntegration.attach(browser)
			}
			.onChange(of: scenePhase) { _, phase in
				sceneIntegration.scenePhaseDidChange(phase, browser: browser)
			}
			.onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
				sceneIntegration.handleMemoryWarning(in: browser)
			}
			.onDisappear {
				sceneIntegration.disconnect(browser)
			}
		#endif
	}
}
