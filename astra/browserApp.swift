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
			ContentView()
				.task {
					updates.start()
					BrowserDownloadManager.shared.resumeAvailableDownloads()
				}
				.sheet(isPresented: $updates.isPresented) {
					BrowserUpdateSheet(updates: updates)
				}
		}
		#if os(macOS)
		.windowStyle(.hiddenTitleBar)
		.windowBackgroundDragBehavior(.disabled)
		#endif

		.commands {
			BrowserCommands()

			#if os(macOS)
				CommandGroup(replacing: .appTermination) {
					Button("Quit browser") {
						requestQuit()
						BrowserWindowRegistry.shared.activeBrowser?.isAboutToQuit = true
					}
					.keyboardShortcut("q", modifiers: .command)
				}
			#endif
		}

		#if os(macOS)
			WindowGroup(id: "detached-tab", for: UUID.self) { windowID in
				ContentView(detachedWindowID: windowID.wrappedValue)
			}
			.windowStyle(.hiddenTitleBar)
			.windowBackgroundDragBehavior(.disabled)
		#endif
	}
}
