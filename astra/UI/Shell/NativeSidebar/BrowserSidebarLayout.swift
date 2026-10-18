import Foundation

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
	var tabID: UUID?
	var collection: SidebarTabCollection?

	var isPinned: Bool {
		switch collection {
			case .pinned?, .folder(_)?: true
			default: false
		}
	}

	var indentation: CGFloat {
		if case .folder(_)? = collection { return 12 }
		return 0
	}
}

/// Shared AppKit/UIKit geometry. There are no SwiftUI size probes on resize or
/// scroll. Only width or item metrics changes rebuild the inexpensive frame index.
struct BrowserSidebarLayoutGeometry {
	private(set) var frames: [CGRect] = []
	private(set) var contentSize = CGSize.zero
	private var favouriteIndices: Set<Int> = []

	init(items: [BrowserSidebarItem], width: CGFloat, top: CGFloat, padding: CGFloat, spacing: CGFloat) {
		let width = max(0, width)
		let available = max(0, width - padding * 2)
		let tileWidth = max(0, (available - 18) / 4)
		var y = max(0, top) + 4
		var column = 0
		var inFavourites = false
		frames.reserveCapacity(items.count)
		for item in items {
			if item.isFavourite {
				inFavourites = true
				favouriteIndices.insert(frames.count)
				if column == 4 {
					y += 48
					column = 0
				}
				frames.append(CGRect(x: padding + CGFloat(column) * (tileWidth + 6), y: y, width: tileWidth, height: 42))
				column += 1
			} else {
				if inFavourites {
					y += 42 + 12 + spacing
					column = 0
					inFavourites = false
				}
				frames.append(CGRect(x: padding, y: y, width: available, height: item.height))
				y += item.height + spacing
			}
		}
		if inFavourites { y += 42 }
		contentSize = CGSize(width: width, height: y + 48)
	}

	/// O(log n + visible items), including all four tiles on a shared grid line.
	func visibleIndices(in rect: CGRect) -> Range<Int> {
		var lower = 0
		var upper = frames.count
		while lower < upper {
			let middle = (lower + upper) / 2
			if frames[middle].maxY <= rect.minY { lower = middle + 1 } else { upper = middle }
		}
		let start = lower
		while lower < frames.count, frames[lower].minY < rect.maxY { lower += 1 }
		return start..<lower
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

	func dropTarget(at point: CGPoint, items: [BrowserSidebarItem]) -> (SidebarTabCollection, UUID?)? {
		guard let insertion = insertion(at: point), items.indices.contains(insertion.index),
		      let collection = items[insertion.index].collection else { return nil }
		let item = items[insertion.index]
		guard item.tabID != nil else { return (collection, nil) } // Empty regions and folder/group headers.
		if !insertion.after { return (collection, item.tabID) }
		let next = insertion.index + 1
		// At a section boundary, "after the last favourite" still means
		// favourite; it must not silently become "before the first pinned tab".
		let before = items.indices.contains(next) && items[next].collection == collection ? items[next].tabID : nil
		return (collection, before)
	}
}
