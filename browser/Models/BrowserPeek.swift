import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserPeek: Identifiable {
	let id = UUID()
	let depth: Int
	let source: UnitPoint
	let controller: BrowserController

	init(
		url: URL,
		depth: Int,
		source: UnitPoint,
		parentZoom: Double,
		zoomsOut: Bool
	) {
		self.depth = depth
		self.source = source
		controller = BrowserController(initialURL: url)

		if zoomsOut {
			controller.webView.pageZoom = parentZoom * (depth == 1 ? 0.95 : 0.85)
		} else {
			controller.webView.pageZoom = parentZoom
		}
	}
}
