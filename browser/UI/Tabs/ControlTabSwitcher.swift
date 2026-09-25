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

		func start() {
			guard eventMonitor == nil else { return }
			eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
				let isKeyDown = event.type == .keyDown
				let isTab = event.keyCode == 48
				let isEscape = event.keyCode == 53
				let isControlPressed = event.modifierFlags.contains(.control)
				let isShiftPressed = event.modifierFlags.contains(.shift)
				let isHandled = MainActor.assumeIsolated {
					self?.handle(
						isKeyDown: isKeyDown,
						isTab: isTab,
						isEscape: isEscape,
						isControlPressed: isControlPressed,
						isShiftPressed: isShiftPressed
					) ?? false
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
			let validTabIDs = Set(browser.tabs.map(\.id))
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
			isTab: Bool,
			isEscape: Bool,
			isControlPressed: Bool,
			isShiftPressed: Bool
		) -> Bool {
			if isCancelledUntilControlRelease {
				if !isControlPressed {
					isCancelledUntilControlRelease = false
				} else if isKeyDown, isTab {
					return true
				}
			}

			if isKeyDown {
				if isEscape, !candidateIDs.isEmpty {
					isCancelledUntilControlRelease = isControlPressed
					endSession()
					return true
				}
				guard isControlPressed, isTab else { return false }
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

			if !candidateIDs.isEmpty, !isControlPressed {
				if let highlightedTabID {
					browser.commitTabSwitch(to: highlightedTabID)
				}
				endSession()
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
