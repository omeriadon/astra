//
//  AppDelegate.swift
//  browser
//
//  Created by Adon Omeri on 24/9/2026.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var commandQMonitor: Any?
	private var lastCommandQPress: Date?

	private let doublePressInterval: TimeInterval = 1.0

	func applicationDidFinishLaunching(_: Notification) {
		installCommandQHandler()

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

	private func installCommandQHandler() {
		commandQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard
				event.charactersIgnoringModifiers?.lowercased() == "q",
				event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
			else {
				return event
			}

			guard !event.isARepeat else {
				return nil
			}

			let now = Date()

			if let lastPress = self?.lastCommandQPress,
			   now.timeIntervalSince(lastPress) <= self?.doublePressInterval ?? 1
			{
				self?.lastCommandQPress = nil

				NSApplication.shared.terminate(nil)
			} else {
				self?.lastCommandQPress = now
			}

			// Consume ⌘Q so the normal menu shortcut doesn't receive it.
			return nil
		}
	}

	func applicationWillTerminate(_: Notification) {
		if let commandQMonitor {
			NSEvent.removeMonitor(commandQMonitor)
		}
	}
}
