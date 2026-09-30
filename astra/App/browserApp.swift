//
//  browserApp.swift
//  browser
//
//  Created by Adon Omeri on 20/9/2026.
//

import SwiftUI

extension Color {
	static let customPurple = Color(
		red: 112.0 / 255,
		green: 124.0 / 255,
		blue: 255.0 / 255
	)
}

#if os(macOS)
	import AppKit

	@main
	enum browserApp {
		@MainActor
		static func main() {
			let application = NSApplication.shared
			let delegate = AppDelegate()

			application.setActivationPolicy(.regular)
			application.delegate = delegate
			application.run()

			// NSApplication's delegate is not an ownership boundary we want to
			// rely on. Keep it alive for the entire run loop explicitly.
			_ = delegate
		}
	}
#else
	@main
	struct browserApp: App {
		var body: some Scene {
			WindowGroup {
				ContentView()
					.task {
						await BrowserExtensionManager.shared.prepare()
						BrowserDownloadManager.shared.resumeAvailableDownloads()
					}
			}
		}
	}
#endif
