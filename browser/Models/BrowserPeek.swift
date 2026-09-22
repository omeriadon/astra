import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserPeek: Identifiable {
	let id: UUID
	let depth: Int
	let source: UnitPoint
	let controller: BrowserController
	var hasPresented: Bool

	var openPeek: OpenPeek {
		OpenPeek(
			id: id,
			depth: depth,
			sourceX: Double(source.x),
			sourceY: Double(source.y),
			url: controller.url,
			history: controller.history,
			historyIndex: controller.historyIndex,
			pageZoom: controller.webView.pageZoom
		)
	}

	init(
		url: URL,
		depth: Int,
		source: UnitPoint,
		parentZoom: Double,
		zoomsOut: Bool
	) {
		id = UUID()
		self.depth = depth
		self.source = source
		controller = BrowserController(initialURL: url)
		hasPresented = false

		if zoomsOut {
			controller.webView.pageZoom = parentZoom * (depth == 1 ? 0.95 : 0.85)
		} else {
			controller.webView.pageZoom = parentZoom
		}
	}

	init(openPeek: OpenPeek) {
		id = openPeek.id
		depth = openPeek.depth
		source = UnitPoint(
			x: CGFloat(openPeek.sourceX),
			y: CGFloat(openPeek.sourceY)
		)
		controller = BrowserController(
			initialURL: openPeek.url,
			history: openPeek.history,
			historyIndex: openPeek.historyIndex
		)
		controller.webView.pageZoom = openPeek.pageZoom
		hasPresented = true
	}
}
