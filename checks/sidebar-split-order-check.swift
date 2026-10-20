// swiftc -parse-as-library astra/UI/Shell/NativeSidebar/BrowserSidebarLayout.swift astra/UI/Shell/NativeSidebar/BrowserSidebarSplitProjection.swift checks/sidebar-split-order-check.swift -o /tmp/sidebar-split-order-check
import Foundation

enum SidebarTabCollection: Hashable, Sendable {
	case favourite, pinned, normal, folder(UUID), todayGroup(String)
}

@main
struct SidebarSplitOrderCheck {
	static func main() {
		let ids = (0..<5).map { _ in UUID() }
		let tabs = ids.enumerated().map { index, id in
			BrowserSidebarItem(id: "tab-\(index)", tabID: id, collection: .normal)
		}
		let prefix: [BrowserSidebarItem] = [
			.init(id: "favourite", kind: .favourite, isFavourite: true, tabID: UUID(), collection: .favourite),
			.init(id: "pinned", tabID: UUID(), collection: .pinned),
			.init(id: "divider", kind: .divider, collection: .normal)
		]
		let original = prefix + tabs
		for (left, right) in [(1, 3), (3, 1), (1, 2), (0, 4)] {
			let result = BrowserSidebarSplitProjection.collapse(original, leftID: ids[left], rightID: ids[right])
			precondition(Array(result.prefix(prefix.count)) == prefix, "Split must stay below favourites, pinned tabs and divider")
			let expected = tabs.indices.filter { $0 != max(left, right) }.map { index in
				index == min(left, right) ? "split-\(ids[left])-\(ids[right])" : tabs[index].id
			}
			precondition(result.dropFirst(prefix.count).map(\.id) == expected, "Unrelated tab order and first member position must survive either orientation")
			precondition(result.filter { $0.kind == .split }.count == 1)
			precondition(result.first { $0.kind == .split }?.collection == .normal)
		}
		let grouped: [BrowserSidebarItem] = [
			.init(id: "group-a", kind: .group("a")),
			.init(id: "a", tabID: ids[1], collection: .todayGroup("a")),
			.init(id: "group-b", kind: .group("b")),
			.init(id: "b", tabID: ids[3], collection: .todayGroup("b")),
			tabs[4]
		]
		let result = BrowserSidebarSplitProjection.collapse(grouped, leftID: ids[3], rightID: ids[1])
		precondition(result.map(\.id) == ["group-a", "split-\(ids[3])-\(ids[1])", "tab-4"])
		precondition(result[1].collection == .todayGroup("a"), "Split retains the first member's group")
		let hiddenMembers = BrowserSidebarSplitProjection.collapse(prefix, leftID: ids[1], rightID: ids[3])
		precondition(hiddenMembers.first?.kind == .split, "Hidden folder members must retain an accessible split control")
		precondition(Array(hiddenMembers.dropFirst()) == prefix)
		precondition(original == prefix + tabs, "Projection must leave persisted ordering untouched")
		print("Split sidebar order checks passed")
	}
}
