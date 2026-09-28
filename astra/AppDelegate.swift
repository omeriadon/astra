//
//  AppDelegate.swift
//  browser
//
//  Created by Adon Omeri on 24/9/2026.
//

#if os(macOS)
	import AppKit

	@MainActor
	final class AppDelegate: NSObject, NSApplicationDelegate {
		private var windows: [BrowserWindowController] = []
		private var lastQuitAttempt: Date?

		func applicationDidFinishLaunching(_: Notification) {
			UpdateManager.shared.start()
			BrowserDownloadManager.shared.resumeAvailableDownloads()
			openBrowserWindow()
		}

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

		func applicationShouldHandleReopen(
			_: NSApplication,
			hasVisibleWindows flag: Bool
		) -> Bool {
			if !flag {
				if let window = windows.first?.window {
					window.makeKeyAndOrderFront(nil)
				} else {
					openBrowserWindow()
				}
			}
			return true
		}

		func application(_: NSApplication, open urls: [URL]) {
			for url in urls where url.scheme == "http" || url.scheme == "https" {
				open(url)
			}
		}

		func requestQuit() {
			let now = Date()

			if let lastQuitAttempt,
			   now.timeIntervalSince(lastQuitAttempt) < 0.5
			{
				NSApplication.shared.terminate(nil)
				self.lastQuitAttempt = nil
			} else {
				lastQuitAttempt = now
				BrowserWindowRegistry.shared.activeBrowser?.isAboutToQuit = true
			}
		}

		@discardableResult
		func openBrowserWindow() -> BrowserWindowController {
			let controller = BrowserWindowController()
			controller.onClose = { [weak self, weak controller] in
				guard let self, let controller else { return }
				self.windows.removeAll { $0 === controller }
			}
			windows.append(controller)
			controller.showWindow(nil)
			controller.window?.makeKeyAndOrderFront(nil)
			NSApp.activate()
			return controller
		}

		private func open(_ url: URL) {
			let controller: BrowserWindowController

			if let keyWindow = NSApp.keyWindow,
			   let existing = windows.first(where: { $0.window === keyWindow })
			{
				controller = existing
			} else if let existing = windows.first {
				controller = existing
				existing.window?.makeKeyAndOrderFront(nil)
			} else {
				controller = openBrowserWindow()
			}

			let tab = controller.browser.addTab()
			tab.controller?.load(url)
		}
	}
#endif
