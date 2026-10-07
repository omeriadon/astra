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
	import SwiftUI
	import WebKit

	@MainActor
	final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
		private var windows: [BrowserWindowController] = []
		private var miniWindows: [MiniAstraWindowController] = []
		private var lastQuitAttempt: Date?
		private var terminationApprovalInFlight = false
		private var lastClosedNormalWindow: BrowserWindowRecord?
		private var wasLaunchedForWebPush = false
		private var startupWindowRestorationFinished = false
		private var queuedStartupURLs: [URL] = []
		private var shouldReopenAfterStartup = false
		private var memoryPressureSource: DispatchSourceMemoryPressure?

		private var pictureInPictureController: BrowserController? {
			for browser in allBrowsers {
				for tab in browser.tabs {
					if let controller = tab.controller,
					   controller.isPictureInPictureActive || controller.isEnteringPictureInPicture
					{
						return controller
					}
					if let controller = tab.peeks.map(\.controller).first(where: {
						$0.isPictureInPictureActive || $0.isEnteringPictureInPicture
					}) {
						return controller
					}
				}
			}
			return nil
		}

		private var allBrowsers: [Browser] {
			windows.map(\.browser) + miniWindows.map(\.browser)
		}

		func applicationWillFinishLaunching(_: Notification) {
			BrowserLog.info(.lifecycle, "app.will-finish-launching")
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
			BrowserController.addressPromptOwner = { [weak self] controller, webView, documentID in
				guard let self,
				      let browser = activeBrowser,
				      let keyWindow = NSApp.keyWindow,
				      BrowserKeyboardMenuPolicy.canPromptForAddressAction(
				      	isFocusedBrowser: keyWindow.isKeyWindow && activeBrowser === browser,
				      	isSelectedController: browser.selectedTab?.activeController === controller,
				      	isSameSession: browser.session === controller.session,
				      	isCurrentWebView: controller.webViewIfLoaded === webView,
				      	isSameNavigation: controller.navigationIdentifier == documentID,
				      	webViewMatchesOwnerWindow: webView.window == nil || webView.window === keyWindow
				      )
				else { return nil }
				return BrowserAddressPromptOwner(browser: browser, window: keyWindow)
			}
			BrowserWebPushManager.shared.openRequested = { [weak self] url in
				self?.open(url)
			}
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(newMiniAstra(_:)),
				name: MiniAstraShortcut.notification,
				object: nil
			)
			NSWorkspace.shared.notificationCenter.addObserver(
				self,
				selector: #selector(applicationWillSleep(_:)),
				name: NSWorkspace.willSleepNotification,
				object: NSWorkspace.shared
			)
			NSWorkspace.shared.notificationCenter.addObserver(
				self,
				selector: #selector(applicationDidWake(_:)),
				name: NSWorkspace.didWakeNotification,
				object: NSWorkspace.shared
			)
			MiniAstraShortcut.shared.update()
		}

		@objc private func applicationWillSleep(_: Notification) {
			BrowserLog.notice(.lifecycle, "system.will-sleep")
			for controller in windows {
				controller.saveWindowFrame()
			}
			for browser in allBrowsers where !browser.isPrivate && !browser.isMini {
				browser.flushPersistence()
			}
		}

		@objc private func applicationDidWake(_: Notification) {
			BrowserLog.notice(.lifecycle, "system.did-wake")
			guard let keyWindow = NSApp.keyWindow,
			      let browser = windows.first(where: { $0.window === keyWindow })?.browser else { return }
			BrowserWindowRegistry.shared.activate(browser)
		}

		func applicationDidFinishLaunching(_: Notification) {
			BrowserLog.info(.lifecycle, "app.did-finish-launching")
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
			BrowserWebsiteMonitoring.shared.start()
			BrowserController.prewarmSharedProcess()
			let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
			source.setEventHandler {
				Task { @MainActor in
					for browser in BrowserWindowRegistry.shared.openBrowsers {
						for tab in browser.tabs {
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
			Task { @MainActor [weak self] in
				await Task.yield()
				guard let self else { return }
				defer { finishStartupWindowRestoration() }
				guard !authentication.wasLaunchedByAuthenticationServices else { return }
				let persistence = try? BrowserPersistence()
				let records = await Task.detached(priority: .utility) {
					(try? persistence?.loadPersistedState()?.windowRecords) ?? []
				}.value
				BrowserWindowRegistry.shared.beginWindowRestoration(records)
				for record in records where !windows.contains(where: { $0.browser.windowID == record.windowID }) {
					openBrowserWindow(restorationRecord: record, showImmediately: false)
				}
				if windows.isEmpty, !wasLaunchedForWebPush {
					openBrowserWindow(showImmediately: false)
				}
				for controller in windows {
					while !controller.browser.isHydrationFinished {
						try? await Task.sleep(for: .milliseconds(25))
					}
				}
				for controller in windows {
					controller.showWindow()
				}
				if !windows.isEmpty {
					NSApp.activate()
				}
				BrowserWindowRegistry.shared.finishWindowRestoration()
			}
		}

		func applicationWillTerminate(_: Notification) {
			BrowserLog.notice(.lifecycle, "app.will-terminate", metadata: ["windows": String(BrowserWindowRegistry.shared.openBrowsers.count)])
			memoryPressureSource?.cancel()
			memoryPressureSource = nil
		}

		func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
			guard !terminationApprovalInFlight else { return .terminateLater }
			terminationApprovalInFlight = true
			Task { @MainActor in
				defer { terminationApprovalInFlight = false }
				let hasChanges = allBrowsers.contains { browser in
					browser.tabs.contains { tab in
						tab.controller?.hasUnsavedChanges == true || tab.peeks.contains { $0.controller.hasUnsavedChanges }
					}
				}
				let hasProtectedMedia = allBrowsers.contains { browser in
					browser.tabs.contains { tab in
						tab.controller?.requiresMediaTeardownConfirmation == true
							|| tab.peeks.contains { $0.controller.requiresMediaTeardownConfirmation }
					}
				}
				if hasChanges || hasProtectedMedia {
					let message = hasChanges && hasProtectedMedia
						? "Some tabs contain changes that may not be saved, and closing will stop media playback."
						: hasChanges ? "Some tabs contain changes that may not be saved." : "Quitting will stop media playback."
					let alert = BrowserWebsiteUI.alert(title: "Quit Astra?", message: message, confirm: "Quit")
					guard await BrowserWebsiteUI.present(alert, in: NSApp.keyWindow) == .alertFirstButtonReturn else {
						sender.reply(toApplicationShouldTerminate: false)
						return
					}
				}
				for controller in windows {
					controller.saveWindowFrame()
					await controller.browser.flushAndWaitForPersistence()
				}
				for controller in miniWindows {
					await controller.browser.flushAndWaitForPersistence()
				}
				if let failure = allBrowsers.compactMap(\.persistenceErrorDescription).first {
					let alert = BrowserWebsiteUI.alert(title: "Quit without saving?", message: failure, confirm: "Quit Without Saving")
					guard await BrowserWebsiteUI.present(alert, in: NSApp.keyWindow) == .alertFirstButtonReturn else {
						sender.reply(toApplicationShouldTerminate: false)
						return
					}
				}
				for browser in allBrowsers where !browser.isMini {
					await browser.markCleanShutdown()
				}
				for browser in allBrowsers {
					for tab in browser.tabs {
						tab.stopForClose(force: true)
					}
					if browser.isPrivate {
						await browser.session.endPrivateSession()
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
				guard startupWindowRestorationFinished else {
					shouldReopenAfterStartup = true
					return true
				}
				if let controller = windows.first {
					controller.showWindow()
				} else if let lastClosedNormalWindow {
					self.lastClosedNormalWindow = nil
					openBrowserWindow(restorationRecord: lastClosedNormalWindow)
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
				if startupWindowRestorationFinished {
					BrowserWebPushManager.shared.drainPendingMessages()
				}
			}
			for url in urls where ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
				openAfterStartupRestoration(url)
			}
		}

		private func openAfterStartupRestoration(_ url: URL) {
			BrowserLog.debug(.lifecycle, "startup.open-after-restoration", metadata: ["url": BrowserLog.url(url)])
			guard startupWindowRestorationFinished else {
				queuedStartupURLs.append(url)
				return
			}
			if Defaults[.miniAstraEnabled] {
				openMiniAstra(url: url)
			} else {
				open(url)
			}
		}

		private func finishStartupWindowRestoration() {
			BrowserWindowRegistry.shared.finishWindowRestoration()
			startupWindowRestorationFinished = true
			BrowserWebPushManager.shared.drainPendingMessages()
			if shouldReopenAfterStartup {
				shouldReopenAfterStartup = false
				if let controller = windows.first {
					controller.showWindow()
				} else if let lastClosedNormalWindow {
					self.lastClosedNormalWindow = nil
					openBrowserWindow(restorationRecord: lastClosedNormalWindow)
				} else if !wasLaunchedForWebPush {
					openBrowserWindow()
				}
			}
			let urls = queuedStartupURLs
			queuedStartupURLs.removeAll()
			for url in urls {
				openAfterStartupRestoration(url)
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
				activeBrowser?.isAboutToQuit = true
			}
		}

		@discardableResult
		func openBrowserWindow(
			isPrivate: Bool = false,
			restorationRecord: BrowserWindowRecord? = nil,
			showImmediately: Bool = true
		) -> BrowserWindowController {
			BrowserLog.info(.lifecycle, "window.open-request", metadata: ["private": String(isPrivate), "restoring": String(restorationRecord != nil), "show_immediately": String(showImmediately)])
			let record = isPrivate ? nil : restorationRecord
			let controller = BrowserWindowController(browser: Browser(isPrivate: isPrivate, windowRecord: record))
			controller.onClose = { [weak self, weak controller] in
				guard let self, let controller else { return }
				if !controller.browser.isPrivate {
					lastClosedNormalWindow = BrowserWindowRecord(
						windowID: controller.browser.windowID,
						tabIDs: controller.browser.tabs.map(\.id),
						selectedTabID: controller.browser.selectedTabID,
						frame: controller.browser.savedWindowFrame
					)
				}
				windows.removeAll { $0 === controller }
			}

			windows.append(controller)
			if showImmediately {
				controller.showWindow()
				NSApp.activate()
			}
			return controller
		}

		private var focusedBrowser: Browser? {
			focusedBrowserWindow?.browser ?? focusedMiniWindow?.browser
		}

		private var activeAuthenticationBrowser: Browser? {
			BrowserAuthenticationSessionHandler.shared.activeBrowser
		}

		private var activeBrowser: Browser? {
			activeAuthenticationBrowser ?? focusedBrowser
		}

		private var focusedBrowserWindow: BrowserWindowController? {
			windows.first {
				BrowserKeyboardMenuPolicy.ownsFocusedTarget(
					isKeyWindow: $0.window.isKeyWindow,
					matchesKeyWindow: $0.window === NSApp.keyWindow
				)
			}
		}

		private var focusedMiniWindow: MiniAstraWindowController? {
			miniWindows.first {
				BrowserKeyboardMenuPolicy.ownsFocusedTarget(
					isKeyWindow: $0.window.isKeyWindow,
					matchesKeyWindow: $0.window === NSApp.keyWindow
				)
			}
		}

		private var activeMiniWindow: MiniAstraWindowController? {
			focusedMiniWindow
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
			openBrowserWindow(isPrivate: activeAuthenticationBrowser == nil && activeBrowser?.isPrivate == true)
		}

		@objc private func newTab(_: Any?) {
			if activeAuthenticationBrowser != nil {
				openBrowserWindow()
				return
			}
			if activeMiniWindow != nil {
				openMiniAstra()
				return
			}
			let browser: Browser = if let activeBrowser {
				activeBrowser
			} else {
				openBrowserWindow().browser
			}
			browser.requestNewTab()
		}

		@objc private func closeTab(_: Any?) {
			if let browser = activeBrowser, browser.showsQuickSearch {
				browser.dismissQuickSearch()
				return
			}
			if activeAuthenticationBrowser != nil {
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
			guard activeMiniWindow == nil, activeAuthenticationBrowser == nil else { return }
			activeBrowser?.reopenLastClosedTab()
		}

		@objc private func closeWindow(_: Any?) {
			NSApp.keyWindow?.performClose(nil)
		}

		@objc private func toggleSidebar(_: Any?) {
			guard activeMiniWindow == nil else { return }
			activeBrowser?.sidebarShown.toggle()
		}

		@objc private func toggleTopBar(_: Any?) {
			guard let browser = activeBrowser, !browser.isMini else { return }
			NotificationCenter.default.post(name: .toggleBrowserTopBar, object: browser.windowID)
		}

		@objc private func toggleAISidebar(_: Any?) {
			guard let browser = activeBrowser, browser.canShowAISidebar else { return }
			withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.3)) {
				browser.showsAISidebar.toggle()
			}
		}

		@objc private func editSpace(_: Any?) {
			guard activeAuthenticationBrowser == nil else { return }
			activeBrowser?.openInternalPage(.themeEditor)
		}

		@objc private func openSettings(_: Any?) {
			let browser: Browser = if activeAuthenticationBrowser == nil, let focusedBrowserWindow {
				focusedBrowserWindow.browser
			} else {
				openBrowserWindow().browser
			}
			browser.openInternalPage(.settings)
		}

		@objc private func openHistory(_: Any?) {
			guard activeAuthenticationBrowser == nil else { return }
			activeBrowser?.openInternalPage(.history)
		}

		@objc private func showDownloads(_: Any?) {
			guard activeAuthenticationBrowser == nil,
			      let browser = activeBrowser,
			      !browser.isMini else { return }
			NotificationCenter.default.post(name: .showBrowserDownloads, object: browser.windowID)
		}

		@objc private func openBookmarks(_: Any?) {
			guard activeAuthenticationBrowser == nil else { return }
			activeBrowser?.openInternalPage(.bookmarks)
		}

		@objc private func openSavedBookmark(_ sender: NSMenuItem) {
			guard let browser = activeBrowser,
			      activeAuthenticationBrowser == nil,
			      !browser.isPrivate,
			      let id = sender.representedObject as? UUID,
			      let bookmark = browser.bookmarks.first(where: { $0.id == id })
			else { return }
			browser.openBookmark(bookmark)
		}

		@objc private func openHistoryVisit(_ sender: NSMenuItem) {
			guard let browser = activeBrowser,
			      activeAuthenticationBrowser == nil,
			      let id = sender.representedObject as? UUID,
			      let visit = browser.historyVisits.first(where: { $0.id == id })
			else { return }
			browser.openHistoryURL(visit.url, inBackground: false)
		}

		#if DEBUG
			@objc private func openDebugPage(_ sender: NSMenuItem) {
				guard let id = sender.representedObject as? String,
				      let page = BrowserInternalPage(persistenceID: id)
				else { return }
				let browser: Browser = if activeAuthenticationBrowser == nil {
					activeBrowser ?? openBrowserWindow().browser
				} else {
					openBrowserWindow().browser
				}
				browser.openInternalPage(page, inNewTab: true)
			}
		#endif

		func menuWillOpen(_ menu: NSMenu) {
			if menu.title == "Bookmarks" {
				for item in menu.items where item.tag == 17018 {
					menu.removeItem(item)
				}
				let bookmarks = activeAuthenticationBrowser == nil && activeBrowser?.isPrivate != true
					? activeBrowser?.bookmarks ?? []
					: []
				if !bookmarks.isEmpty {
					let separator = NSMenuItem.separator()
					separator.tag = 17018
					menu.addItem(separator)
					for bookmark in bookmarks {
						let menuItem = item(bookmark.name, action: #selector(openSavedBookmark(_:)))
						menuItem.representedObject = bookmark.id
						menuItem.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: "Bookmark")
						menuItem.tag = 17018
						menu.addItem(menuItem)
					}
				}
				return
			}
			if menu.title == "Navigation" {
				for item in menu.items where item.tag == 17017 {
					menu.removeItem(item)
				}
				let visits = activeAuthenticationBrowser == nil
					? activeBrowser.map { Array($0.recentHistoryVisits.prefix(10)) } ?? []
					: []
				if !visits.isEmpty {
					let separator = NSMenuItem.separator()
					separator.tag = 17017
					let insertionIndex = (menu.items.firstIndex { $0.action == #selector(openHistory(_:)) } ?? 0) + 1
					menu.insertItem(separator, at: insertionIndex)
					var nextIndex = insertionIndex + 1
					for visit in visits {
						let title = visit.title.isEmpty ? (visit.url.host ?? visit.url.absoluteString) : visit.title
						let menuItem = item(title, action: #selector(openHistoryVisit(_:)))
						menuItem.representedObject = visit.id
						menuItem.tag = 17017
						menu.insertItem(menuItem, at: nextIndex)
						nextIndex += 1
					}
				}
				return
			}
			guard menu.title == "Window" else { return }
			for item in menu.items where item.tag == 17019 {
				menu.removeItem(item)
			}
			let browserWindows = windows.map { ($0.browser, $0.window) }
			let miniWindows = miniWindows.map { ($0.browser, $0.window as NSWindow) }
			for (index, entry) in (browserWindows + miniWindows).enumerated() {
				let (browser, window) = entry
				let title = browser.isMini ? "Mini Astra" : browser.isPrivate ? "Private Window" : "Astra Window"
				let menuItem = item("\(title) \(index + 1)", action: #selector(activateWindow(_:)))
				menuItem.representedObject = browser.windowID
				menuItem.state = window === NSApp.keyWindow ? .on : .off
				menuItem.tag = 17019
				menu.addItem(menuItem)
			}
		}

		@objc private func activateWindow(_ sender: NSMenuItem) {
			guard let id = sender.representedObject as? UUID else { return }
			if let controller = windows.first(where: { $0.browser.windowID == id }) {
				controller.showWindow()
			} else if let controller = miniWindows.first(where: { $0.browser.windowID == id }) {
				controller.showWindow()
			}
		}

		@objc private func showAbout(_: Any?) {
			let browser: Browser = if activeAuthenticationBrowser == nil, let focusedBrowserWindow {
				focusedBrowserWindow.browser
			} else {
				openBrowserWindow().browser
			}
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
			let browser: Browser = if activeAuthenticationBrowser == nil {
				activeBrowser ?? openBrowserWindow().browser
			} else {
				openBrowserWindow().browser
			}
			BrowserDesktopCommands.openFile(in: browser, window: NSApp.keyWindow)
		}

		@objc private func printPage(_: Any?) {
			guard let controller = activeBrowser?.selectedTab?.activeController else { return }
			BrowserDesktopCommands.printPage(controller, window: NSApp.keyWindow)
		}

		@objc private func sharePage(_: Any?) {
			guard let browser = activeBrowser,
			      let controller = browser.selectedTab?.activeController
			else { return }
			BrowserDesktopCommands.sharePage(controller, in: browser, window: NSApp.keyWindow)
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

		@objc private func showWebInspector(_: Any?) {
			guard activeAuthenticationBrowser == nil,
			      let controller = activeBrowser?.selectedTab?.activeController else { return }
			BrowserDesktopCommands.showWebInspector(controller)
		}

		private func exportPage(_ format: BrowserDesktopCommands.ExportFormat) {
			guard let browser = activeBrowser,
			      let controller = browser.selectedTab?.activeController
			else { return }
			BrowserDesktopCommands.export(controller, in: browser, format: format, window: NSApp.keyWindow)
		}

		@objc private func findInPage(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.presentFind()
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

		@objc private func toggleReader(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.toggleReader()
		}

		@objc private func enterPictureInPicture(_: Any?) {
			activeBrowser?.selectedTab?.activeController?.enterPictureInPicture()
		}

		@objc private func showPictureInPictureTab(_: Any?) {
			pictureInPictureController?.returnToPictureInPictureSource()
		}

		@objc private func addBookmark(_: Any?) {
			guard activeAuthenticationBrowser == nil else { return }
			activeBrowser?.bookmarkSelectedPage()
		}

		@objc private func duplicateTab(_: Any?) {
			guard activeAuthenticationBrowser == nil else { return }
			if let mini = activeMiniWindow {
				openMiniAstra(url: mini.browser.selectedTab?.currentURL)
				return
			}
			guard let browser = activeBrowser else { return }
			browser.duplicateTab(browser.selectedTabID)
		}

		@objc private func copyURL(_: Any?) {
			guard let browser = activeBrowser, let tab = browser.selectedTab else { return }
			browser.copyURL(for: tab)
		}

		@objc private func toggleFullScreen(_: Any?) {
			NSApp.keyWindow?.toggleFullScreen(nil)
		}

		@objc private func copyDiagnostics(_: Any?) {
			BrowserDiagnostics.copy(for: activeBrowser)
		}

		func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
			let pageActions: Set<Selector> = [
				#selector(printPage(_:)), #selector(sharePage(_:)), #selector(savePDF(_:)), #selector(saveWebArchive(_:)),
				#selector(saveSource(_:)), #selector(findInPage(_:)), #selector(findNext(_:)),
				#selector(findPrevious(_:)), #selector(showWebInspector(_:)),
			]
			let dataActions: Set<Selector> = [#selector(importBrowsingData(_:)), #selector(exportBrowsingData(_:)), #selector(exportBookmarks(_:))]
			if let action = menuItem.action, pageActions.contains(action) {
				guard let controller = activeBrowser?.selectedTab?.activeController,
				      activeBrowser?.selectedTab?.internalPage == nil,
				      controller.committedURL != nil,
				      controller.navigationFailure == nil,
				      !controller.isLoading
				else { return false }
				return true
			}
			let browserActions: Set<Selector> = [
				#selector(editSpace(_:)), #selector(openHistory(_:)),
				#selector(openBookmarks(_:)),
				#selector(duplicateTab(_:)),
			]
			if let action = menuItem.action, browserActions.contains(action) {
				return activeAuthenticationBrowser == nil && activeBrowser != nil
			}
			if menuItem.action == #selector(openSettings(_:)) {
				return true
			}
			if menuItem.action == #selector(openLocation(_:)) {
				return activeBrowser != nil
			}
			if menuItem.action == #selector(toggleAISidebar(_:)) {
				return activeBrowser?.canShowAISidebar == true && Defaults[.aiFeaturesEnabled] && Defaults[.aiSidebar]
			}
			if menuItem.action == #selector(toggleTopBar(_:)) {
				return activeBrowser?.isMini == false
			}
			if menuItem.action == #selector(toggleSidebar(_:)) {
				return activeBrowser?.isMini == false
			}
			if menuItem.action == #selector(goBack(_:)) {
				return activeBrowser?.selectedTab?.activeController?.canGoBack == true
			}
			if menuItem.action == #selector(goForward(_:)) {
				return activeBrowser?.selectedTab?.activeController?.canGoForward == true
			}
			if menuItem.action == #selector(reload(_:)) || menuItem.action == #selector(forceReload(_:)) {
				guard let controller = activeBrowser?.selectedTab?.activeController else { return false }
				return controller.url != nil || controller.navigationFailure != nil
			}
			if menuItem.action == #selector(showDownloads(_:)) {
				return activeAuthenticationBrowser == nil && activeBrowser?.isMini == false
			}
			if menuItem.action == #selector(reopenLastClosedTab(_:)) {
				return BrowserKeyboardMenuPolicy.canReopenLastClosedTab(
					isFocusedBrowser: activeBrowser != nil,
					isMini: activeBrowser?.isMini == true,
					isAuthenticationSession: activeAuthenticationBrowser != nil,
					hasClosedTab: activeBrowser?.closedHistoryTabs.isEmpty == false
				)
			}
			if menuItem.action == #selector(addBookmark(_:)) {
				return activeAuthenticationBrowser == nil && activeBrowser?.canBookmarkSelectedPage == true
			}
			if menuItem.action == #selector(openSavedBookmark(_:)) {
				return activeAuthenticationBrowser == nil && activeBrowser?.isPrivate == false
			}
			if menuItem.action == #selector(openHistoryVisit(_:)) {
				guard activeAuthenticationBrowser == nil,
				      let browser = activeBrowser,
				      let id = menuItem.representedObject as? UUID else { return false }
				return browser.historyVisits.contains(where: { $0.id == id })
			}
			if menuItem.action == #selector(closeTab(_:)) {
				return activeBrowser != nil || activeMiniWindow != nil
			}
			if menuItem.action == #selector(closeWindow(_:)) || menuItem.action == #selector(toggleFullScreen(_:)) {
				return NSApp.keyWindow != nil
			}
			if menuItem.action == #selector(zoomIn(_:)) {
				return BrowserKeyboardMenuPolicy.canZoomIn(activeBrowser?.selectedTab?.activeController?.pageZoom)
			}
			if menuItem.action == #selector(zoomOut(_:)) {
				return BrowserKeyboardMenuPolicy.canZoomOut(activeBrowser?.selectedTab?.activeController?.pageZoom)
			}
			if menuItem.action == #selector(actualSize(_:)) {
				return BrowserKeyboardMenuPolicy.canResetZoom(activeBrowser?.selectedTab?.activeController?.pageZoom)
			}
			if menuItem.action == #selector(copyURL(_:)) {
				return BrowserKeyboardMenuPolicy.canCopyURL(activeBrowser?.selectedTab?.copyableURL)
			}
			if menuItem.action == #selector(toggleReader(_:)) {
				let controller = activeBrowser?.selectedTab?.activeController
				menuItem.title = controller?.readerHTML == nil ? "Show Reader" : "Hide Reader"
				return activeAuthenticationBrowser == nil
					&& activeBrowser?.selectedTab?.internalPage == nil
					&& controller?.isPreparingReader == false
					&& (controller?.isReaderAvailable == true || controller?.readerHTML != nil)
			}
			if menuItem.action == #selector(enterPictureInPicture(_:)) {
				guard activeAuthenticationBrowser == nil,
				      let controller = activeBrowser?.selectedTab?.activeController else { return false }
				return controller.canEnterPictureInPicture
					&& !controller.isPictureInPictureActive
					&& !controller.isEnteringPictureInPicture
			}
			if menuItem.action == #selector(showPictureInPictureTab(_:)) {
				return pictureInPictureController != nil
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
			fileMenu.addItem(item("Share Page…", action: #selector(sharePage(_:))))
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
			viewMenu.addItem(item("Show Reader", action: #selector(toggleReader(_:)), key: "r", modifiers: [.command, .option]))
			viewMenu.addItem(item("Toggle Sidebar", action: #selector(toggleSidebar(_:)), key: "s"))
			viewMenu.addItem(item("Toggle Top Bar", action: #selector(toggleTopBar(_:)), key: "d"))
			viewMenu.addItem(item("Toggle AI Sidebar", action: #selector(toggleAISidebar(_:)), key: "l", modifiers: [.command, .option]))
			viewMenu.addItem(item("Edit Space", action: #selector(editSpace(_:))))
			viewMenu.addItem(.separator())
			viewMenu.addItem(item(
				"Web Inspector",
				action: #selector(showWebInspector(_:)),
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
			navigationMenu.delegate = self
			navigationMenu.addItem(item("History", action: #selector(openHistory(_:)), key: "y"))
			navigationMenu.addItem(.separator())
			navigationMenu.addItem(item("Show Downloads", action: #selector(showDownloads(_:)), key: "j"))
			navigationMenu.addItem(item("Open Location", action: #selector(openLocation(_:)), key: "l"))
			navigationMenu.addItem(item("Back", action: #selector(goBack(_:)), key: "["))
			navigationMenu.addItem(item("Forward", action: #selector(goForward(_:)), key: "]"))
			navigationMenu.addItem(item("Enter Picture in Picture", action: #selector(enterPictureInPicture(_:))))
			navigationMenu.addItem(item("Show Picture in Picture Tab", action: #selector(showPictureInPictureTab(_:))))
			navigationMenu.addItem(.separator())
			navigationMenu.addItem(item("Reload", action: #selector(reload(_:)), key: "r"))
			navigationMenu.addItem(item("Force Reload", action: #selector(forceReload(_:)), key: "r", modifiers: [.command, .shift]))
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
			tabMenu.addItem(item("Duplicate Tab", action: #selector(duplicateTab(_:)), key: "d", modifiers: [.command, .shift]))
			tabMenu.addItem(item(
				"Copy URL",
				action: #selector(copyURL(_:)),
				key: "c",
				modifiers: [.option]
			))

			let windowMenu = NSMenu(title: "Window")
			mainMenu.addItem(menuRoot("Window", submenu: windowMenu))
			windowMenu.delegate = self
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
