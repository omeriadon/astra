//
//  AppDelegate.swift
//  browser
//
//  Created by Adon Omeri on 24/9/2026.
//

#if os(macOS)
	import AppKit
	import Sparkle

	@MainActor
	final class AppDelegate: NSObject, NSApplicationDelegate {
		private var windows: [BrowserWindowController] = []
		private var lastQuitAttempt: Date?

		func applicationWillFinishLaunching(_: Notification) {
			installMainMenu()
		}

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
				if let controller = windows.first {
					controller.showWindow()
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
				windows.removeAll { $0 === controller }
			}

			windows.append(controller)
			controller.showWindow()
			NSApp.activate()
			return controller
		}

		private var activeBrowser: Browser? {
			BrowserWindowRegistry.shared.activeBrowser
		}

		private func open(_ url: URL) {
			let controller: BrowserWindowController

			if let keyWindow = NSApp.keyWindow,
			   let existing = windows.first(where: { $0.window === keyWindow })
			{
				controller = existing
			} else if let existing = windows.first {
				controller = existing
				existing.showWindow()
			} else {
				controller = openBrowserWindow()
			}

			let tab = controller.browser.addTab()
			tab.controller?.load(url)
		}

		// MARK: - Browser actions

		@objc private func newWindow(_: Any?) {
			openBrowserWindow()
		}

		@objc private func newTab(_: Any?) {
			let browser: Browser = if let activeBrowser {
				activeBrowser
			} else {
				openBrowserWindow().browser
			}
			browser.addTab()
		}

		@objc private func closeTab(_: Any?) {
			guard let browser = activeBrowser else { return }
			browser.closeTab(browser.selectedTabID)
		}

		@objc private func closeWindow(_: Any?) {
			NSApp.keyWindow?.performClose(nil)
		}

		@objc private func toggleSidebar(_: Any?) {
			activeBrowser?.sidebarShown.toggle()
		}

		@objc private func editSpace(_: Any?) {
			activeBrowser?.openInternalPage(.themeEditor)
		}

		@objc private func openSettings(_: Any?) {
			activeBrowser?.openInternalPage(.settings)
		}

		@objc private func openHistory(_: Any?) {
			activeBrowser?.openInternalPage(.history)
		}

		@objc private func showAbout(_: Any?) {
			activeBrowser?.openInternalPage(.settings)
		}

		@objc private func checkForUpdates(_: Any?) {
			UpdateManager.shared.updater.checkForUpdates()
		}

		@objc private func openLocation(_: Any?) {
			guard let browser = activeBrowser else { return }
			if browser.selectedTab?.internalPage != nil {
				browser.addTab()
			} else {
				browser.addressFocusRequest += 1
			}
		}

		@objc private func goBack(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.goBack()
		}

		@objc private func goForward(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.goForward()
		}

		@objc private func reload(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.reload()
		}

		@objc private func forceReload(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.reloadFromOrigin()
		}

		@objc private func zoomIn(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.zoomIn()
		}

		@objc private func zoomOut(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.zoomOut()
		}

		@objc private func actualSize(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.resetZoom()
		}

		@objc private func addBookmark(_: Any?) {
			activeBrowser?.bookmarkSelectedPage()
		}

		@objc private func duplicateTab(_: Any?) {
			guard let browser = activeBrowser else { return }
			browser.duplicateTab(browser.selectedTabID)
		}

		@objc private func copyURL(_: Any?) {
			guard let url = activeBrowser?.selectedTab?.activeController?.url else { return }
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(url.absoluteString, forType: .string)
		}

		@objc private func toggleFullScreen(_: Any?) {
			NSApp.keyWindow?.toggleFullScreen(nil)
		}

		// MARK: - Main menu

		private func installMainMenu() {
			let mainMenu = NSMenu()

			let appMenu = NSMenu()
			mainMenu.addItem(menuRoot("astra", submenu: appMenu))
			appMenu.addItem(item("About astra", action: #selector(showAbout(_:))))
			appMenu.addItem(item("Check for Updates…", action: #selector(checkForUpdates(_:))))
			appMenu.addItem(.separator())

			let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
			let servicesMenu = NSMenu(title: "Services")
			servicesItem.submenu = servicesMenu
			appMenu.addItem(servicesItem)
			NSApp.servicesMenu = servicesMenu

			appMenu.addItem(.separator())
			appMenu.addItem(item("Hide astra", action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
			appMenu.addItem(item(
				"Hide Others",
				action: #selector(NSApplication.hideOtherApplications(_:)),
				key: "h",
				modifiers: [.command, .option],
				target: NSApp
			))
			appMenu.addItem(item("Show All", action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
			appMenu.addItem(.separator())
			appMenu.addItem(item("Settings…", action: #selector(openSettings(_:)), key: ","))
			appMenu.addItem(.separator())
			appMenu.addItem(item("Quit astra", action: #selector(quitFromMenu(_:)), key: "q"))

			let fileMenu = NSMenu(title: "File")
			mainMenu.addItem(menuRoot("File", submenu: fileMenu))
			fileMenu.addItem(item("New Window", action: #selector(newWindow(_:)), key: "n"))
			fileMenu.addItem(item("New Tab", action: #selector(newTab(_:)), key: "t"))
			fileMenu.addItem(.separator())
			fileMenu.addItem(item("Close Tab", action: #selector(closeTab(_:)), key: "w"))
			fileMenu.addItem(item(
				"Close Window",
				action: #selector(closeWindow(_:)),
				key: "w",
				modifiers: [.command, .shift]
			))

			let editMenu = NSMenu(title: "Edit")
			mainMenu.addItem(menuRoot("Edit", submenu: editMenu))
			editMenu.addItem(responderItem("Undo", action: Selector(("undo:")), key: "z"))
			editMenu.addItem(responderItem(
				"Redo",
				action: Selector(("redo:")),
				key: "z",
				modifiers: [.command, .shift]
			))
			editMenu.addItem(.separator())
			editMenu.addItem(responderItem("Cut", action: Selector(("cut:")), key: "x"))
			editMenu.addItem(responderItem("Copy", action: Selector(("copy:")), key: "c"))
			editMenu.addItem(responderItem("Paste", action: Selector(("paste:")), key: "v"))
			editMenu.addItem(responderItem("Select All", action: Selector(("selectAll:")), key: "a"))

			let viewMenu = NSMenu(title: "View")
			mainMenu.addItem(menuRoot("View", submenu: viewMenu))
			viewMenu.addItem(item("Toggle Sidebar", action: #selector(toggleSidebar(_:)), key: "s"))
			viewMenu.addItem(item("Edit Space", action: #selector(editSpace(_:))))
			viewMenu.addItem(.separator())
			viewMenu.addItem(item(
				"Enter Full Screen",
				action: #selector(toggleFullScreen(_:)),
				key: "f",
				modifiers: [.command, .control]
			))

			let navigationMenu = NSMenu(title: "Navigation")
			mainMenu.addItem(menuRoot("Navigation", submenu: navigationMenu))
			navigationMenu.addItem(item("History", action: #selector(openHistory(_:)), key: "y"))
			navigationMenu.addItem(.separator())
			navigationMenu.addItem(item("Open Location", action: #selector(openLocation(_:)), key: "l"))
			navigationMenu.addItem(item("Back", action: #selector(goBack(_:)), key: "["))
			navigationMenu.addItem(item("Forward", action: #selector(goForward(_:)), key: "]"))
			navigationMenu.addItem(.separator())
			navigationMenu.addItem(item("Reload", action: #selector(reload(_:)), key: "r"))
			navigationMenu.addItem(item(
				"Force Reload",
				action: #selector(forceReload(_:)),
				key: "r",
				modifiers: [.command, .shift]
			))
			navigationMenu.addItem(.separator())
			navigationMenu.addItem(item("Zoom In", action: #selector(zoomIn(_:)), key: "="))
			navigationMenu.addItem(item("Zoom Out", action: #selector(zoomOut(_:)), key: "-"))
			navigationMenu.addItem(item("Actual Size", action: #selector(actualSize(_:)), key: "0"))

			let bookmarksMenu = NSMenu(title: "Bookmarks")
			mainMenu.addItem(menuRoot("Bookmarks", submenu: bookmarksMenu))
			bookmarksMenu.addItem(item("Add Bookmark", action: #selector(addBookmark(_:)), key: "b"))

			let tabMenu = NSMenu(title: "Tab")
			mainMenu.addItem(menuRoot("Tab", submenu: tabMenu))
			tabMenu.addItem(item("Duplicate Tab", action: #selector(duplicateTab(_:)), key: "d"))
			tabMenu.addItem(item(
				"Copy URL",
				action: #selector(copyURL(_:)),
				key: "c",
				modifiers: [.option]
			))

			let windowMenu = NSMenu(title: "Window")
			mainMenu.addItem(menuRoot("Window", submenu: windowMenu))
			windowMenu.addItem(responderItem("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
			windowMenu.addItem(responderItem("Zoom", action: #selector(NSWindow.performZoom(_:))))
			windowMenu.addItem(.separator())
			windowMenu.addItem(item("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), target: NSApp))
			NSApp.windowsMenu = windowMenu

			let helpMenu = NSMenu(title: "Help")
			mainMenu.addItem(menuRoot("Help", submenu: helpMenu))
			NSApp.helpMenu = helpMenu

			NSApp.mainMenu = mainMenu
		}

		@objc private func quitFromMenu(_: Any?) {
			requestQuit()
		}

		private func menuRoot(_ title: String, submenu: NSMenu) -> NSMenuItem {
			let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
			root.submenu = submenu
			return root
		}

		private func item(
			_ title: String,
			action: Selector,
			key: String = "",
			modifiers: NSEvent.ModifierFlags = [.command],
			target: AnyObject? = nil
		) -> NSMenuItem {
			let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
			menuItem.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
			menuItem.target = target ?? self
			return menuItem
		}

		private func responderItem(
			_ title: String,
			action: Selector,
			key: String = "",
			modifiers: NSEvent.ModifierFlags = [.command]
		) -> NSMenuItem {
			let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
			menuItem.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
			menuItem.target = nil
			return menuItem
		}
	}
#endif
