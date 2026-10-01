//
//  AppDelegate.swift
//  browser
//
//  Created by Adon Omeri on 24/9/2026.
//

#if os(macOS)
	import AppKit
	import AuthenticationServices
	import Carbon
	import Defaults
	import Sparkle
	import WebKit

	@MainActor
	final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
		private var windows: [BrowserWindowController] = []
		private var miniWindows: [MiniAstraWindowController] = []
		private var lastQuitAttempt: Date?
		private var wasLaunchedForWebPush = false
		private var memoryPressureSource: DispatchSourceMemoryPressure?

		func applicationWillFinishLaunching(_: Notification) {
			#if DEBUG
				if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
					return
				}
			#endif
			installMainMenu()
			NSAppleEventManager.shared().setEventHandler(
				self,
				andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
				forEventClass: AEEventClass(kInternetEventClass),
				andEventID: AEEventID(kAEGetURL)
			)
			_ = BrowserWebSession.shared
			BrowserWebPushManager.shared.openRequested = { [weak self] url in self?.open(url) }
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(newMiniAstra(_:)),
				name: MiniAstraShortcut.notification,
				object: nil
			)
			MiniAstraShortcut.shared.update()
		}

		func applicationDidFinishLaunching(_: Notification) {
			#if DEBUG
				if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
					return
				}
			#endif
			let authentication = ASWebAuthenticationSessionWebBrowserSessionManager.shared
			authentication.sessionHandler = BrowserAuthenticationSessionHandler.shared
			Task { await BrowserExtensionManager.shared.prepare() }
			UpdateManager.shared.start()
			BrowserDownloadManager.shared.resumeAvailableDownloads()
			BrowserController.prewarmSharedProcess()
			let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
			source.setEventHandler {
				Task { @MainActor in
					for browser in BrowserWindowRegistry.shared.openBrowsers {
						for tab in browser.tabs where tab.id != browser.selectedTabID {
							tab.controller?.discardPreviewSnapshot()
							for peek in tab.peeks {
								peek.controller.discardPreviewSnapshot()
							}
						}
					}
				}
			}
			source.resume()
			memoryPressureSource = source
			BrowserWebPushManager.shared.drainPendingMessages()
			Task { @MainActor [weak self] in
				await Task.yield()
				guard let self, windows.isEmpty, miniWindows.isEmpty, !wasLaunchedForWebPush,
				      !authentication.wasLaunchedByAuthenticationServices else { return }
				openBrowserWindow()
			}
		}

		func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
			Task { @MainActor in
				let hasChanges = windows.contains { controller in
					controller.browser.tabs.contains { tab in
						tab.controller?.hasUnsavedChanges == true || tab.peeks.contains { $0.controller.hasUnsavedChanges }
					}
				}
				if hasChanges {
					let alert = BrowserWebsiteUI.alert(title: "Quit Astra?", message: "Some tabs contain changes that may not be saved.", confirm: "Quit")
					guard await BrowserWebsiteUI.present(alert, in: NSApp.keyWindow) == .alertFirstButtonReturn else {
						sender.reply(toApplicationShouldTerminate: false)
						return
					}
				}
				for controller in windows {
					await controller.browser.flushAndWaitForPersistence()
				}
				if let failure = windows.compactMap(\.browser.persistenceErrorDescription).first {
					let alert = BrowserWebsiteUI.alert(title: "Quit without saving?", message: failure, confirm: "Quit Without Saving")
					guard await BrowserWebsiteUI.present(alert, in: NSApp.keyWindow) == .alertFirstButtonReturn else {
						sender.reply(toApplicationShouldTerminate: false)
						return
					}
				}
				for controller in windows {
					for tab in controller.browser.tabs {
						tab.stopForClose()
					}
					if controller.browser.isPrivate {
						await controller.browser.session.endPrivateSession()
					}
				}
				await BrowserAuthenticationSessionHandler.shared.cancelAll()
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

		@objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
			guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
			      let url = URL(string: value) else { return }
			application(NSApp, open: [url])
		}

		func application(_: NSApplication, open urls: [URL]) {
			if urls.contains(where: { $0.absoluteString == "x-webkit-app-launch://1" }) {
				wasLaunchedForWebPush = true
				BrowserWebPushManager.shared.drainPendingMessages()
			}
			for url in urls where ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
				if Defaults[.miniAstraEnabled] {
					openMiniAstra(url: url)
				} else {
					open(url)
				}
			}
		}

		func requestQuit() {
			guard Defaults[.requireDoublePressToQuit] else {
				NSApplication.shared.terminate(nil)
				return
			}

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
		func openBrowserWindow(isPrivate: Bool = false) -> BrowserWindowController {
			let controller = BrowserWindowController(browser: Browser(isPrivate: isPrivate))
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
			BrowserAuthenticationSessionHandler.shared.activeBrowser ?? activeMiniWindow?.browser ?? BrowserWindowRegistry.shared.activeBrowser
		}

		private var activeMiniWindow: MiniAstraWindowController? {
			miniWindows.first { $0.window === NSApp.keyWindow }
		}

		private var mainWindow: BrowserWindowController {
			windows.first { $0.browser === BrowserWindowRegistry.shared.activeBrowser }
				?? windows.first
				?? openBrowserWindow()
		}

		func openMiniAstra(url: URL? = nil) {
			let controller = MiniAstraWindowController(url: url)
			controller.onClose = { [weak self, weak controller] in
				guard let self, let controller else { return }
				miniWindows.removeAll { $0 === controller }
			}
			controller.onPromote = { [weak self] tab in
				guard let self else { return }
				let destination = mainWindow
				#if DEBUG
					let webView = tab.controller?.webViewIfLoaded
				#endif
				destination.browser.adoptMiniTab(tab)
				destination.showWindow()
				NSApp.activate()
				#if DEBUG
					assert(destination.browser.selectedTab === tab)
					assert(destination.browser.selectedTab?.controller?.webViewIfLoaded === webView)
				#endif
			}
			miniWindows.append(controller)
			controller.showWindow()
		}

		@objc private func newMiniAstra(_: Any?) {
			openMiniAstra()
		}

		@discardableResult
		private func open(_ url: URL) -> WKWebView? {
			let controller: BrowserWindowController

			if let keyWindow = NSApp.keyWindow,
			   let existing = windows.first(where: { $0.window === keyWindow && !$0.browser.isPrivate })
			{
				controller = existing
			} else if let existing = windows.first(where: { !$0.browser.isPrivate }) {
				controller = existing
				existing.showWindow()
			} else {
				controller = openBrowserWindow()
			}

			let tab = controller.browser.addTab()
			tab.controller?.load(url)
			return tab.controller?.webView
		}

		// MARK: - Browser actions

		@objc private func newPrivateWindow(_: Any?) {
			openBrowserWindow(isPrivate: true)
		}

		@objc private func newWindow(_: Any?) {
			openBrowserWindow(isPrivate: activeBrowser?.isPrivate == true)
		}

		@objc private func newTab(_: Any?) {
			if activeMiniWindow != nil {
				openMiniAstra()
				return
			}
			let browser: Browser = if let activeBrowser {
				activeBrowser
			} else {
				openBrowserWindow().browser
			}
			browser.addTab()
		}

		@objc private func closeTab(_: Any?) {
			if BrowserAuthenticationSessionHandler.shared.activeBrowser != nil {
				NSApp.keyWindow?.performClose(nil)
				return
			}
			if let mini = activeMiniWindow {
				mini.window.performClose(nil)
				return
			}
			guard let browser = activeBrowser else { return }
			browser.closeTab(browser.selectedTabID)
		}

		@objc private func reopenLastClosedTab(_: Any?) {
			guard activeMiniWindow == nil else { return }
			activeBrowser?.reopenLastClosedTab()
		}

		@objc private func closeWindow(_: Any?) {
			NSApp.keyWindow?.performClose(nil)
		}

		@objc private func toggleSidebar(_: Any?) {
			guard activeMiniWindow == nil else { return }
			activeBrowser?.sidebarShown.toggle()
		}

		@objc private func editSpace(_: Any?) {
			let controller = mainWindow
			controller.browser.openInternalPage(.themeEditor)
			controller.showWindow()
		}

		@objc private func openSettings(_: Any?) {
			let controller = mainWindow
			controller.browser.openInternalPage(.settings)
			controller.showWindow()
		}

		@objc private func openHistory(_: Any?) {
			let controller = mainWindow
			controller.browser.openInternalPage(.history)
			controller.showWindow()
		}

		@objc private func openBookmarks(_: Any?) {
			activeBrowser?.openInternalPage(.bookmarks)
		}

		@objc private func openSavedBookmark(_ sender: NSMenuItem) {
			guard let browser = activeBrowser,
			      let id = sender.representedObject as? UUID,
			      let bookmark = browser.bookmarks.first(where: { $0.id == id })
			else { return }
			browser.openBookmark(bookmark)
		}

		#if DEBUG
			@objc private func openDebugPage(_ sender: NSMenuItem) {
				guard let id = sender.representedObject as? String,
				      let page = BrowserInternalPage(persistenceID: id)
				else { return }
				let browser = activeBrowser ?? openBrowserWindow().browser
				browser.openInternalPage(page, inNewTab: true)
			}
		#endif

		func menuWillOpen(_ menu: NSMenu) {
			guard menu.title == "Bookmarks" else { return }
			menu.removeAllItems()
			menu.addItem(item("Add Bookmark", action: #selector(addBookmark(_:)), key: "b"))
			menu.addItem(item("Open Bookmarks", action: #selector(openBookmarks(_:))))
			let bookmarks = activeBrowser?.bookmarks ?? []
			if !bookmarks.isEmpty {
				menu.addItem(.separator())
				for bookmark in bookmarks {
					let menuItem = item(bookmark.name, action: #selector(openSavedBookmark(_:)))
					menuItem.representedObject = bookmark.id
					menuItem.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: "Bookmark")
					menu.addItem(menuItem)
				}
			}
		}

		@objc private func showAbout(_: Any?) {
			let controller = mainWindow
			controller.showWindow()
			let browser = controller.browser
			browser.settingsPage = .about
			browser.openInternalPage(.settings)
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

		@objc private func importBrowsingData(_: Any?) {
			guard let browser = activeBrowser else { return }
			BrowserDataTransfer.importData(into: browser, window: NSApp.keyWindow)
		}

		@objc private func exportBrowsingData(_: Any?) {
			guard let browser = activeBrowser else { return }
			BrowserDataTransfer.exportData(from: browser, window: NSApp.keyWindow)
		}

		@objc private func exportBookmarks(_: Any?) {
			guard let browser = activeBrowser else { return }
			BrowserDataTransfer.exportData(from: browser, window: NSApp.keyWindow, bookmarksOnly: true)
		}

		@objc private func openFile(_: Any?) {
			let browser = activeBrowser ?? openBrowserWindow().browser
			BrowserDesktopCommands.openFile(in: browser, window: NSApp.keyWindow)
		}

		@objc private func printPage(_: Any?) {
			guard let controller = activeBrowser?.selectedTab?.activeController else { return }
			BrowserDesktopCommands.printPage(controller, window: NSApp.keyWindow)
		}

		@objc private func savePDF(_: Any?) {
			exportPage(.pdf)
		}

		@objc private func saveWebArchive(_: Any?) {
			exportPage(.webArchive)
		}

		@objc private func saveSource(_: Any?) {
			exportPage(.source)
		}

		private func exportPage(_ format: BrowserDesktopCommands.ExportFormat) {
			guard let controller = activeBrowser?.selectedTab?.activeController else { return }
			BrowserDesktopCommands.export(controller, format: format, window: NSApp.keyWindow)
		}

		@objc private func findInPage(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.showsFind = true
		}

		@objc private func findNext(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.findNext()
		}

		@objc private func findPrevious(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.findNext(backwards: true)
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

		@objc private func toggleWebInspector(_: Any?) {
			guard let webView = activeBrowser?.selectedTab?.activeController?.webViewIfLoaded,
			      webView.responds(to: NSSelectorFromString("_inspector")),
			      let inspector = webView.perform(NSSelectorFromString("_inspector"))?.takeUnretainedValue() as? NSObject
			else { return }

			let action = inspector.value(forKey: "visible") as? Bool == true ? "hide" : "show"
			inspector.perform(NSSelectorFromString(action))
		}

		@objc private func addBookmark(_: Any?) {
			activeBrowser?.bookmarkSelectedPage()
		}

		@objc private func duplicateTab(_: Any?) {
			if let mini = activeMiniWindow {
				openMiniAstra(url: mini.browser.selectedTab?.currentURL)
				return
			}
			guard let browser = activeBrowser else { return }
			browser.duplicateTab(browser.selectedTabID)
		}

		@objc private func copyURL(_: Any?) {
			guard let url = activeBrowser?.selectedTab?.activeController?.url else { return }
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(BrowserAddress.withoutCredentials(url).absoluteString, forType: .string)
		}

		@objc private func toggleFullScreen(_: Any?) {
			NSApp.keyWindow?.toggleFullScreen(nil)
		}

		@objc private func copyDiagnostics(_: Any?) {
			BrowserDiagnostics.copy(for: activeBrowser)
		}

		func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
			let pageActions: Set<Selector> = [
				#selector(printPage(_:)), #selector(savePDF(_:)), #selector(saveWebArchive(_:)),
				#selector(saveSource(_:)), #selector(findInPage(_:)), #selector(findNext(_:)),
				#selector(findPrevious(_:)), #selector(toggleWebInspector(_:)),
			]
			let dataActions: Set<Selector> = [#selector(importBrowsingData(_:)), #selector(exportBrowsingData(_:)), #selector(exportBookmarks(_:))]
			if let action = menuItem.action, pageActions.contains(action) {
				return activeBrowser?.selectedTab?.activeController?.committedURL != nil
			}
			if let action = menuItem.action, dataActions.contains(action) {
				return activeBrowser?.isPrivate == false && activeBrowser?.isMini == false
			}
			return true
		}

		// MARK: - Main menu

		private func installMainMenu() {
			let mainMenu = NSMenu()

			let appMenu = NSMenu()
			mainMenu.addItem(menuRoot("astra", submenu: appMenu))
			appMenu.addItem(item("About astra", action: #selector(showAbout(_:))))
			#if DEBUG
				appMenu.addItem(.separator())
				let heading = NSMenuItem(title: "Internal Pages", action: nil, keyEquivalent: "")
				heading.isEnabled = false
				appMenu.addItem(heading)
				for page in BrowserInternalPage.allCases {
					let menuItem = item(page.title, action: #selector(openDebugPage(_:)))
					menuItem.representedObject = page.persistenceID
					menuItem.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
					appMenu.addItem(menuItem)
				}
				appMenu.addItem(.separator())
			#endif
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
			let privateWindowItem = item("New Private Window", action: #selector(newPrivateWindow(_:)), key: "n")
			privateWindowItem.keyEquivalentModifierMask = [.command, .shift]
			fileMenu.addItem(privateWindowItem)
			fileMenu.addItem(item("New Tab", action: #selector(newTab(_:)), key: "t"))
			fileMenu.addItem(item("New Mini Astra", action: #selector(newMiniAstra(_:))))
			fileMenu.addItem(.separator())
			fileMenu.addItem(item("Close Tab", action: #selector(closeTab(_:)), key: "w"))
			fileMenu.addItem(item(
				"Reopen Closed Tab",
				action: #selector(reopenLastClosedTab(_:)),
				key: "t",
				modifiers: [.command, .shift]
			))
			fileMenu.addItem(item(
				"Close Window",
				action: #selector(closeWindow(_:)),
				key: "w",
				modifiers: [.command, .shift]
			))

			fileMenu.addItem(.separator())
			fileMenu.addItem(item("Open File…", action: #selector(openFile(_:)), key: "o"))
			fileMenu.addItem(item("Save Page as Web Archive…", action: #selector(saveWebArchive(_:)), key: "s", modifiers: [.command, .shift]))
			fileMenu.addItem(item("Export PDF…", action: #selector(savePDF(_:))))
			fileMenu.addItem(item("Save Page Source…", action: #selector(saveSource(_:))))
			fileMenu.addItem(item("Print…", action: #selector(printPage(_:)), key: "p"))
			fileMenu.addItem(.separator())
			fileMenu.addItem(item("Import Browsing Data…", action: #selector(importBrowsingData(_:))))
			fileMenu.addItem(item("Export Browsing Data…", action: #selector(exportBrowsingData(_:))))
			fileMenu.addItem(item("Export Bookmarks as HTML…", action: #selector(exportBookmarks(_:))))

			let editMenu = NSMenu(title: "Edit")
			mainMenu.addItem(menuRoot("Edit", submenu: editMenu))
			// Standard Edit actions dispatch through the responder chain by
			// name; NSSelectorFromString keeps them dynamic without tripping
			// the explicit-Selector-construction warning.
			editMenu.addItem(responderItem("Undo", action: NSSelectorFromString("undo:"), key: "z"))
			editMenu.addItem(responderItem(
				"Redo",
				action: NSSelectorFromString("redo:"),
				key: "z",
				modifiers: [.command, .shift]
			))
			editMenu.addItem(.separator())
			editMenu.addItem(responderItem("Cut", action: NSSelectorFromString("cut:"), key: "x"))
			editMenu.addItem(responderItem("Copy", action: NSSelectorFromString("copy:"), key: "c"))
			editMenu.addItem(responderItem("Paste", action: NSSelectorFromString("paste:"), key: "v"))
			editMenu.addItem(responderItem("Select All", action: NSSelectorFromString("selectAll:"), key: "a"))

			editMenu.addItem(.separator())
			editMenu.addItem(item("Find in Page…", action: #selector(findInPage(_:)), key: "f"))
			editMenu.addItem(item("Find Next", action: #selector(findNext(_:)), key: "g"))
			editMenu.addItem(item("Find Previous", action: #selector(findPrevious(_:)), key: "g", modifiers: [.command, .shift]))

			let viewMenu = NSMenu(title: "View")
			mainMenu.addItem(menuRoot("View", submenu: viewMenu))
			viewMenu.addItem(item("Toggle Sidebar", action: #selector(toggleSidebar(_:)), key: "s"))
			viewMenu.addItem(item("Edit Space", action: #selector(editSpace(_:))))
			viewMenu.addItem(.separator())
			viewMenu.addItem(item(
				"Web Inspector",
				action: #selector(toggleWebInspector(_:)),
				key: "i",
				modifiers: [.command, .option]
			))
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
			bookmarksMenu.delegate = self
			bookmarksMenu.addItem(item("Add Bookmark", action: #selector(addBookmark(_:)), key: "b"))
			bookmarksMenu.addItem(item("Open Bookmarks", action: #selector(openBookmarks(_:))))

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
			helpMenu.addItem(item("Copy Diagnostics", action: #selector(copyDiagnostics(_:))))
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
