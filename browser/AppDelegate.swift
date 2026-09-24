//
//  AppDelegate.swift
//  browser
//
//  Created by Adon Omeri on 24/9/2026.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var didClearStartupFocus = false

	func applicationDidFinishLaunching(_: Notification) {
		// Disable for any windows already open
		disableTabbing()
		if let window = NSApplication.shared.keyWindow {
			clearStartupFocus(in: window)
		}

		// Observe future windows opening
		NotificationCenter.default.addObserver(
			forName: NSWindow.didBecomeKeyNotification,
			object: nil,
			queue: .main
		) { [weak self] notification in
			self?.disableTabbing()
			if let window = notification.object as? NSWindow {
				self?.clearStartupFocus(in: window)
			}
		}
	}

	private func clearStartupFocus(in window: NSWindow) {
		guard !didClearStartupFocus else { return }
		didClearStartupFocus = true
		DispatchQueue.main.async {
			window.makeFirstResponder(nil)
		}
	}

	private func disableTabbing() {
		for window in NSApplication.shared.windows {
			window.tabbingMode = .disallowed
		}
	}
}
