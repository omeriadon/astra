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
	#if os(macOS)
		@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

		var body: some Scene {
			Settings {
				EmptyView()
			}
			.commands {
				BrowserCommands()

				CommandGroup(replacing: .appTermination) {
					Button("Quit astra") {
						(NSApp.delegate as? AppDelegate)?.requestQuit()
					}
					.keyboardShortcut("q", modifiers: .command)
				}
			}
		}
	#else
		@State private var updates = UpdateManager.shared

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
		}
	#endif
}
