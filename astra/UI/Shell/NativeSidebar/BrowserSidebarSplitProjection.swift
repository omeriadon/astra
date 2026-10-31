import Foundation

/// A split replaces its first sidebar member in place. Pane orientation must
/// never move the pair ahead of unrelated tabs or into another sidebar section.
enum BrowserSidebarSplitProjection {
	static func collapse(_ items: [BrowserSidebarItem], leftID: UUID, rightID: UUID) -> [BrowserSidebarItem] {
		let memberIDs: Set<UUID> = [leftID, rightID]
		var inserted = false
		let collapsed = items.compactMap { item -> BrowserSidebarItem? in
			guard let id = item.tabID, memberIDs.contains(id) else { return item }
			guard !inserted else { return nil }
			inserted = true
			return BrowserSidebarItem(id: "split-\(leftID)-\(rightID)", kind: .split, height: 28, collection: item.collection)
		}
		// Both tabs can live in collapsed pinned folders. Keep the active split
		// accessible when neither member currently has a visible sidebar row.
		guard inserted else {
			return [BrowserSidebarItem(id: "split-\(leftID)-\(rightID)", kind: .split, height: 28)] + items
		}
		// A group that contained only the second member no longer has a row.
		let occupiedGroups = Set(collapsed.compactMap { item -> String? in
			guard item.kind == .tab || item.kind == .split,
			      case let .todayGroup(id)? = item.collection else { return nil }
			return id
		})
		return collapsed.filter { item in
			if case let .group(id) = item.kind { return occupiedGroups.contains(id) }
			return true
		}
	}
}
