#if os(macOS)
	import AppKit
	import Observation
	import SwiftUI

	@MainActor
	@Observable
	final class ControlTabSwitcher {
		private(set) var candidateIDs: [UUID] = []
		private(set) var highlightedTabID: UUID?
		private(set) var isPreviewVisible = false
		private var visibleCandidateCount = 1

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
						keyCode: event.keyCode,
						isEscape: isEscape,
						isControlPressed: isControlPressed,
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
			// No active switch session: avoid rebuilding tab membership for
			// every background mutation in every open window.
			guard !candidateIDs.isEmpty else { return }
			let validTabIDs = Set(browser.visibleTabs.map(\.id))
			candidateIDs.removeAll { !validTabIDs.contains($0) }
			guard !candidateIDs.isEmpty else {
				endSession()
				return
			}
			if let highlightedTabID, !validTabIDs.contains(highlightedTabID) {
				self.highlightedTabID = candidateIDs[0]
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

		func setVisibleCandidateCount(_ count: Int) {
			visibleCandidateCount = max(1, count)
		}

		private func handle(
			isKeyDown: Bool,
			keyCode: UInt16,
			isEscape: Bool,
			isControlPressed: Bool,
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
					sessionForward = keyCode == 48
					let order = browser.switchCandidates(forward: sessionForward)
					guard !order.isEmpty else { return true }
					candidateIDs = order
					highlightedTabID = order[0]
					previewTask = Task { @MainActor [weak self] in
						try? await Task.sleep(for: .milliseconds(200))
						guard !Task.isCancelled, let self, !candidateIDs.isEmpty else { return }
						isPreviewVisible = true
					}
				} else {
					let cycleCount = min(candidateIDs.count, visibleCandidateCount)
					let visibleIDs = candidateIDs.prefix(cycleCount)
					let currentIndex = visibleIDs.firstIndex(of: highlightedTabID ?? candidateIDs[0]) ?? 0
					let isForward = keyCode == 48
					let step = isForward == sessionForward ? 1 : -1
					highlightedTabID = candidateIDs[(currentIndex + step + cycleCount) % cycleCount]
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
			isPreviewVisible = false
		}
	}

#endif
