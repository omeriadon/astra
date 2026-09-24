//
//  AppDelegate.swift
//  browser
//
//  Created by Adon Omeri on 24/9/2026.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_: Notification) {
		// Disable for any windows already open
		disableTabbing()

		// Observe future windows opening
		NotificationCenter.default.addObserver(
			forName: NSWindow.didBecomeMainNotification,
			object: nil,
			queue: .main
		) { _ in
			self.disableTabbing()
		}
	}

	private func disableTabbing() {
		for window in NSApplication.shared.windows {
			window.tabbingMode = .disallowed
		}
	}
}
