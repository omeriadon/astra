#if os(macOS)
	import AppKit
	import Observation
	import SwiftUI

	@MainActor
	@Observable
	final class ControlTabSwitcher {
		private(set) var candidateIDs: [UUID] = []
		private(set) var highlightedTabID: UUID?
		private(set) var candidateWindowAnchorID: UUID?
		private(set) var isPreviewVisible = false

		@ObservationIgnored
		private let browser: Browser
		@ObservationIgnored
		private weak var window: NSWindow?
		@ObservationIgnored
		private var eventMonitor: Any?
		@ObservationIgnored
		private var previewTask: Task<Void, Never>?
		@ObservationIgnored
		private var sessionForward = true
		@ObservationIgnored
		private var isCancelledUntilControlRelease = false

		init(browser: Browser) {
			self.browser = browser
		}

		func setWindow(_ window: NSWindow?) {
			self.window = window
		}

		func start() {
			guard !browser.isMini, eventMonitor == nil else { return }
			eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
				let isKeyDown = event.type == .keyDown
				let isEscape = event.keyCode == 53
				let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
				let isControlPressed = modifiers.contains(.control)
				let isShiftPressed = modifiers.contains(.shift)
				let hasDisallowedModifiers = modifiers.contains(.command) || modifiers.contains(.option)
				let isHandled = MainActor.assumeIsolated {
					guard let self else { return false }
					let isFocusedWindow = BrowserKeyboardMenuPolicy.ownsFocusedTarget(
						isKeyWindow: self.window?.isKeyWindow == true,
						matchesKeyWindow: self.window === NSApp.keyWindow
					)
					let hasMarkedText = (self.window?.firstResponder as? NSTextInputClient)?.hasMarkedText() == true
					let ownsTabSwitch = BrowserKeyboardMenuPolicy.ownsTabSwitch(
						isFocusedWindow: isFocusedWindow,
						hasMarkedText: hasMarkedText,
						isKeyDown: isKeyDown,
						keyCode: event.keyCode,
						modifiers: modifiers
					)
					return self.handle(
						isKeyDown: isKeyDown,
						isEscape: isEscape,
						isControlPressed: isControlPressed,
						isShiftPressed: isShiftPressed,
						hasDisallowedModifiers: hasDisallowedModifiers,
						hasMarkedText: hasMarkedText,
						ownsTabSwitch: ownsTabSwitch
					)
				}
				return isHandled ? nil : event
			}
		}

		func stop() {
			if let eventMonitor {
				NSEvent.removeMonitor(eventMonitor)
				self.eventMonitor = nil
			}
			previewTask?.cancel()
			previewTask = nil
			isCancelledUntilControlRelease = false
			endSession()
		}

		func tabsDidChange() {
			let validTabIDs = Set(browser.visibleTabs.map(\.id))
			candidateIDs.removeAll { !validTabIDs.contains($0) }
			guard !candidateIDs.isEmpty else {
				endSession()
				return
			}
			if let highlightedTabID, !validTabIDs.contains(highlightedTabID) {
				self.highlightedTabID = candidateIDs[0]
			}
			if let candidateWindowAnchorID, !validTabIDs.contains(candidateWindowAnchorID) {
				self.candidateWindowAnchorID = highlightedTabID ?? candidateIDs[0]
			}
		}

		func select(_ tabID: UUID) {
			guard candidateIDs.contains(tabID) else { return }
			browser.commitTabSwitch(to: tabID)
			isCancelledUntilControlRelease = NSEvent.modifierFlags.contains(.control)
			endSession()
		}

		func highlight(_ tabID: UUID) {
			guard candidateIDs.contains(tabID) else { return }
			highlightedTabID = tabID
		}

		private func handle(
			isKeyDown: Bool,
			isEscape: Bool,
			isControlPressed: Bool,
			isShiftPressed: Bool,
			hasDisallowedModifiers: Bool,
			hasMarkedText: Bool,
			ownsTabSwitch: Bool
		) -> Bool {
			guard BrowserKeyboardMenuPolicy.ownsFocusedTarget(
				isKeyWindow: window?.isKeyWindow == true,
				matchesKeyWindow: window === NSApp.keyWindow
			) else {
				if !candidateIDs.isEmpty {
					endSession()
				}
				return false
			}
			if isKeyDown, hasMarkedText {
				return false
			}
			if isCancelledUntilControlRelease {
				if !isControlPressed {
					isCancelledUntilControlRelease = false
				} else if ownsTabSwitch {
					return true
				}
			}
			if !isKeyDown, !isControlPressed, !candidateIDs.isEmpty {
				if let highlightedTabID {
					browser.commitTabSwitch(to: highlightedTabID)
				}
				endSession()
			}
			guard !hasDisallowedModifiers else { return false }

			if isKeyDown {
				if isEscape, !candidateIDs.isEmpty {
					isCancelledUntilControlRelease = isControlPressed
					endSession()
					return true
				}
				guard ownsTabSwitch else { return false }
				if candidateIDs.isEmpty {
					sessionForward = !isShiftPressed
					let order = browser.switchCandidates(forward: sessionForward)
					guard !order.isEmpty else { return true }
					candidateIDs = order
					highlightedTabID = order[0]
					candidateWindowAnchorID = order[0]
					previewTask = Task { @MainActor [weak self] in
						try? await Task.sleep(for: .milliseconds(200))
						guard !Task.isCancelled, let self, !candidateIDs.isEmpty else { return }
						isPreviewVisible = true
					}
				} else {
					let currentIndex = candidateIDs.firstIndex(of: highlightedTabID ?? candidateIDs[0]) ?? 0
					let isForward = !isShiftPressed
					let step = isForward == sessionForward ? 1 : -1
					highlightedTabID = candidateIDs[(currentIndex + step + candidateIDs.count) % candidateIDs.count]
					candidateWindowAnchorID = highlightedTabID
				}
				return true
			}
			return false
		}

		private func endSession() {
			previewTask?.cancel()
			previewTask = nil
			candidateIDs = []
			highlightedTabID = nil
			candidateWindowAnchorID = nil
			isPreviewVisible = false
		}
	}

#endif
