import SwiftUI

/// Only semantic changes refresh hosted roots. In particular a new proposed
/// width must only resize the visible native cells, not replace their contents.
private struct BrowserSidebarTraits: Equatable {
	let colorScheme: ColorScheme
	let dynamicTypeSize: DynamicTypeSize
	let layoutDirection: LayoutDirection
	let locale: String
	let reduceMotion: Bool
	let reduceTransparency: Bool
	let contrast: ColorSchemeContrast
	let enabled: Bool
	let controlSize: ControlSize
	let voiceOver: Bool
	let differentiateWithoutColor: Bool
	let displayScale: CGFloat

	init(_ environment: EnvironmentValues) {
		colorScheme = environment.colorScheme
		dynamicTypeSize = environment.dynamicTypeSize
		layoutDirection = environment.layoutDirection
		locale = environment.locale.identifier
		reduceMotion = environment.accessibilityReduceMotion
		reduceTransparency = environment.accessibilityReduceTransparency
		contrast = environment.colorSchemeContrast
		enabled = environment.isEnabled
		controlSize = environment.controlSize
		voiceOver = environment.accessibilityVoiceOverEnabled
		differentiateWithoutColor = environment.accessibilityDifferentiateWithoutColor
		displayScale = environment.displayScale
	}
}

#if os(macOS)
	import AppKit

	struct BrowserSidebarScrollView<Revision: Equatable, Row: View>: NSViewRepresentable {
		let items: [BrowserSidebarItem]
		let revision: Revision
		var top: CGFloat = 0
		var padding: CGFloat = BrowserChromeMetrics.shellEdgePadding
		var spacing: CGFloat = 2
		var move: (([UUID], SidebarTabCollection, UUID?) -> Void)?
		@ViewBuilder let row: (BrowserSidebarItem) -> Row
		@Environment(\.self) private var environment

		func makeCoordinator() -> Coordinator {
			Coordinator()
		}

		func makeNSView(context: Context) -> NSScrollView {
			let scroll = NSScrollView()
			scroll.drawsBackground = false
			scroll.contentView.drawsBackground = false
			scroll.hasVerticalScroller = true
			scroll.hasHorizontalScroller = false
			scroll.scrollerStyle = .overlay
			scroll.autohidesScrollers = true
			scroll.automaticallyAdjustsContentInsets = false
			scroll.horizontalScrollElasticity = .none
			scroll.verticalScrollElasticity = .automatic
			let collection = NSCollectionView()
			collection.frame = scroll.contentView.bounds
			collection.autoresizingMask = [.width]
			collection.backgroundColors = [.clear]
			collection.isSelectable = false // Existing SwiftUI row controls own selection.
			collection.collectionViewLayout = context.coordinator.layout
			collection.register(BrowserSidebarHostingItem.self, forItemWithIdentifier: Coordinator.cellID)
			collection.dataSource = context.coordinator
			collection.delegate = context.coordinator
			collection.registerForDraggedTypes([Coordinator.tabType])
			scroll.documentView = collection
			context.coordinator.collection = collection
			return scroll
		}

		func updateNSView(_ scroll: NSScrollView, context: Context) {
			context.coordinator.update(self, scroll: scroll)
		}

		static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
			coordinator.collection?.delegate = nil
			coordinator.collection?.dataSource = nil
			coordinator.collection = nil
			coordinator.parent = nil
			scroll.documentView = nil
		}

		@MainActor
		final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
			static var cellID: NSUserInterfaceItemIdentifier {
				.init("sidebar-hosted-row")
			}

			static var tabType: NSPasteboard.PasteboardType {
				.init("com.omeriadon.astra.tab")
			}

			let layout = BrowserSidebarCollectionLayout()
			weak var collection: NSCollectionView?
			var parent: BrowserSidebarScrollView?
			private var traits: BrowserSidebarTraits?

			func update(_ new: BrowserSidebarScrollView, scroll: NSScrollView) {
				guard let collection else { return }
				let old = parent
				let newTraits = BrowserSidebarTraits(new.environment)
				let structureChanged = old?.items != new.items
				let contentChanged = old?.revision != new.revision || traits != newTraits
				let metricsChanged = structureChanged || old?.top != new.top || old?.padding != new.padding || old?.spacing != new.spacing
				// Anchor structural changes to the first visible item rather than jumping
				// when AI inserts groups, folders collapse, or a tab above it closes.
				let origin = scroll.contentView.bounds.origin
				let anchor = layout.geometry.visibleIndices(in: scroll.contentView.bounds).first.flatMap { index -> (String, CGFloat)? in
					guard structureChanged, origin.y > 0, let old, old.items.indices.contains(index) else { return nil }
					return (old.items[index].id, origin.y - layout.geometry.frames[index].minY)
				}
				parent = new
				traits = newTraits
				if metricsChanged {
					layout.items = new.items
					layout.top = new.top
					layout.padding = new.padding
					layout.spacing = new.spacing
					layout.invalidateLayout()
				}
				if structureChanged {
					collection.reloadData()
				}
				if contentChanged, !structureChanged {
					for path in collection.indexPathsForVisibleItems() {
						guard new.items.indices.contains(path.item), let cell = collection.item(at: path) as? BrowserSidebarHostingItem else { continue }
						configure(cell, item: new.items[path.item])
					}
				}
				if metricsChanged {
					collection.layoutSubtreeIfNeeded()
					var y = origin.y
					if let anchor, let index = new.items.firstIndex(where: { $0.id == anchor.0 }), layout.geometry.frames.indices.contains(index) {
						y = layout.geometry.frames[index].minY + anchor.1
					}
					let maximum = max(0, layout.collectionViewContentSize.height - scroll.contentView.bounds.height)
					scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(y, 0), maximum)))
					scroll.reflectScrolledClipView(scroll.contentView)
				}
			}

			func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
				parent?.items.count ?? 0
			}

			func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
				let cell = collectionView.makeItem(withIdentifier: Self.cellID, for: indexPath) as! BrowserSidebarHostingItem
				if let parent {
					configure(cell, item: parent.items[indexPath.item])
				}
				return cell
			}

			private func configure(_ cell: BrowserSidebarHostingItem, item: BrowserSidebarItem) {
				guard let parent else { return }
				cell.configure(id: item.id, root: AnyView(parent.row(item)
						.environment(\.self, parent.environment)
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)))
			}

			private func draggedIDs(_ info: any NSDraggingInfo) -> [UUID] {
				guard info.draggingSource != nil else { return [] } // Only in-process tab identities.
				return (info.draggingPasteboard.pasteboardItems ?? []).compactMap { item in
					guard let data = item.data(forType: Self.tabType), let text = String(data: data, encoding: .utf8) else { return nil }
					return UUID(uuidString: text)
				}
			}

			func collectionView(_ collectionView: NSCollectionView, validateDrop info: any NSDraggingInfo,
			                    proposedIndexPath path: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
			                    dropOperation operation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation
			{
				guard parent?.move != nil, !draggedIDs(info).isEmpty,
				      layout.geometry.dropTarget(at: collectionView.convert(info.draggingLocation, from: nil), items: parent?.items ?? []) != nil else { return [] }
				if let insertion = layout.geometry.insertion(at: collectionView.convert(info.draggingLocation, from: nil)) {
					unsafe path.pointee = NSIndexPath(forItem: insertion.index + (insertion.after ? 1 : 0), inSection: 0)
				}
				unsafe operation.pointee = .before
				return info.draggingSourceOperationMask.contains(.move) ? .move : .copy
			}

			func collectionView(_ collectionView: NSCollectionView, acceptDrop info: any NSDraggingInfo,
			                    indexPath _: IndexPath, dropOperation _: NSCollectionView.DropOperation) -> Bool
			{
				let ids = draggedIDs(info)
				guard !ids.isEmpty, let move = parent?.move, let target = layout.geometry.dropTarget(at: collectionView.convert(info.draggingLocation, from: nil), items: parent?.items ?? []) else { return false }
				move(ids, target.0, target.1)
				return true
			}
		}
	}

	private final class BrowserSidebarHostingItem: NSCollectionViewItem {
		private var host: NSHostingView<AnyView>?
		private var rowID: String?

		override func loadView() {
			view = NSView()
		}

		func configure(id: String, root: AnyView) {
			if let host, rowID == id {
				host.rootView = root
			} else {
				host?.removeFromSuperview()
				let host = NSHostingView(rootView: root)
				host.sizingOptions = [] // Frames are known; don't probe min/ideal/max sizes.
				host.safeAreaRegions = []
				host.frame = view.bounds
				host.autoresizingMask = [.width, .height]
				view.addSubview(host)
				self.host = host
				rowID = id
			}
		}

		override func prepareForReuse() {
			super.prepareForReuse()
			// Reusing another tab must not inherit rename/hover/focus state. Empty the
			// root now, so the reuse pool cannot retain tab observations or previews.
			host?.rootView = AnyView(EmptyView())
			rowID = nil
		}
	}

	final class BrowserSidebarCollectionLayout: NSCollectionViewLayout {
		var items: [BrowserSidebarItem] = []
		var top: CGFloat = 0
		var padding: CGFloat = 4
		var spacing: CGFloat = 2
		private(set) var geometry = BrowserSidebarLayoutGeometry(items: [], width: 0, top: 0, padding: 0, spacing: 0)

		override func prepare() {
			super.prepare()
			geometry = BrowserSidebarLayoutGeometry(items: items, width: collectionView?.bounds.width ?? 0, top: top, padding: padding, spacing: spacing)
		}

		override var collectionViewContentSize: NSSize {
			NSSize(width: geometry.contentSize.width, height: max(geometry.contentSize.height, collectionView?.enclosingScrollView?.contentSize.height ?? 0))
		}

		override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
			geometry.visibleIndices(in: rect).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
		}

		override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
			guard geometry.frames.indices.contains(indexPath.item) else { return nil }
			let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
			attributes.frame = geometry.frames[indexPath.item]
			return attributes
		}

		override func layoutAttributesForInterItemGap(before indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
			guard !geometry.frames.isEmpty else { return nil }
			let index = min(indexPath.item, geometry.frames.count - 1)
			let frame = geometry.frames[index]
			let attributes = NSCollectionViewLayoutAttributes(forInterItemGapBefore: indexPath)
			if items[index].isFavourite, indexPath.item < geometry.frames.count {
				attributes.frame = NSRect(x: frame.minX - 3, y: frame.minY, width: 2, height: frame.height)
			} else {
				let y = indexPath.item >= geometry.frames.count ? frame.maxY : frame.minY - spacing / 2
				attributes.frame = NSRect(x: frame.minX, y: y, width: frame.width, height: 2)
			}
			return attributes
		}

		override func layoutAttributesForDropTarget(at point: NSPoint) -> NSCollectionViewLayoutAttributes? {
			guard let insertion = geometry.insertion(at: point) else { return nil }
			return layoutAttributesForInterItemGap(before: IndexPath(item: insertion.index + (insertion.after ? 1 : 0), section: 0))
		}

		override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
			newBounds.width != collectionView?.bounds.width
		}
	}
#endif

#if os(iOS)
	import UIKit

	struct BrowserSidebarScrollView<Revision: Equatable, Row: View>: UIViewRepresentable {
		let items: [BrowserSidebarItem]
		let revision: Revision
		var top: CGFloat = 0
		var padding: CGFloat = BrowserChromeMetrics.shellEdgePadding
		var spacing: CGFloat = 2
		var move: (([UUID], SidebarTabCollection, UUID?) -> Void)?
		let row: (BrowserSidebarItem) -> Row
		@Environment(\.self) private var environment

		func makeCoordinator() -> Coordinator {
			Coordinator()
		}

		func makeUIView(context: Context) -> UICollectionView {
			let collection = UICollectionView(frame: .zero, collectionViewLayout: context.coordinator.layout)
			collection.backgroundColor = .clear
			collection.contentInsetAdjustmentBehavior = .never
			collection.alwaysBounceVertical = true
			collection.allowsSelection = false
			collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "sidebar-hosted-row")
			collection.dataSource = context.coordinator
			collection.dragDelegate = context.coordinator
			collection.dropDelegate = context.coordinator
			collection.dragInteractionEnabled = true
			return collection
		}

		func updateUIView(_ collection: UICollectionView, context: Context) {
			let coordinator = context.coordinator
			let old = coordinator.parent
			let traits = BrowserSidebarTraits(environment)
			let structureChanged = old?.items != items
			let contentChanged = old?.revision != revision || coordinator.traits != traits
			let metricsChanged = structureChanged || old?.top != top || old?.padding != padding || old?.spacing != spacing
			let origin = collection.contentOffset
			let anchor = coordinator.layout.geometry.visibleIndices(in: collection.bounds).first.flatMap { index -> (String, CGFloat)? in
				guard structureChanged, origin.y > 0, let old, old.items.indices.contains(index) else { return nil }
				return (old.items[index].id, origin.y - coordinator.layout.geometry.frames[index].minY)
			}
			coordinator.parent = self
			coordinator.traits = traits
			if metricsChanged {
				coordinator.layout.items = items
				coordinator.layout.top = top
				coordinator.layout.padding = padding
				coordinator.layout.spacing = spacing
				coordinator.layout.invalidateLayout()
			}
			if structureChanged {
				collection.reloadData()
			}
			if contentChanged, !structureChanged {
				for path in collection.indexPathsForVisibleItems {
					if let cell = collection.cellForItem(at: path), items.indices.contains(path.item) {
						coordinator.configure(cell, item: items[path.item])
					}
				}
			}
			if metricsChanged {
				collection.layoutIfNeeded()
				var y = origin.y
				if let anchor, let index = items.firstIndex(where: { $0.id == anchor.0 }), coordinator.layout.geometry.frames.indices.contains(index) {
					y = coordinator.layout.geometry.frames[index].minY + anchor.1
				}
				collection.setContentOffset(CGPoint(x: 0, y: min(max(y, 0), max(0, collection.contentSize.height - collection.bounds.height))), animated: false)
			}
		}

		static func dismantleUIView(_ collection: UICollectionView, coordinator: Coordinator) {
			collection.dataSource = nil
			collection.dragDelegate = nil
			collection.dropDelegate = nil
			coordinator.parent = nil
		}

		@MainActor
		final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
			let layout = BrowserSidebarCollectionLayout()
			var parent: BrowserSidebarScrollView?
			fileprivate var traits: BrowserSidebarTraits?

			func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
				parent?.items.count ?? 0
			}

			func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
				let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "sidebar-hosted-row", for: indexPath)
				if let parent {
					configure(cell, item: parent.items[indexPath.item])
				}
				return cell
			}

			func configure(_ cell: UICollectionViewCell, item: BrowserSidebarItem) {
				guard let parent else { return }
				cell.contentConfiguration = UIHostingConfiguration {
					parent.row(item).environment(\.self, parent.environment).id(item.id)
				}
				.margins(.all, 0)
				.minSize(width: 0, height: 0)
				cell.backgroundConfiguration = .clear()
			}

			func collectionView(_: UICollectionView, itemsForBeginning _: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
				guard let parent, parent.move != nil, let id = parent.items[indexPath.item].tabID else { return [] }
				let item = UIDragItem(itemProvider: NSItemProvider(object: id.uuidString as NSString))
				item.localObject = id
				return [item]
			}

			func collectionView(_: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath _: IndexPath?) -> UICollectionViewDropProposal {
				let valid = parent?.move != nil && session.localDragSession != nil && session.items.contains { $0.localObject is UUID }
				return UICollectionViewDropProposal(operation: valid ? .move : .forbidden, intent: .insertAtDestinationIndexPath)
			}

			func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
				guard let parent, let move = parent.move, !parent.items.isEmpty else { return }
				let ids = coordinator.items.compactMap { $0.dragItem.localObject as? UUID }
				guard !ids.isEmpty, let target = layout.geometry.dropTarget(at: coordinator.session.location(in: collectionView), items: parent.items) else { return }
				move(ids, target.0, target.1)
			}
		}
	}

	final class BrowserSidebarCollectionLayout: UICollectionViewLayout {
		var items: [BrowserSidebarItem] = []
		var top: CGFloat = 0
		var padding: CGFloat = 4
		var spacing: CGFloat = 2
		private(set) var geometry = BrowserSidebarLayoutGeometry(items: [], width: 0, top: 0, padding: 0, spacing: 0)

		override func prepare() {
			super.prepare()
			geometry = BrowserSidebarLayoutGeometry(items: items, width: collectionView?.bounds.width ?? 0, top: top, padding: padding, spacing: spacing)
		}

		override var collectionViewContentSize: CGSize {
			geometry.contentSize
		}

		override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
			geometry.visibleIndices(in: rect).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
		}

		override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
			guard geometry.frames.indices.contains(indexPath.item) else { return nil }
			let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
			attributes.frame = geometry.frames[indexPath.item]
			return attributes
		}

		override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
			newBounds.width != collectionView?.bounds.width
		}
	}
#endif
