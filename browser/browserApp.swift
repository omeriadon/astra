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

	var body: some Scene {
		WindowGroup {
			ContentView(browser: $browser)
		}
		#if os(macOS)
		.windowStyle(.hiddenTitleBar)
		.windowBackgroundDragBehavior(.disabled)
		#endif
		.commandsRemoved()
		.commands {
			BrowserCommands()

			CommandGroup(replacing: .appSettings) {
				Button {
					browser.openInternalPage(.settings)
				} label: {
					Label("Settings...", systemImage: "gear")
				}
				.keyboardShortcut(",", modifiers: .command)
			}
		}
	}
}
