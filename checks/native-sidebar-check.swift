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

	static func content(_ items: [BrowserSidebarItem], revision: Int = 0, top: CGFloat = 38, bottom: CGFloat = 45) -> some View {
		BrowserSidebarScrollView(items: items, revision: revision, top: top) { item in
			let _ = factories += 1
			Text(item.id).frame(height: item.height)
				.background { BrowserWindowFrameReader { anchors[item.id] = $0 } }
		}
		.environment(\.sidebarScrollIndicatorBottomInset, bottom)
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

/// Model AppKit asking about invalidation after installing the proposed bounds.
/// Reporting the new bounds without triggering AppKit's layout scheduling keeps
/// this case deterministic and leaves the geometry cached at the previous width.
@MainActor
private final class InstalledBoundsCollectionView: NSCollectionView {
	var installedBounds: NSRect?

	override var bounds: NSRect {
		get { installedBounds ?? super.bounds }
		set { super.bounds = newValue }
	}
}

@main
struct NativeSidebarCheck {
	@MainActor static func main() {
		geometryChecks()
		folderTransitionChecks()
		dragDestinationChecks()
		let application = NSApplication.shared
		application.setActivationPolicy(.prohibited)
		installedBoundsInvalidationCheck()
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
		precondition(scroll.scrollerInsets.top == 38 && scroll.scrollerInsets.bottom == 45, "Scroller must clear both edge fades")
		// Header reservation changes at the top must reveal space for the header,
		// rather than compensating with a new nonzero scroll offset.
		let firstRow = collection.item(at: IndexPath(item: 0, section: 0))
		for top: CGFloat in [67.5, 100, 82.25, 38] {
			host.rootView = Probe.content(items, top: top)
			Probe.pulse(host)
			guard let layout = collection.collectionViewLayout as? BrowserSidebarCollectionLayout else { fatalError("Missing sidebar layout") }
			precondition(layout.geometry.frames[0].minY == top + 4, "Native layout ignored an intermediate header reservation")
			precondition(scroll.scrollerInsets.top == top, "Scroller jumped ahead of the interpolated header reservation")
			precondition(collection.item(at: IndexPath(item: 0, section: 0)) === firstRow, "Header interpolation replaced a visible row")
			precondition(abs(scroll.contentView.bounds.origin.y) < 0.1, "Header reservation scrolled a list pinned at the top")
		}
		host.rootView = Probe.content(items)
		Probe.pulse(host)
		// Growing media controls change only the bottom reservation, without a
		// structural/revision update. The full content viewport must stay intact.
		let viewportBeforeInset = scroll.contentView.frame
		let boundsBeforeInset = scroll.contentView.bounds
		let contentSizeBeforeInset = collection.frame.size
		let factoriesBeforeInset = Probe.factories
		host.rootView = Probe.content(items, bottom: 120)
		Probe.pulse(host)
		precondition(scroll.scrollerInsets.bottom == 120, "Scroller ignored a media-only reservation change")
		precondition(scroll.contentView.frame == viewportBeforeInset && scroll.contentView.bounds == boundsBeforeInset, "Indicator insets changed the content viewport")
		precondition(collection.frame.size == contentSizeBeforeInset, "Indicator insets changed the scroll range")
		precondition(Probe.factories == factoriesBeforeInset, "Indicator insets rebuilt hosted rows")
		host.rootView = Probe.content(items)
		Probe.pulse(host)
		precondition(scroll.scrollerInsets.bottom == 45, "Scroller did not reset after media controls disappeared")
		let beforeResize = Probe.factories
		// Exercise both directions and the actual minimum sidebar width. The
		// original bug left wide row frames behind when shrinking the viewport.
		for width: CGFloat in [400, 300, 220, 168, 220, 300, 400, 168, 400] {
			window.setContentSize(NSSize(width: width, height: 600))
			Probe.pulse(host)
			guard let layout = collection.collectionViewLayout as? BrowserSidebarCollectionLayout else {
				fatalError("Missing production sidebar layout")
			}
			let viewportWidth = scroll.contentView.bounds.width
			precondition(abs(scroll.frame.width - width) < 0.5, "Native viewport did not follow the resized sidebar")
			precondition(abs(collection.frame.width - viewportWidth) < 0.5, "Document retained a previous sidebar width")
			precondition(abs(layout.geometry.contentSize.width - viewportWidth) < 0.5, "Cached row geometry retained a previous sidebar width")
			for path in collection.indexPathsForVisibleItems() {
				guard let attributes = layout.layoutAttributesForItem(at: path),
				      let cell = collection.item(at: path) else { fatalError("Visible row is missing") }
				precondition(attributes.frame.minX >= 0 && attributes.frame.maxX <= viewportWidth + 0.5, "Row layout extends beyond the sidebar viewport")
				precondition(abs(cell.view.frame.width - attributes.frame.width) < 0.5, "Visible native cell retained a previous row width")
				for hostedView in cell.view.subviews {
					precondition(abs(hostedView.frame.width - cell.view.bounds.width) < 0.5, "SwiftUI host retained a previous native cell width")
				}
			}
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

	@MainActor
	static func installedBoundsInvalidationCheck() {
		let collection = InstalledBoundsCollectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
		let layout = BrowserSidebarCollectionLayout()
		layout.items = [BrowserSidebarItem(id: "resize-probe")]
		collection.collectionViewLayout = layout
		for width: CGFloat in [300, 220, 168, 220, 300, 400] {
			layout.prepare()
			let cachedWidth = layout.geometry.contentSize.width
			var proposedBounds = collection.bounds
			proposedBounds.size.width = width
			collection.installedBounds = proposedBounds
			precondition(cachedWidth != width, "Probe must retain geometry from before the bounds change")
			precondition(collection.bounds == proposedBounds)
			precondition(layout.shouldInvalidateLayout(forBoundsChange: proposedBounds), "Installed new bounds hid a required sidebar width invalidation")
			layout.prepare()
			precondition(layout.geometry.contentSize.width == width, "Invalidated geometry did not adopt the installed width")
			precondition(!layout.shouldInvalidateLayout(forBoundsChange: proposedBounds), "Unchanged width must not invalidate on vertical scrolling")
		}
	}

	static func dragDestinationChecks() {
		let folderID = UUID()
		let pinnedID = UUID(), folderTabID = UUID(), groupTabID = UUID(), normalID = UUID()
		let items: [BrowserSidebarItem] = [
			.init(id: "pinned-header", kind: .pinnedHeader, height: 20, collection: .pinned),
			.init(id: "folder-header", kind: .folder(folderID), height: 24, collection: .folder(folderID)),
			.init(id: "folder-tab", tabID: folderTabID, collection: .folder(folderID)),
			.init(id: "pinned-tab", tabID: pinnedID, collection: .pinned),
			.init(id: "divider", kind: .divider, height: 28, collection: .normal),
			.init(id: "group-header", kind: .group("g"), height: 28, collection: .todayGroup("g")),
			.init(id: "group-tab", tabID: groupTabID, collection: .todayGroup("g")),
			.init(id: "normal-tab", tabID: normalID, collection: .normal),
			.init(id: "new", kind: .newTab, collection: .normal),
		]
		let geometry = BrowserSidebarLayoutGeometry(items: items, width: 260, top: 0, padding: 4, spacing: 2)
		for (index, expected) in [(0, pinnedID), (1, folderTabID), (4, normalID), (5, groupTabID)] {
			let frame = geometry.frames[index]
			for y in [frame.minY + 1, frame.midY, frame.maxY - 1] {
				let target = geometry.dropTarget(at: CGPoint(x: frame.midX, y: y), items: items)
				precondition(target?.0 == items[index].collection && target?.1 == expected, "Header drop must insert at its own collection's beginning")
			}
		}
		let newTab = geometry.frames[8]
		precondition(geometry.dropTarget(at: CGPoint(x: newTab.midX, y: newTab.midY), items: items)?.1 == nil, "New-tab target must still append")
		for count in [1, 4, 5, 8, 9] {
			let favourites = (0 ..< count).map { BrowserSidebarItem(id: "f-\($0)", kind: .favourite, isFavourite: true, tabID: UUID(), collection: .favourite) }
			let all = favourites + [items[0]]
			let grid = BrowserSidebarLayoutGeometry(items: all, width: 260, top: 0, padding: 4, spacing: 2)
			for index in Array(stride(from: 4, through: count, by: 4)) + [count] {
				let previous = grid.frames[index - 1]
				guard let indicator = grid.insertionIndicator(before: index, spacing: 2) else { fatalError("Missing grid insertion marker") }
				precondition(indicator.width == 2 && indicator.minY == previous.minY && indicator.height == previous.height && indicator.minX > previous.maxX, "Grid row/section boundary marker must stay beside the preceding tile")
			}
			let last = grid.frames[count - 1]
			let target = grid.dropTarget(at: CGPoint(x: last.maxX - 1, y: last.midY), items: all)
			precondition(target?.0 == .favourite && target?.1 == nil, "Grid end must continue appending to favourites")
		}
	}

	static func folderTransitionChecks() {
		let folderID = UUID()
		let header = BrowserSidebarItem(id: "folder", kind: .folder(folderID), height: 24, collection: .folder(folderID))
		var closedHeader = header
		closedHeader.isExpanded = false
		let children = (0 ..< 1000).map { BrowserSidebarItem(id: "child-\($0)", tabID: UUID(), collection: .folder(folderID)) }
		let tail = BrowserSidebarItem(id: "tail", tabID: UUID(), collection: .normal)
		let open = [header] + children + [tail]
		let closed = [closedHeader, tail]
		guard let opening = BrowserSidebarFolderTransition(from: closed, to: open),
		      let closing = BrowserSidebarFolderTransition(from: open, to: closed) else { fatalError("Folder disclosure must use native batches") }
		precondition(opening.inserted == (1 ..< 1001) && opening.deleted.isEmpty)
		precondition(closing.deleted == (1 ..< 1001) && closing.inserted.isEmpty)
		precondition(BrowserSidebarFolderTransition(from: open, to: [header] + Array(children.reversed()) + [tail]) == nil, "Drag reorders must not be mistaken for disclosure")
		precondition(BrowserSidebarFolderTransition(from: open, to: [header] + Array(children.dropLast()) + [tail]) == nil, "Tab close must not be mistaken for disclosure")
		precondition(BrowserSidebarFolderTransition(from: [], to: open) == nil)
		precondition(BrowserSidebarFolderTransition(from: [closedHeader, tail], to: [header, tail]) == nil, "Empty folders need no child animation")
		precondition(BrowserSidebarFolderTransition(from: closed, to: open + [tail]) == nil, "Concurrent structural changes must fall back safely")
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
		// Fractional header reservations arrive on every SwiftUI animation frame.
		// Both directions must match a fresh layout, including grid rows and the
		// visible-item search used for virtualization and drag targeting.
		var animated = BrowserSidebarLayoutGeometry(items: items, width: 260, top: 38, padding: 4, spacing: 2)
		let originalRows = animated.frames.rows.map { $0.y }
		for top: CGFloat in [100, 73.5, 52.25, 38, 0, -10, 67.75, 100, 38] {
			animated.updateTop(top)
			let reference = BrowserSidebarLayoutGeometry(items: items, width: 260, top: top, padding: 4, spacing: 2)
			precondition(Array(animated.frames) == Array(reference.frames), "Header interpolation changed final row geometry")
			precondition(animated.contentSize == reference.contentSize, "Header interpolation retained stale scroll bounds")
			precondition(animated.frames.rows.map { $0.y } == originalRows, "Header interpolation rebuilt the vertical index")
			for y: CGFloat in [0, 100, 500, 2000] {
				let rect = CGRect(x: 0, y: y, width: 260, height: 600)
				precondition(animated.visibleIndices(in: rect) == reference.visibleIndices(in: rect), "Header interpolation lost visible rows")
			}
		}
		var resized = BrowserSidebarLayoutGeometry(items: items, width: 260, top: 38, padding: 4, spacing: 2)
		let vertical = resized.frames.map { ($0.minY, $0.height) }
		for width: CGFloat in [168, 400, 220, 260] {
			resized.resize(width: width)
			let reference = BrowserSidebarLayoutGeometry(items: items, width: width, top: 38, padding: 4, spacing: 2)
			precondition(Array(resized.frames) == Array(reference.frames), "Width-only reuse changed row pixels")
			precondition(zip(resized.frames, vertical).allSatisfy { $0.0.minY == $0.1.0 && $0.0.height == $0.1.1 })
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
