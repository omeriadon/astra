import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Native cells contain the existing SwiftUI controls, never a tall hosting view
/// around a LazyVStack (which would lose its SwiftUI ScrollView's virtualization).
struct BrowserSidebarItem: Equatable {
	enum Kind: Equatable {
		case tab, favourite, split, pinnedHeader, divider, newTab, emptyFavourites, privateHeader
		case folder(UUID), group(String)
	}

	let id: String
	var kind: Kind = .tab
	var height: CGFloat = 30
	var isFavourite = false
	var isExpanded = true
	var tabID: UUID?
	var collection: SidebarTabCollection?

	var isPinned: Bool {
		switch collection {
			case .pinned?, .folder(_)?: true
			default: false
		}
	}

	var indentation: CGFloat {
		if case .folder(_)? = collection {
			return 12
		}
		return 0
	}
}

/// Only animate a whole folder opening/closing. Tab reorders, removals and
/// split projection changes keep their existing structural update path.
struct BrowserSidebarFolderTransition {
	let inserted: Range<Int>
	let deleted: Range<Int>

	init?(from old: [BrowserSidebarItem], to new: [BrowserSidebarItem]) {
		var header = 0
		while header < min(old.count, new.count), old[header] == new[header] { header += 1 }
		guard old.indices.contains(header), new.indices.contains(header),
		      case let .folder(folderID) = old[header].kind,
		      old[header].isExpanded != new[header].isExpanded else { return nil }
		var updatedHeader = old[header]
		updatedHeader.isExpanded = new[header].isExpanded
		guard updatedHeader == new[header] else { return nil }
		let prefix = header + 1
		var suffix = 0
		while suffix < min(old.count, new.count) - prefix,
		      old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
		deleted = prefix ..< (old.count - suffix)
		inserted = prefix ..< (new.count - suffix)
		guard inserted.isEmpty != deleted.isEmpty,
		      new[header].isExpanded == !inserted.isEmpty else { return nil }
		let children = inserted.isEmpty ? old[deleted] : new[inserted]
		guard children.allSatisfy({ $0.collection == .folder(folderID) && ($0.tabID != nil || $0.kind == .split) }) else { return nil }
		// A tab added to or removed from an expanded folder isn't a disclosure.
		let shorter = inserted.isEmpty ? new : old
		guard !shorter.indices.contains(prefix) || shorter[prefix].collection != .folder(folderID) else { return nil }
	}
}

/// Shared AppKit/UIKit geometry. There are no SwiftUI size probes on resize or
/// scroll. Item metric changes rebuild the index; width changes reuse it.
struct BrowserSidebarLayoutGeometry {
	nonisolated struct Frames: RandomAccessCollection {
		typealias Index = Int
		struct Row { let y: CGFloat; let height: CGFloat; let column: Int? }
		var rows: [Row] = []
		var width: CGFloat = 0
		var padding: CGFloat = 0
		var topAdjustment: CGFloat = 0
		var startIndex: Int { rows.startIndex }
		var endIndex: Int { rows.endIndex }
		subscript(index: Int) -> CGRect {
			let row = rows[index]
			let available = Swift.max(0, width - padding * 2)
			if let column = row.column {
				let tileWidth = Swift.max(0, (available - 18) / 4)
				return CGRect(x: padding + CGFloat(column) * (tileWidth + 6), y: row.y + topAdjustment, width: tileWidth, height: row.height)
			}
			return CGRect(x: padding, y: row.y + topAdjustment, width: available, height: row.height)
		}
	}

	private(set) var frames = Frames()
	private(set) var contentSize = CGSize.zero
	private var favouriteIndices: Set<Int> = []
	private var firstTabIDs: [SidebarTabCollection: UUID] = [:]
	private var top: CGFloat

	init(items: [BrowserSidebarItem], width: CGFloat, top: CGFloat, padding: CGFloat, spacing: CGFloat) {
		let width = max(0, width)
		self.top = max(0, top)
		frames.width = width
		frames.padding = padding
		var y = max(0, top) + 4
		var column = 0
		var inFavourites = false
		frames.rows.reserveCapacity(items.count)
		for item in items {
			if let collection = item.collection, let id = item.tabID, firstTabIDs[collection] == nil {
				firstTabIDs[collection] = id
			}
			if item.isFavourite {
				inFavourites = true
				favouriteIndices.insert(frames.count)
				if column == 4 {
					y += 48
					column = 0
				}
				frames.rows.append(.init(y: y, height: 42, column: column))
				column += 1
			} else {
				if inFavourites {
					y += 42 + 12 + spacing
					column = 0
					inFavourites = false
				}
				frames.rows.append(.init(y: y, height: item.height, column: nil))
				y += item.height + spacing
			}
		}
		if inFavourites {
			y += 42
		}
		contentSize = CGSize(width: width, height: y + 48)
	}

	/// Header animation changes every frame; reuse the vertical index and apply
	/// one shared translation instead of rebuilding every offscreen row.
	mutating func updateTop(_ top: CGFloat) {
		let top = max(0, top)
		let delta = top - self.top
		frames.topAdjustment += delta
		contentSize.height += delta
		self.top = top
	}

	/// Width-only native layout never rebuilds the item/vertical index.
	mutating func resize(width: CGFloat) {
		frames.width = max(0, width)
		contentSize.width = frames.width
	}

	/// O(log n + visible items), including all four tiles on a shared grid line.
	func visibleIndices(in rect: CGRect) -> Range<Int> {
		var lower = 0
		var upper = frames.count
		while lower < upper {
			let middle = (lower + upper) / 2
			if frames[middle].maxY <= rect.minY {
				lower = middle + 1
			} else {
				upper = middle
			}
		}
		let start = lower
		while lower < frames.count, frames[lower].minY < rect.maxY {
			lower += 1
		}
		return start ..< lower
	}

	func insertion(at point: CGPoint) -> (index: Int, after: Bool)? {
		guard !frames.isEmpty else { return nil }
		let candidates = visibleIndices(in: CGRect(x: 0, y: point.y - 60, width: contentSize.width, height: 120))
		let index = candidates.min { left, right in
			func distance(_ frame: CGRect) -> CGFloat {
				let dx = max(frame.minX - point.x, point.x - frame.maxX, 0)
				let dy = max(frame.minY - point.y, point.y - frame.maxY, 0)
				return dx * dx + dy * dy
			}
			return distance(frames[left]) < distance(frames[right])
		} ?? (point.y < frames[0].minY ? 0 : frames.count - 1)
		let frame = frames[index]
		let isTile = favouriteIndices.contains(index)
		return (index, isTile ? point.x > frame.midX : point.y > frame.midY)
	}

	/// A grid insertion at a row/section boundary belongs to the trailing edge
	/// of its last tile, not a horizontal line through the next section.
	func insertionIndicator(before index: Int, spacing: CGFloat) -> CGRect? {
		guard !frames.isEmpty, index >= 0, index <= frames.count else { return nil }
		if index > 0, favouriteIndices.contains(index - 1),
		   index == frames.count || !favouriteIndices.contains(index) || frames[index].minY != frames[index - 1].minY
		{
			let previous = frames[index - 1]
			return CGRect(x: previous.maxX + 2, y: previous.minY, width: 2, height: previous.height)
		}
		let frame = frames[min(index, frames.count - 1)]
		if favouriteIndices.contains(index) {
			return CGRect(x: frame.minX - 3, y: frame.minY, width: 2, height: frame.height)
		}
		let y = index == frames.count ? frame.maxY : frame.minY - spacing / 2
		return CGRect(x: frame.minX, y: y, width: frame.width, height: 2)
	}

	func dropTarget(at point: CGPoint, items: [BrowserSidebarItem]) -> (SidebarTabCollection, UUID?)? {
		guard let insertion = insertion(at: point), items.indices.contains(insertion.index),
		      let collection = items[insertion.index].collection else { return nil }
		let item = items[insertion.index]
		guard item.tabID != nil else {
			// Headers represent the beginning of a collection. Previously they
			// displayed a marker at the top but silently appended at the end.
			// The new-tab button and empty regions remain append targets.
			switch item.kind {
				case .newTab, .emptyFavourites: return (collection, nil)
				default: return (collection, firstTabIDs[collection])
			}
		}
		if !insertion.after {
			return (collection, item.tabID)
		}
		let next = insertion.index + 1
		// At a section boundary, "after the last favourite" still means
		// favourite; it must not silently become "before the first pinned tab".
		let before = items.indices.contains(next) && items[next].collection == collection ? items[next].tabID : nil
		return (collection, before)
	}
}
