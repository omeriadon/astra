import Foundation
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class BrowserPeek: Identifiable {
	let id: UUID
	let depth: Int
	let source: UnitPoint
	let controller: BrowserController
	var hasPresented: Bool
	var isPresented: Bool
	var isDismissing = false

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
			scrollPosition: controller.scrollPosition
		)
	}

	init(
		url: URL? = nil,
		depth: Int,
		source: UnitPoint,
		parentZoom: Double,
		zoomsOut: Bool,
		session: BrowserWebSession? = nil,
		existingController: BrowserController? = nil
	) {
		id = UUID()
		self.depth = depth
		self.source = source
		controller = existingController ?? BrowserController(initialURL: url, session: session, scrollPosition: .zero)
		hasPresented = false
		isPresented = false

		if zoomsOut {
			controller.pageZoom = parentZoom * (depth == 1 ? 0.95 : 0.85)
		} else {
			controller.pageZoom = parentZoom
		}
	}

	init(openPeek: OpenPeek, session: BrowserWebSession = .shared) {
		id = openPeek.id
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
		controller.pageZoom = openPeek.pageZoom
		hasPresented = true
		isPresented = true
	}
}
