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
		#if os(macOS)
		.windowStyle(.hiddenTitleBar)
		.windowBackgroundDragBehavior(.disabled)
		#endif
		.commandsRemoved()
		#if os(macOS)
			.commands {
				BrowserCommands()

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
