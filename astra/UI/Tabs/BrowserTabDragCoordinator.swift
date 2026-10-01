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
				guard let browser, !browser.isPrivate, !browser.isMini, let window, !bounds.isEmpty else {
					BrowserTabDragCoordinator.shared.unregister(id)
					return
				}
				let frame = window.convertToScreen(convert(bounds, to: nil))
				BrowserTabDragCoordinator.shared.register(
					.init(
						browser: browser,
						area: area,
						spaceID: spaceID,
						beforeTabID: beforeTabID,
						frame: frame,
						window: window,
						isWindowFallback: isWindowFallback
					),
					id: id
				)
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
