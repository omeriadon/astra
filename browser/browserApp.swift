//
//  browserApp.swift
//  browser
//
//  Created by Adon Omeri on 20/9/2026.
//

import SwiftUI

@main
struct browserApp: App {
	@State private var browser = Browser()

	#if os(macOS)
		@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
		@State private var lastQuitAttempt: Date?

		private func requestQuit() {
			let now = Date()

			if let lastQuitAttempt,
			   now.timeIntervalSince(lastQuitAttempt) < 0.5
			{
				NSApplication.shared.terminate(nil)
				self.lastQuitAttempt = nil
			} else {
				lastQuitAttempt = now
			}
		}
	#endif

	var body: some Scene {
		WindowGroup {
			ContentView(browser: $browser)
				.onOpenURL { url in
					guard url.scheme == "http" || url.scheme == "https" else {
						return
					}

					browser.addTab()
				}
		}
		#if os(macOS)
		.windowStyle(.hiddenTitleBar)
		.windowBackgroundDragBehavior(.disabled)
		#endif

		.commands {
			BrowserCommands()

			CommandGroup(after: .appSettings) {
				Button {
					browser.openInternalPage(.settings)
				} label: {
					Label("Settings...", systemImage: "gear")
				}
				.keyboardShortcut(",", modifiers: .command)

				#if DEBUG
					Button("Debug Stuff...", systemImage: "ladybug") {
						browser.openInternalPage(.debug)
					}
					.accessibilityIdentifier("open-debug-stuff")
				#endif
			}

			CommandGroup(replacing: .appInfo) {
				Button {
					browser.openInternalPage(.settings) // info
				} label: {
					Label("About Browser", systemImage: "info.circle")
				}
			}

			#if os(macOS)
				CommandGroup(replacing: .appTermination) {
					Button("Quit browser") {
						requestQuit()
						browser.isAboutToQuit = true
					}
					.keyboardShortcut("q", modifiers: .command)
				}
			#endif
		}
	}
}
