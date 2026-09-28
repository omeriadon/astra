//
//  AppDelegate.swift
//  browser
//
//  Created by Adon Omeri on 24/9/2026.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		guard BrowserDownloadManager.shared.activeProgress != nil else {
			return .terminateNow
		}
		Task { @MainActor in
			await BrowserDownloadManager.shared.pauseAllForQuit()
			sender.reply(toApplicationShouldTerminate: true)
		}
		return .terminateLater
	}

	func applicationDidFinishLaunching(_: Notification) {
		configureExistingWindows()

		NotificationCenter.default.addObserver(
			forName: NSWindow.didBecomeKeyNotification,
			object: nil,
			queue: .main
		) { [weak self] notification in
			guard let window = notification.object as? NSWindow else { return }
			self?.configure(window)
		}
	}

	private func configureExistingWindows() {
		for window in NSApplication.shared.windows {
			configure(window)
		}
	}

	private func configure(_ window: NSWindow) {
		window.tabbingMode = .disallowed

		// Keep the real AppKit title bar and traffic lights, but let Astra's
		// content render through it. This avoids SwiftUI's hidden-title-bar
		// toolbar/glass hierarchy, which can intercept pointer events.
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.styleMask.insert(.fullSizeContentView)
		window.toolbar = nil
		window.titlebarSeparatorStyle = .none

		// Astra owns every draggable region explicitly.
		window.isMovableByWindowBackground = false
		window.isMovable = false
	}
}
