import Foundation
import Observation
import SwiftUI
import WebKit
#if os(macOS)
	import AppKit
#endif

@MainActor
@Observable
final class BrowserPeek: Identifiable {
	let id: UUID
	let depth: Int
	let source: UnitPoint
	/// Native UI activations use screen coordinates, independent of the parent webview.
	let activationScreenPoint: CGPoint?
	let controller: BrowserController
	var hasPresented: Bool
	var isPresented: Bool
	var isDismissing = false
	let easelQuote: BrowserEaselQuote?

	var openPeek: OpenPeek {
		OpenPeek(
			id: id,
			depth: depth,
			sourceX: Double(source.x),
			sourceY: Double(source.y),
			url: controller.url.map(BrowserAddress.withoutCredentials),
			history: controller.history.map(BrowserAddress.withoutCredentials),
			historyIndex: controller.historyIndex,
			pageZoom: controller.pageZoom,
			scrollPosition: controller.scrollPosition,
			easelQuote: easelQuote
		)
	}

	init(
		url: URL? = nil,
		depth: Int,
		source: UnitPoint,
		activationScreenPoint: CGPoint? = nil,
		parentZoom: Double,
		zoomsOut: Bool,
		session: BrowserWebSession? = nil,
		existingController: BrowserController? = nil,
		easelQuote: BrowserEaselQuote? = nil
	) {
		id = UUID()
		self.easelQuote = easelQuote
		self.depth = depth
		self.source = source
		self.activationScreenPoint = activationScreenPoint
		controller = existingController ?? BrowserController(initialURL: url, session: session, scrollPosition: .zero)
		controller.easelQuoteHighlight = easelQuote
		hasPresented = false
		isPresented = false

		if zoomsOut {
			controller.pageZoom = parentZoom * (depth == 1 ? 0.95 : 0.85)
		} else {
			controller.pageZoom = parentZoom
		}
	}

	/// Capture during the action, never after asynchronous work or from a stale cursor.
	static func currentActivationScreenPoint() -> CGPoint? {
		#if os(macOS)
			guard let event = NSApp.currentEvent,
			      event.type == .leftMouseDown || event.type == .leftMouseUp,
			      ProcessInfo.processInfo.systemUptime - event.timestamp < 0.5,
			      let window = unsafe event.window else { return nil }
			return window.convertPoint(toScreen: event.locationInWindow)
		#else
			return nil
		#endif
	}

	init(openPeek: OpenPeek, session: BrowserWebSession? = nil) {
		id = openPeek.id
		activationScreenPoint = nil
		easelQuote = openPeek.easelQuote
		depth = openPeek.depth
		source = UnitPoint(
			x: CGFloat(openPeek.sourceX),
			y: CGFloat(openPeek.sourceY)
		)
		controller = BrowserController(
			initialURL: openPeek.url,
			session: session,
			history: openPeek.history,
			historyIndex: openPeek.historyIndex,
			scrollPosition: openPeek.scrollPosition
		)
		controller.easelQuoteHighlight = openPeek.easelQuote
		controller.pageZoom = openPeek.pageZoom
		hasPresented = true
		isPresented = true
	}
}
