import Foundation

struct BrowserTheme: Codable, Equatable, Sendable {}

struct OpenTab: Identifiable {
	var id: UUID
}

@main
struct TabsSpacesChecks {
	static func main() {
		let favouriteID = id(1)
		let sharedID = id(2)
		let staleID = id(3)
		let pinnedID = id(4)
		let unassignedID = id(5)
		let folderID = id(6)
		let firstSpaceID = id(7)
		let secondSpaceID = id(8)
		let now = Date(timeIntervalSince1970: 100)
		let firstSpace = BrowserSpace(
			id: firstSpaceID,
			tabIDs: [sharedID, sharedID, pinnedID, staleID],
			pinnedTabIDs: [pinnedID, pinnedID, staleID],
			pinnedFolders: [
				PinnedTabFolder(id: folderID, name: "Work", tabIDs: [pinnedID, pinnedID, staleID], modifiedAt: now),
				PinnedTabFolder(id: folderID, name: "Newer", tabIDs: [pinnedID], modifiedAt: now.addingTimeInterval(1)),
				PinnedTabFolder(id: id(9), name: "Projects", tabIDs: [pinnedID, pinnedID], modifiedAt: now.addingTimeInterval(2)),
			],
			selectedTabID: staleID,
			modifiedAt: now
		)
		let secondSpace = BrowserSpace(
			id: secondSpaceID,
			tabIDs: [sharedID],
			selectedTabID: sharedID,
			modifiedAt: now.addingTimeInterval(-1)
		)
		var workspace = BrowserWorkspace(
			spaces: [firstSpace, secondSpace],
			favouriteTabIDs: [favouriteID, favouriteID, sharedID],
			favouritesModifiedAt: now.addingTimeInterval(-2),
			selectedSpaceID: firstSpaceID,
			modifiedAt: now,
			selectionModifiedAt: now
		)
		workspace.reconcileMembership(
			existingTabIDs: [favouriteID, sharedID, pinnedID, unassignedID],
			unassignedTabIDs: [unassignedID]
		)

		assert(workspace.favouriteTabIDs == [favouriteID])
		assert(workspace.spaces[0].tabIDs == [sharedID, pinnedID, unassignedID])
		assert(workspace.spaces[1].tabIDs.isEmpty)
		assert(workspace.spaces[0].pinnedTabIDs == [pinnedID])
		assert(workspace.spaces[0].pinnedFolders.count == 2)
		assert(workspace.spaces[0].pinnedFolders[0].name == "Newer")
		assert(workspace.spaces[0].pinnedFolders[0].tabIDs.isEmpty)
		assert(workspace.spaces[0].pinnedFolders[1].tabIDs == [pinnedID])
		assert(workspace.spaces[0].selectedTabID == sharedID)
		assert(workspace.spaces[0].modifiedAt == now)

		let first = id(10)
		let second = id(11)
		let third = id(12)
		let fourth = id(13)
		assert(BrowserWorkspace.tabSwitchCandidates(
			visibleTabIDs: [first, second, third],
			recentlyUsedTabIDs: [third, first, third],
			selectedTabID: third,
			forward: true
		) == [first, second, third])
		assert(BrowserWorkspace.tabSwitchCandidates(
			visibleTabIDs: [first, second, third],
			recentlyUsedTabIDs: [third, first],
			selectedTabID: third,
			forward: false
		) == [second, first, third])
		assert(BrowserWorkspace.tabSelectionAfterClosing(
			tabID: first,
			normalTabIDs: [first],
			visibleTabIDs: [fourth, first]
		) == fourth)
		assert(BrowserWorkspace.tabSelectionAfterClosing(
			tabID: second,
			normalTabIDs: [first, second, third],
			visibleTabIDs: [first, second, third]
		) == first)
	}

	private static func id(_ value: UInt8) -> UUID {
		UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
	}
}
