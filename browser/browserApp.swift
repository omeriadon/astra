//
//  browserApp.swift
//  browser
//
//  Created by Adon Omeri on 20/9/2026.
//

import SwiftUI

@main
struct browserApp: App {
	var body: some Scene {
		WindowGroup {
			ContentView()
		}
		.windowStyle(.hiddenTitleBar)
		.commandsRemoved()
		#if os(macOS)
			.commands {
				CommandGroup(replacing: .appSettings) {
					SettingsLink {
						Label("Settings…", systemImage: "gear")
					}
				}
			}
		#endif // os(macOS)

		#if os(macOS)

			Settings {
				BrowserSettingsView()
			}
		#endif // os(macOS)
	}
}
