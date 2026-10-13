#if os(macOS)
	import AppKit
	import Observation
	import SwiftUI

	@MainActor
	@Observable
	final class BrowserTabDragCoordinator {
		static let shared = BrowserTabDragCoordinator()

		private(set) var activeTabID: UUID?
		private(set) var screenPoint = CGPoint.zero
		@ObservationIgnored private var targets: [UUID: Target] = [:]
		@ObservationIgnored private weak var sourceBrowser: Browser?

		final class Target {
			weak var browser: Browser?
			let area: Browser.TabArea
			let spaceID: UUID?
			let beforeTabID: UUID?
			let frame: CGRect
			weak var window: NSWindow?
			let isWindowFallback: Bool

			init(
				browser: Browser,
				area: Browser.TabArea,
				spaceID: UUID?,
				beforeTabID: UUID?,
				frame: CGRect,
				window: NSWindow,
				isWindowFallback: Bool
			) {
				self.browser = browser
				self.area = area
				self.spaceID = spaceID
				self.beforeTabID = beforeTabID
				self.frame = frame
				self.window = window
				self.isWindowFallback = isWindowFallback
			}
		}

		func begin(_ id: UUID, from browser: Browser) {
			guard !browser.isPrivate, !browser.isMini, browser.tab(withID: id) != nil else {
				clearDrag()
				return
			}
			activeTabID = id
			sourceBrowser = browser
			screenPoint = NSEvent.mouseLocation
		}

		func update() {
			screenPoint = NSEvent.mouseLocation
		}

		func register(_ target: Target, id: UUID) {
			targets[id] = target
		}

		func unregister(_ id: UUID) {
			targets.removeValue(forKey: id)
		}

		func drop() {
			guard let activeTabID,
			      let sourceBrowser,
			      !sourceBrowser.isPrivate,
			      !sourceBrowser.isMini,
			      sourceBrowser.tab(withID: activeTabID) != nil
			else {
				clearDrag()
				return
			}
			let point = NSEvent.mouseLocation
			let target = targets.values
				.filter {
					$0.frame.contains(point)
						&& (!$0.isWindowFallback || $0.browser?.windowID != sourceBrowser.windowID)
				}
				.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
			if let target, let browser = target.browser,
			   !browser.isPrivate,
			   !browser.isMini,
			   browser.session === sourceBrowser.session
			{
				if browser !== sourceBrowser {
					browser.receiveSharedState(from: sourceBrowser)
				}
				guard browser.tab(withID: activeTabID) != nil else {
					clearDrag()
					return
				}
				browser.moveTab(
					activeTabID,
					to: target.area,
					in: target.spaceID,
					before: target.beforeTabID
				)
				browser.selectTab(activeTabID)
				if browser.windowID != BrowserWindowRegistry.shared.activeBrowserID {
					target.window?.makeKeyAndOrderFront(nil)
				}
				browser.flushPersistence()
			}
			clearDrag()
		}

		private func clearDrag() {
			activeTabID = nil
			sourceBrowser = nil
		}
	}

	struct BrowserDropZone: NSViewRepresentable {
		let browser: Browser
		let area: Browser.TabArea
		var spaceID: UUID?
		var beforeTabID: UUID?
		var isWindowFallback = false

		func makeNSView(context _: Context) -> DropView {
			DropView()
		}

		func updateNSView(_ view: DropView, context _: Context) {
			view.browser = browser
			view.area = area
			view.spaceID = spaceID
			view.beforeTabID = beforeTabID
			view.isWindowFallback = isWindowFallback
			view.updateTarget()
		}

		final class DropView: NSView {
			let id = UUID()
			weak var browser: Browser?
			var area: Browser.TabArea = .normal
			var spaceID: UUID?
			var beforeTabID: UUID?
			var isWindowFallback = false
			private var registeredTarget: BrowserTabDragCoordinator.Target?

			override func hitTest(_: NSPoint) -> NSView? {
				nil
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				updateTarget()
			}

			override func layout() {
				super.layout()
				updateTarget()
			}

			func updateTarget() {
				guard let browser, !browser.isPrivate, !browser.isMini, let window = unsafe window, !bounds.isEmpty else {
					registeredTarget = nil
					BrowserTabDragCoordinator.shared.unregister(id)
					return
				}
				let frame = window.convertToScreen(convert(bounds, to: nil))
				if let previous = registeredTarget,
				   previous.browser === browser, previous.window === window,
				   previous.area == area, previous.spaceID == spaceID,
				   previous.beforeTabID == beforeTabID, previous.frame == frame,
				   previous.isWindowFallback == isWindowFallback
				{
					return
				}
				let target = BrowserTabDragCoordinator.Target(
					browser: browser,
					area: area,
					spaceID: spaceID,
					beforeTabID: beforeTabID,
					frame: frame,
					window: window,
					isWindowFallback: isWindowFallback
				)
				registeredTarget = target
				BrowserTabDragCoordinator.shared.register(target, id: id)
			}

			deinit {
				let id = id
				Task { @MainActor in
					BrowserTabDragCoordinator.shared.unregister(id)
				}
			}
		}
	}
#endif

#if os(macOS)
	/// Distinct destinations allow macOS 27 SwiftUI reordering to move items both
	/// within and across the sidebar's three top-level areas and pinned folders.
	nonisolated enum SidebarTabCollection: Hashable, Sendable {
		case favourite
		case pinned
		case normal
		case folder(UUID)
		case todayGroup(String)
	}

	@MainActor
	@Observable
	final class BrowserSidebarTabSelection {
		private(set) var tabIDs: Set<UUID> = []
		private(set) var area: Browser.TabArea?
		private(set) var spaceID: UUID?
		private var anchorID: UUID?

		func contains(_ id: UUID, area: Browser.TabArea, spaceID: UUID) -> Bool {
			self.area == area && self.spaceID == spaceID && tabIDs.contains(id)
		}

		func orderedIDs(in ids: [UUID], area: Browser.TabArea, spaceID: UUID) -> [UUID] {
			guard self.area == area, self.spaceID == spaceID else { return [] }
			return ids.filter { tabIDs.contains($0) }
		}

		/// Returns true when the click should also activate the tab.
		@discardableResult
		func click(_ id: UUID, area: Browser.TabArea, spaceID: UUID, orderedIDs: [UUID], currentID: UUID?, modifiers: NSEvent.ModifierFlags) -> Bool {
			let command = modifiers.contains(.command)
			let shift = modifiers.contains(.shift)
			guard command || shift else {
				clear()
				anchorID = id
				return true
			}
			guard orderedIDs.contains(id) else { return false }
			if self.area != area || self.spaceID != spaceID {
				clear()
				self.area = area
				self.spaceID = spaceID
			}
			if shift {
				let anchor = anchorID.flatMap { orderedIDs.firstIndex(of: $0) }
					?? currentID.flatMap { orderedIDs.firstIndex(of: $0) }
					?? orderedIDs.firstIndex(of: id)!
				let clicked = orderedIDs.firstIndex(of: id)!
				let range = Set(orderedIDs[min(anchor, clicked) ... max(anchor, clicked)])
				if command {
					tabIDs.formUnion(range)
				} else {
					tabIDs = range
				}
				anchorID = orderedIDs[anchor]
			} else {
				if !tabIDs.insert(id).inserted {
					tabIDs.remove(id)
				}
				anchorID = id
			}
			return false
		}

		func clear() {
			tabIDs = []
			area = nil
			spaceID = nil
			anchorID = nil
		}
	}
#endif

#if os(iOS)
	import Foundation
	import Observation

	nonisolated enum SidebarTabCollection: Hashable, Sendable {
		case favourite
		case pinned
		case normal
		case folder(UUID)
		case todayGroup(String)
	}

	/// The macOS sidebar supplies real multi-selection; iOS rows do not.
	@MainActor
	@Observable
	final class BrowserSidebarTabSelection {
		var tabIDs: Set<UUID> = []
		func contains(_: UUID, area _: Browser.TabArea, spaceID _: UUID) -> Bool {
			false
		}

		func orderedIDs(in _: [UUID], area _: Browser.TabArea, spaceID _: UUID) -> [UUID] {
			[]
		}

		func clear() {}
	}
#endif
