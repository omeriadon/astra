// Compiles the production native viewport independently of Astra's Xcode 27 UI.
// No SwiftUI List/ScrollView, browser session, WebKit or network dependencies.
import AppKit
import SwiftUI

enum SidebarTabCollection: Hashable, Sendable {
	case favourite, pinned, normal, folder(UUID), todayGroup(String)
}

enum BrowserChromeMetrics {
	static let shellEdgePadding: CGFloat = 4
}

@MainActor
private enum Probe {
	static var factories = 0
	static var anchors: [String: CGRect] = [:]

	static func content(_ items: [BrowserSidebarItem], revision: Int = 0, top: CGFloat = 38) -> some View {
		BrowserSidebarScrollView(items: items, revision: revision, top: top) { item in
			let _ = factories += 1
			Text(item.id).frame(height: item.height)
				.background { BrowserWindowFrameReader { anchors[item.id] = $0 } }
		}
	}

	static func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
		(view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
	}

	static func pulse(_ view: NSView) {
		for _ in 0 ..< 3 {
			view.layoutSubtreeIfNeeded()
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
		}
	}
}

@main
struct NativeSidebarCheck {
	@MainActor static func main() {
		geometryChecks()
		let application = NSApplication.shared
		application.setActivationPolicy(.prohibited)
		let items = (0 ..< 10000).map { BrowserSidebarItem(id: "tab-\($0)", tabID: UUID(), collection: .normal) }
		let host = NSHostingView(rootView: Probe.content(items))
		host.sizingOptions = []
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentView = host
		host.frame = NSRect(x: 0, y: 0, width: 300, height: 600)
		Probe.pulse(host)
		guard let scroll = Probe.descendants(host, of: NSScrollView.self).first,
		      let collection = scroll.documentView as? NSCollectionView else { fatalError("Viewport must be NSScrollView + NSCollectionView") }
		precondition(Probe.factories > 0 && Probe.factories < 100, "Must instantiate viewport rows, not all 10,000")
		precondition(collection.numberOfItems(inSection: 0) == 10000)
		// Header reservation changes at the top must reveal space for the header,
		// rather than compensating with a new nonzero scroll offset.
		host.rootView = Probe.content(items, top: 100)
		Probe.pulse(host)
		precondition(abs(scroll.contentView.bounds.origin.y) < 0.1, "Header reservation scrolled a list pinned at the top")
		host.rootView = Probe.content(items)
		Probe.pulse(host)
		let beforeResize = Probe.factories
		for width in stride(from: 240, through: 400, by: 20) {
			window.setContentSize(NSSize(width: CGFloat(width), height: 600))
			Probe.pulse(host)
		}
		precondition(Probe.factories == beforeResize, "Width-only layout replaced hosted roots")
		scroll.contentView.scroll(to: NSPoint(x: 0, y: 100_000))
		scroll.reflectScrolledClipView(scroll.contentView)
		Probe.pulse(host)
		precondition(Probe.factories - beforeResize < 100, "Native scroll realized offscreen rows")
		let origin = scroll.contentView.bounds.origin.y
		if let path = collection.indexPathsForVisibleItems().min(by: { $0.item < $1.item }),
		   let layout = collection.collectionViewLayout as? BrowserSidebarCollectionLayout,
		   let anchor = Probe.anchors[items[path.item].id]
		{
			precondition(abs(anchor.minY - (layout.geometry.frames[path.item].minY - origin)) < 0.5, "Preview anchor is local to a reused host instead of the window")
		} else {
			fatalError("Visible hosted row did not publish its window frame")
		}
		let beforeSelection = Probe.factories
		host.rootView = Probe.content(items, revision: 1)
		Probe.pulse(host)
		precondition(abs(scroll.contentView.bounds.origin.y - origin) < 0.1, "Selection changed scroll position")
		precondition(Probe.factories - beforeSelection < 100, "Semantic update refreshed offscreen roots")
		host.rootView = Probe.content(Array(items.dropFirst()), revision: 2)
		Probe.pulse(host)
		precondition(abs(scroll.contentView.bounds.origin.y - (origin - 32)) < 0.1, "Closing a preceding tab lost the scroll anchor")
		window.contentView = nil
		window.close()
		print("Native sidebar: 10,000 rows, visible-only hosting, width-only root retention, selection and structural scroll anchors passed")
	}

	static func geometryChecks() {
		let favourites = (0 ..< 9).map { BrowserSidebarItem(id: "f-\($0)", kind: .favourite, isFavourite: true, tabID: UUID(), collection: .favourite) }
		let items = favourites + [.init(id: "pinned", kind: .pinnedHeader, height: 20, collection: .pinned)]
			+ (0 ..< 10000).map { BrowserSidebarItem(id: "n-\($0)", tabID: UUID(), collection: .normal) }
		for width: CGFloat in [0, 180, 260, 400] {
			let geometry = BrowserSidebarLayoutGeometry(items: items, width: width, top: 38, padding: 4, spacing: 2)
			precondition(geometry.frames.count == items.count)
			precondition(geometry.frames.allSatisfy { $0.width >= 0 && $0.height > 0 })
			precondition(geometry.frames[0].minY == 42 && geometry.frames[3].minY == 42)
			precondition(geometry.frames[4].minY == 90 && geometry.frames[8].minY == 138)
			precondition(geometry.frames[9].minY == 194)
			for offset in stride(from: -100, to: 320_000, by: 997) {
				let rect = CGRect(x: 0, y: CGFloat(offset), width: max(1, width), height: 600)
				let expected = geometry.frames.indices.filter { geometry.frames[$0].maxY > rect.minY && geometry.frames[$0].minY < rect.maxY }
				precondition(Array(geometry.visibleIndices(in: rect)) == expected, "Visible index must match brute force")
				precondition(geometry.visibleIndices(in: rect).count < 40)
			}
		}
		let geometry = BrowserSidebarLayoutGeometry(items: items, width: 260, top: 38, padding: 4, spacing: 2)
		let lastFavourite = geometry.frames[8]
		let endFavourite = geometry.dropTarget(at: CGPoint(x: lastFavourite.maxX - 1, y: lastFavourite.midY), items: items)
		precondition(endFavourite?.0 == .favourite && endFavourite?.1 == nil, "Grid boundary changed destination collection")
		let firstNormal = geometry.frames[10]
		precondition(geometry.dropTarget(at: CGPoint(x: 30, y: firstNormal.minY + 1), items: items)?.1 == items[10].tabID)
		precondition(geometry.dropTarget(at: CGPoint(x: 30, y: firstNormal.maxY - 1), items: items)?.1 == items[11].tabID)
		let folderID = UUID()
		let emptyRegions: [BrowserSidebarItem] = [
			.init(id: "f", kind: .emptyFavourites, height: 14, collection: .favourite),
			.init(id: "p", kind: .pinnedHeader, height: 20, collection: .pinned),
			.init(id: "folder", kind: .folder(folderID), height: 24, collection: .folder(folderID)),
			.init(id: "g", kind: .group("g"), height: 28, collection: .todayGroup("g")),
			.init(id: "new", kind: .newTab, collection: .normal),
		]
		let emptyGeometry = BrowserSidebarLayoutGeometry(items: emptyRegions, width: 260, top: 0, padding: 4, spacing: 2)
		for (index, item) in emptyRegions.enumerated() {
			let point = CGPoint(x: 20, y: emptyGeometry.frames[index].midY)
			precondition(emptyGeometry.dropTarget(at: point, items: emptyRegions)?.0 == item.collection)
		}
		precondition(BrowserSidebarLayoutGeometry(items: [], width: 260, top: 0, padding: 4, spacing: 2).visibleIndices(in: .zero).isEmpty)
	}
}
