//
//  browserApp.swift
//  browser
//
//  Created by Adon Omeri on 20/9/2026.
//

import Sparkle
import SwiftUI

extension Color {
	static let customPurple = Color(
		red: 112.0 / 255,
		green: 124.0 / 255,
		blue: 255.0 / 255
	)
}

@main
struct browserApp: App {
	@State private var browser = Browser()
	@State private var updates = UpdateManager.shared

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
				.task {
					updates.start()
				}
				.sheet(isPresented: $updates.isPresented) {
					BrowserUpdateSheet(updates: updates)
				}
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
			}

			CommandGroup(replacing: .appInfo) {
				Button {
					browser.openInternalPage(.settings) // info
				} label: {
					Label("About astra", systemImage: "info.circle")
				}

				CheckForUpdatesView(
					updater: updates.updater
				)
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
