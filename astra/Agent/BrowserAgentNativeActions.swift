#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER && !ASTRA_BROWSER_USE_FIXTURE
	import Defaults
	import Foundation
	import MCP
	import Observation

	/// Native browser operations. Browser and WebKit state is accessed only on the UI actor.
	@MainActor
	enum BrowserAgentNativeActions {
		private enum Failure: LocalizedError {
			case argument(String), missing(String), unavailable(String)
			var errorDescription: String? {
				switch self {
					case let .argument(value): "INVALID_ARGUMENT: \(value)"
					case let .missing(value): "NOT_FOUND: \(value)"
					case let .unavailable(value): "UNAVAILABLE: \(value)"
				}
			}
		}

		nonisolated static let tools: [Tool] = {
			let string: Value = .object(["type": .string("string")])
			let bool: Value = .object(["type": .string("boolean")])
			var result: [Tool] = []
			func add(_ name: String, _ description: String, _ fields: [String: Value] = [:], _ required: [String] = [], read: Bool = false) {
				result.append(Tool(name: name, description: description, inputSchema: .object([
					"type": .string("object"), "properties": .object(fields),
					"required": .array(required.map { .string($0) }), "additionalProperties": .bool(false),
				]), annotations: .init(readOnlyHint: read, destructiveHint: ["delete_space", "remove_bookmark", "delete_bookmark", "remove_reading_list_item", "remove_from_reading_list", "delete_download", "delete_boost", "update_boost"].contains(name), openWorldHint: ["search_web", "go_back", "go_forward", "reload_tab", "open_history_entry", "open_reading_list_item", "open_download"].contains(name))))
			}
			let tab = ["tabID": string]
			let window = ["windowID": string]
			let collectionFields = ["windowID": string, "offset": Value.object(["type": .string("integer"), "minimum": .int(0)]), "limit": Value.object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(200)])]
			add("list_windows", "List eligible normal windows and their selected tab IDs.", read: true)
			add("get_active_tab", "Read the active tab in an explicit window.", window, ["windowID"], read: true)
			for name in ["get_tab", "get_tab_state", "get_navigation_history"] {
				add(name, "Read a granted tab and its browser state.", tab, ["tabID"], read: true)
			}
			for name in ["close_tab", "select_tab", "duplicate_tab", "reload_tab", "go_back", "go_forward"] {
				add(name, "Operate on an explicitly granted tab.", tab, ["tabID"])
			}
			add("list_spaces", "List Spaces in an eligible window.", collectionFields, ["windowID"], read: true)
			add("create_space", "Create a Space in an eligible window.", window, ["windowID"])
			add("select_space", "Select a Space in an eligible window.", ["windowID": string, "spaceID": string], ["windowID", "spaceID"])
			add("rename_space", "Rename an existing Space.", ["windowID": string, "spaceID": string, "name": string], ["windowID", "spaceID", "name"])
			add("delete_space", "Delete a Space, moving its tabs into another Space.", ["windowID": string, "spaceID": string], ["windowID", "spaceID"])
			add("move_tab_to_space", "Move a granted tab into a Space.", ["tabID": string, "spaceID": string], ["tabID", "spaceID"])
			add("pin_tab", "Pin a granted tab, or explicitly set its pin state.", ["tabID": string, "pinned": bool], ["tabID"])
			add("set_favourite", "Set favourite membership for a granted tab.", ["tabID": string, "favourite": bool], ["tabID", "favourite"])
			add("list_pinned_folders", "List folders in a Space.", ["windowID": string, "spaceID": string], ["windowID", "spaceID"], read: true)
			add("create_pinned_folder", "Create a pinned folder in a Space.", ["windowID": string, "spaceID": string, "name": string], ["windowID", "spaceID", "name"])
			for name in ["list_bookmarks", "list_reading_list", "list_history", "list_easels", "list_downloads"] {
				add(name, "Read a bounded page of the native browser collection in an eligible window.", collectionFields, ["windowID"], read: true)
			}
			add("add_bookmark", "Bookmark a granted tab.", tab, ["tabID"])
			add("remove_bookmark", "Remove a bookmark.", ["windowID": string, "bookmarkID": string], ["windowID", "bookmarkID"])
			add("add_to_reading_list", "Save a granted tab to Reading List.", tab, ["tabID"])
			add("remove_reading_list_item", "Remove a Reading List item.", ["windowID": string, "itemID": string], ["windowID", "itemID"])
			add("create_easel", "Create an Easel in a window.", window, ["windowID"])
			add("get_easel", "Read a bounded page of Easel document items.", ["windowID": string, "easelID": string, "offset": .object(["type": .string("integer")]), "limit": .object(["type": .string("integer")])], ["windowID", "easelID"], read: true)
			add("list_boosts", "List a bounded page of Astra Boost metadata.", ["offset": .object(["type": .string("integer")]), "limit": .object(["type": .string("integer")])], read: true)
			add("create_boost", "Create a Boost for a domain.", ["domain": string], ["domain"])
			add("set_boost_enabled", "Enable or disable an existing Boost.", ["boostID": string, "enabled": bool], ["boostID", "enabled"])
			add("delete_boost", "Delete an existing Boost.", ["boostID": string], ["boostID"])
			add("cancel_download", "Cancel an in-progress download.", ["windowID": string, "downloadID": string], ["windowID", "downloadID"])
			add("get_media_state", "Read available native media metadata for a granted tab.", tab, ["tabID"], read: true)
			add("get_resource_info", "Read available native resource metadata for a granted tab.", tab, ["tabID"], read: true)
			let integer: Value = .object(["type": .string("integer"), "minimum": .int(0)])
			func extra(_ name: String, _ fields: [String: Value], _ required: [String], read: Bool = false) {
				var fields = fields
				if read {
					fields["offset"] = integer; fields["limit"] = integer; fields["query"] = string
				}
				add(name, "Operate on Astra's native browser model using explicit identities.", fields, required, read: read)
			}
			for name in ["get_space", "list_space_tabs", "list_space_folders"] {
				extra(name, ["windowID": string, "spaceID": string], ["windowID", "spaceID"], read: true)
			}
			extra("get_current_space", window, ["windowID"], read: true)
			extra("create_space_folder", ["windowID": string, "spaceID": string, "name": string], ["windowID", "spaceID", "name"])
			extra("rename_space_folder", ["windowID": string, "folderID": string, "name": string], ["windowID", "folderID", "name"])
			extra("move_tab_to_folder", ["tabID": string, "spaceID": string, "folderID": string], ["tabID", "spaceID", "folderID"])
			extra("move_tab", ["tabID": string, "spaceID": string, "area": string], ["tabID", "spaceID", "area"])
			extra("rename_tab", ["tabID": string, "name": string], ["tabID", "name"])
			for name in ["unpin_tab", "favourite_tab", "unfavourite_tab", "hibernate_tab", "wake_tab", "mute_tab", "unmute_tab"] {
				extra(name, tab, ["tabID"])
			}
			for name in ["get_tab_resource_usage", "get_tab_media_state"] {
				extra(name, tab, ["tabID"], read: true)
			}
			extra("search_bookmarks", window.merging(["query": string]) { _, b in b }, ["windowID", "query"], read: true)
			extra("create_bookmark", ["windowID": string, "name": string, "url": string, "folder": string], ["windowID", "name", "url"])
			for name in ["update_bookmark", "move_bookmark"] {
				extra(name, ["windowID": string, "bookmarkID": string, "name": string, "folder": string, "isFavorite": bool], ["windowID", "bookmarkID"])
			}
			extra("delete_bookmark", ["windowID": string, "bookmarkID": string], ["windowID", "bookmarkID"])
			extra("list_bookmark_folders", window, ["windowID"], read: true)
			extra("create_bookmark_folder", ["windowID": string, "name": string], ["windowID", "name"])
			extra("search_history", ["windowID": string, "query": string], ["windowID", "query"], read: true)
			for name in ["get_history_entry", "open_history_entry"] {
				extra(name, ["windowID": string, "visitID": string], ["windowID", "visitID"], read: name == "get_history_entry")
			}
			for name in ["remove_from_reading_list", "open_reading_list_item"] {
				extra(name, ["windowID": string, "itemID": string], ["windowID", "itemID"])
			}
			for name in ["open_easel", "get_easel_contents", "add_easel_text", "add_easel_link", "add_easel_quote"] {
				extra(name, ["windowID": string, "easelID": string, "tabID": string, "text": string, "url": string, "prefix": string, "suffix": string], ["windowID", "easelID"], read: name == "get_easel_contents")
			}
			extra("get_boost", ["boostID": string], ["boostID"], read: true)
			extra("update_boost", ["boostID": string, "name": string, "domain": string, "css": string, "javascript": string, "enabled": bool], ["boostID"])
			extra("toggle_boost", ["boostID": string], ["boostID"])
			for name in ["get_download", "open_download", "reveal_download", "delete_download", "wait_for_download"] {
				extra(name, ["windowID": string, "downloadID": string, "timeout": .object(["type": .string("number")])], ["windowID", "downloadID"], read: name == "get_download" || name == "wait_for_download")
			}
			for name in ["get_browser_status", "get_download_summary", "get_active_media_tabs"] {
				extra(name, window, ["windowID"], read: true)
			}
			extra("search_web", ["windowID": string, "query": string], ["windowID", "query"])
			return result
		}()

		private static func string(_ args: [String: Value], _ key: String) throws -> String {
			guard case let .string(value)? = args[key], !value.isEmpty else { throw Failure.argument(key) }
			return value
		}

		private static func id(_ args: [String: Value], _ key: String) throws -> UUID {
			guard let value = try UUID(uuidString: string(args, key)) else { throw Failure.argument(key) }
			return value
		}

		private static func boolean(_ args: [String: Value], _ key: String) throws -> Bool {
			guard case let .bool(value)? = args[key] else { throw Failure.argument(key) }
			return value
		}

		private static func browser(_ args: [String: Value]) throws -> Browser {
			let windowID = try id(args, "windowID")
			guard let value = BrowserWindowRegistry.shared.openBrowsers.first(where: { $0.windowID == windowID && !$0.isPrivate && !$0.isMini }) else {
				throw Failure.missing("Eligible window \(windowID)")
			}
			return value
		}

		private static func tabValue(_ tab: BrowserTab, _ browser: Browser) -> Value {
			.object(["tabID": .string(tab.id.uuidString), "windowID": .string(browser.windowID.uuidString),
			         "title": .string(tab.title), "url": .string(tab.currentURL.map { BrowserAddress.withoutCredentials($0).absoluteString } ?? ""),
			         "selected": .bool(browser.selectedTabID == tab.id), "hibernated": .bool(tab.isHibernated)])
		}

		private static func spaceValue(_ space: BrowserSpace) -> Value {
			.object(["spaceID": .string(space.id.uuidString), "name": .string(space.name), "symbol": .string(space.symbol),
			         "tabIDs": .array(space.tabIDs.map { .string($0.uuidString) }),
			         "pinnedTabIDs": .array(space.pinnedTabIDs.map { .string($0.uuidString) })])
		}

		private static func space(_ browser: Browser, _ args: [String: Value]) throws -> BrowserSpace {
			let spaceID = try id(args, "spaceID")
			guard let value = browser.workspace.spaces.first(where: { $0.id == spaceID }) else { throw Failure.missing("Space") }
			return value
		}

		private static func optionalString(_ args: [String: Value], _ key: String) -> String? {
			guard case let .string(value)? = args[key] else { return nil }
			return value
		}

		private static func page(_ values: [Value], _ args: [String: Value]) throws -> Value {
			func integer(_ key: String, _ fallback: Int) throws -> Int {
				guard let value = args[key] else { return fallback }
				guard case let .int(number) = value, number >= 0 else { throw Failure.argument(key) }
				return number
			}
			let offset = try integer("offset", 0)
			let limit = try integer("limit", 100)
			guard (1 ... 200).contains(limit) else { throw Failure.argument("limit must be 1...200") }
			let items = Array(values.dropFirst(offset).prefix(limit))
			let next = offset + items.count
			return .object(["items": .array(items), "offset": .int(offset), "total": .int(values.count), "truncated": .bool(next < values.count), "nextOffset": next < values.count ? .int(next) : .null])
		}

		private static func bookmarkValue(_ value: Bookmark) -> Value {
			.object(["bookmarkID": .string(value.id.uuidString), "name": .string(value.name), "url": .string(BrowserAddress.withoutCredentials(value.url).absoluteString), "folder": .string(value.folder), "isFavorite": .bool(value.isFavorite)])
		}

		private static func downloadValue(_ value: BrowserDownload) -> Value {
			.object(["downloadID": .string(value.id.uuidString), "name": .string(value.name), "status": .string(value.status.rawValue), "progress": .double(value.progress)])
		}

		private static func boostValue(_ value: BrowserBoost) -> Value {
			.object(["boostID": .string(value.id.uuidString), "name": .string(value.name), "domain": value.domain.map(Value.string) ?? .null, "css": .string(value.css), "javascript": .string(value.javascript), "enabled": .bool(value.isEnabled)])
		}

		private static func mutation(_ authorize: () throws -> Void) throws {
			try authorize()
		}

		static func execute(name: String, arguments args: [String: Value],
		                    authorizeTab: (UUID) throws -> (Browser, BrowserTab),
		                    shareTab: (BrowserTab, Browser) -> Void,
		                    revokeTab: (UUID) -> Void,
		                    authorizeNativeMutation: () throws -> Void,
		                    authorizeBoostMutation: () throws -> Void) async throws -> Value
		{
			try Task.checkCancellation()
			let aliases = ["create_space_folder": "create_pinned_folder", "list_space_folders": "list_pinned_folders", "delete_bookmark": "remove_bookmark", "remove_from_reading_list": "remove_reading_list_item", "get_easel_contents": "get_easel", "get_tab_media_state": "get_media_state", "get_tab_resource_usage": "get_resource_info"]
			if let canonical = aliases[name] {
				return try await execute(name: canonical, arguments: args, authorizeTab: authorizeTab, shareTab: shareTab, revokeTab: revokeTab, authorizeNativeMutation: authorizeNativeMutation, authorizeBoostMutation: authorizeBoostMutation)
			}
			switch name {
				case "unpin_tab", "favourite_tab", "unfavourite_tab":
					var values = args
					let pin = name == "unpin_tab"
					values[pin ? "pinned" : "favourite"] = .bool(name == "favourite_tab")
					return try await execute(name: pin ? "pin_tab" : "set_favourite", arguments: values, authorizeTab: authorizeTab, shareTab: shareTab, revokeTab: revokeTab, authorizeNativeMutation: authorizeNativeMutation, authorizeBoostMutation: authorizeBoostMutation)
				case "rename_tab", "hibernate_tab", "wake_tab", "mute_tab", "unmute_tab", "move_tab", "move_tab_to_folder":
					let tabID = try id(args, "tabID")
					let (owner, tab) = try authorizeTab(tabID)
					if name == "wake_tab" {
						tab.wake(); return tabValue(tab, owner)
					}
					if name == "hibernate_tab" {
						owner.hibernateTab(tabID)
						let deadline = ContinuousClock.now.advanced(by: .seconds(2))
						while !tab.isHibernated {
							try Task.checkCancellation()
							_ = try authorizeTab(tabID)
							if ContinuousClock.now >= deadline {
								break
							}
							let signal = BrowserAgentStateSignal()
							withObservationTracking { _ = tab.isHibernated } onChange: { signal.finish() }
							try await signal.wait(until: deadline)
						}
						guard tab.isHibernated else { throw Failure.unavailable("Tab cannot safely hibernate") }
						revokeTab(tabID)
						return tabValue(tab, owner)
					}
					if name == "mute_tab" || name == "unmute_tab" {
						guard let controller = tab.activeController else { throw Failure.unavailable("Page is not loaded") }
						let desired = name == "mute_tab"
						if controller.areMediaElementsMuted != desired {
							controller.toggleMediaElementsMuted()
						}
						let deadline = ContinuousClock.now.advanced(by: .seconds(1))
						while true {
							try Task.checkCancellation()
							_ = try authorizeTab(tabID)
							if controller.areMediaElementsMuted == desired {
								return .object(["muted": .bool(desired)])
							}
							if ContinuousClock.now >= deadline {
								throw Failure.unavailable("Media mute state was not established")
							}
							let signal = BrowserAgentStateSignal()
							withObservationTracking { _ = controller.areMediaElementsMuted } onChange: { signal.finish() }
							try await signal.wait(until: deadline)
						}
					}
					try authorizeNativeMutation()
					if name == "rename_tab" {
						let title = try string(args, "name")
						guard title.utf8.count <= 512 else { throw Failure.argument("name") }
						tab.rename(to: title)
						guard tab.title == title else { throw Failure.unavailable("Tab was not renamed") }
					} else {
						let target = try space(owner, args)
						if name == "move_tab_to_folder" {
							let folderID = try id(args, "folderID")
							guard target.pinnedFolders.contains(where: { $0.id == folderID }) else { throw Failure.missing("Folder in target Space") }
							owner.moveTabs([tabID], to: .pinned, in: target.id, folderID: folderID)
							guard owner.workspace.spaces.first(where: { $0.id == target.id })?.pinnedFolders.first(where: { $0.id == folderID })?.tabIDs.contains(tabID) == true else { throw Failure.unavailable("Tab was not moved into folder") }
						} else {
							let area = try string(args, "area")
							guard ["normal", "pinned", "favourite"].contains(area) else { throw Failure.argument("area") }
							owner.moveTab(tabID, to: area == "pinned" ? .pinned : area == "favourite" ? .favourite : .normal, in: target.id)
							guard owner.workspace.spaces.first(where: { $0.id == target.id })?.tabIDs.contains(tabID) == true || owner.workspace.favouriteTabIDs.contains(tabID) else { throw Failure.unavailable("Tab was not moved") }
						}
						revokeTab(tabID)
					}
					return tabValue(tab, owner)
				case "get_space", "get_current_space", "list_space_tabs", "rename_space_folder", "search_bookmarks", "create_bookmark", "update_bookmark", "move_bookmark", "list_bookmark_folders", "create_bookmark_folder", "search_history", "get_history_entry", "open_history_entry", "open_reading_list_item", "open_easel", "add_easel_text", "add_easel_link", "add_easel_quote", "get_download", "open_download", "reveal_download", "delete_download", "wait_for_download", "get_browser_status", "get_download_summary", "get_active_media_tabs", "search_web":
					let owner = try browser(args)
					switch name {
						case "get_space": return try spaceValue(space(owner, args))
						case "get_current_space": return spaceValue(owner.selectedSpace)
						case "list_space_tabs":
							let target = try space(owner, args)
							return try page(target.tabIDs.compactMap { owner.tab(withID: $0) }.map { tabValue($0, owner) }, args)
						case "rename_space_folder":
							try authorizeNativeMutation()
							let folderID = try id(args, "folderID")
							guard let folderSpace = owner.workspace.spaces.first(where: { $0.pinnedFolders.contains(where: { $0.id == folderID }) }) else { throw Failure.missing("Folder") }
							let previousSpaceID = owner.workspace.selectedSpaceID
							owner.selectSpace(folderSpace.id)
							defer { owner.selectSpace(previousSpaceID) }
							let title = try string(args, "name").trimmingCharacters(in: .whitespacesAndNewlines)
							guard !title.isEmpty, title.utf8.count <= 256 else { throw Failure.argument("name") }
							owner.renamePinnedFolder(folderID, to: title)
							guard owner.workspace.spaces.contains(where: { $0.pinnedFolders.contains(where: { $0.id == folderID && $0.name == title }) }) else { throw Failure.unavailable("Folder was not renamed") }
							return .object(["renamed": .bool(true)])
						case "search_bookmarks":
							let query = try string(args, "query")
							return try page(owner.bookmarks.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query) }.map(bookmarkValue), args)
						case "create_bookmark":
							try authorizeNativeMutation()
							guard let url = try URL(string: string(args, "url")), BrowserEaselDocument.isSafeLink(url) else { throw Failure.argument("url") }
							let title = try string(args, "name")
							let bookmark = Bookmark(name: title, url: BrowserAddress.withoutCredentials(url), folder: optionalString(args, "folder") ?? "")
							owner.importBookmarks([bookmark])
							guard let saved = owner.bookmarks.first(where: { $0.url == bookmark.url }) else { throw Failure.unavailable("Bookmark was not saved") }
							return bookmarkValue(saved)
						case "update_bookmark", "move_bookmark":
							try authorizeNativeMutation()
							let bookmarkID = try id(args, "bookmarkID")
							guard let old = owner.bookmarks.first(where: { $0.id == bookmarkID }) else { throw Failure.missing("Bookmark") }
							let title = optionalString(args, "name") ?? old.name
							let folder = optionalString(args, "folder") ?? old.folder
							let favorite = args["isFavorite"] == nil ? old.isFavorite : try boolean(args, "isFavorite")
							guard title.utf8.count <= 16384, folder.utf8.count <= 4096 else { throw Failure.argument("name or folder") }
							owner.updateBookmark(bookmarkID, name: title, folder: folder, isFavorite: favorite, order: old.order)
							guard let updated = owner.bookmarks.first(where: { $0.id == bookmarkID }), updated.name == title, updated.folder == folder, updated.isFavorite == favorite else { throw Failure.unavailable("Bookmark update was not persisted") }
							return bookmarkValue(updated)
						case "list_bookmark_folders": return try page(Defaults[.bookmarkFolderNames].map(Value.string), args)
						case "create_bookmark_folder":
							try authorizeNativeMutation()
							let title = try string(args, "name")
							owner.createBookmarkFolder(title)
							guard Defaults[.bookmarkFolderNames].contains(title) else { throw Failure.unavailable("Bookmark folder was not created") }
							return .object(["name": .string(title)])
						case "search_history":
							let query = try string(args, "query")
							return try page(owner.recentHistoryVisits.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query) }.map { .object(["visitID": .string($0.id.uuidString), "title": .string($0.title), "url": .string(BrowserAddress.withoutCredentials($0.url).absoluteString), "visitedAt": .string($0.visitedAt.ISO8601Format())]) }, args)
						case "get_history_entry", "open_history_entry":
							let visitID = try id(args, "visitID")
							guard let entry = owner.recentHistoryVisits.first(where: { $0.id == visitID }) else { throw Failure.missing("History entry") }
							if name == "get_history_entry" {
								return .object(["visitID": .string(entry.id.uuidString), "title": .string(entry.title), "url": .string(BrowserAddress.withoutCredentials(entry.url).absoluteString), "visitedAt": .string(entry.visitedAt.ISO8601Format())])
							}
							let tab = owner.openHistoryURL(entry.url, inBackground: false)
							shareTab(tab, owner)
							return tabValue(tab, owner)
						case "open_reading_list_item":
							let itemID = try id(args, "itemID")
							guard let item = owner.readingList.first(where: { $0.id == itemID }) else { throw Failure.missing("Reading List item") }
							owner.openReadingListItem(item, offline: false)
							guard let tab = owner.selectedTab, tab.currentURL == item.url else { throw Failure.unavailable("Reading List item was not opened") }
							shareTab(tab, owner)
							return tabValue(tab, owner)
						case "open_easel", "add_easel_text", "add_easel_link", "add_easel_quote":
							let easelID = try id(args, "easelID")
							guard let tab = owner.tab(withID: easelID), tab.internalPage == .easel else { throw Failure.missing("Easel") }
							if name == "open_easel" {
								owner.selectTab(easelID); guard owner.selectedTabID == easelID else { throw Failure.unavailable("Easel was not opened") }; return tabValue(tab, owner)
							}
							try authorizeNativeMutation()
							let text = optionalString(args, "text") ?? ""
							guard text.utf8.count <= 8192 else { throw Failure.argument("text") }
							if name == "add_easel_quote" {
								let sourceID = try id(args, "tabID")
								let (sourceOwner, source) = try authorizeTab(sourceID)
								guard sourceOwner === owner, let url = source.currentURL else { throw Failure.argument("Quote source window") }
								let quote = BrowserEaselQuote(url: BrowserAddress.withoutCredentials(url), text: text, prefix: optionalString(args, "prefix") ?? "", suffix: optionalString(args, "suffix") ?? "")
								guard quote.isValid else { throw Failure.argument("quote") }
								let old = tab.easelDocument.items.count
								owner.addEaselQuote(quote, to: easelID, from: sourceID)
								guard tab.easelDocument.items.count == old + 1 else { throw Failure.unavailable("Quote source and Easel must belong to the selected Space") }
								return .object(["itemID": .string(tab.easelDocument.items.last!.id.uuidString)])
							}
							var item = BrowserEaselDocument.Item(kind: name == "add_easel_link" ? .link : .text)
							item.text = text
							if name == "add_easel_link" {
								guard let url = try URL(string: string(args, "url")), BrowserEaselDocument.isSafeLink(url) else { throw Failure.argument("url") }
								item.url = BrowserAddress.withoutCredentials(url)
							}
							var document = tab.easelDocument
							document.items.append(item)
							guard tab.updateEasel(document) else { throw Failure.unavailable("Easel item exceeds document limits") }
							return .object(["itemID": .string(item.id.uuidString)])
						case "get_download", "open_download", "reveal_download", "delete_download", "wait_for_download":
							let downloadID = try id(args, "downloadID")
							guard let item = owner.session.downloads.items.first(where: { $0.id == downloadID }) else { throw Failure.missing("Download") }
							if name == "get_download" {
								return downloadValue(item)
							}
							if name == "wait_for_download" {
								let timeout: Double
								switch args["timeout"] { case let .double(value): timeout = value; case let .int(value): timeout = Double(value); case nil: timeout = 30; default: throw Failure.argument("timeout") }
								guard timeout.isFinite, (0 ... 300).contains(timeout) else { throw Failure.argument("timeout") }
								let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
								while true {
									try Task.checkCancellation()
									guard BrowserWindowRegistry.shared.openBrowsers.contains(where: { $0 === owner }), let current = owner.session.downloads.items.first(where: { $0.id == downloadID }) else { throw Failure.missing("Download or window") }
									if ![.downloading, .paused, .finalizing].contains(current.status) {
										return downloadValue(current)
									}
									if ContinuousClock.now >= deadline {
										throw Failure.unavailable("Download wait timed out")
									}
									let signal = BrowserAgentStateSignal()
									withObservationTracking {
										_ = owner.session.downloads.items
										_ = BrowserWindowRegistry.shared.activeBrowserID
										_ = owner.tabs
									} onChange: { signal.finish() }
									try await signal.wait(until: deadline)
								}
							}
							try authorizeNativeMutation()
							if name == "delete_download" {
								owner.session.downloads.delete(downloadID)
								let deadline = ContinuousClock.now.advanced(by: .seconds(2))
								while owner.session.downloads.items.contains(where: { $0.id == downloadID }) {
									try Task.checkCancellation()
									if ContinuousClock.now >= deadline {
										throw Failure.unavailable("Download deletion did not complete")
									}
									let signal = BrowserAgentStateSignal()
									withObservationTracking { _ = owner.session.downloads.items } onChange: { signal.finish() }
									try await signal.wait(until: deadline)
								}
								return .object(["deleted": .bool(true)])
							}
							guard item.status == .completed else { throw Failure.unavailable("Download is not complete") }
							if name == "open_download" {
								owner.session.downloads.open(downloadID)
							} else {
								owner.session.downloads.revealInFolder(downloadID)
							}
							return .object(["requested": .bool(true), "postcondition": .string("Dispatched to the native download manager; external application presentation is not observable")])
						case "get_download_summary":
							return .object(["total": .int(owner.session.downloads.items.count), "active": .int(owner.session.downloads.items.filter { [.downloading, .paused, .finalizing].contains($0.status) }.count), "completed": .int(owner.session.downloads.items.filter { $0.status == .completed }.count)])
						case "get_browser_status": return .object(["windowID": .string(owner.windowID.uuidString), "tabCount": .int(owner.tabs.count), "spaceCount": .int(owner.workspace.spaces.count), "selectedTabID": .string(owner.selectedTabID.uuidString)])
						case "get_active_media_tabs": return try page(owner.tabs.filter { $0.activeController?.isPlayingMedia == true }.map { tabValue($0, owner) }, args)
						case "search_web":
							guard let url = try owner.browserSearchConfiguration.searchURL(for: string(args, "query"), isPrivate: false) else { throw Failure.unavailable("Search provider has no URL") }
							let tab = owner.openHistoryURL(url, inBackground: false)
							shareTab(tab, owner)
							return tabValue(tab, owner)
						default: throw Failure.argument("native action")
					}
				case "get_boost", "update_boost", "toggle_boost":
					let boostID = try id(args, "boostID")
					guard var boost = BrowserBoostStore.shared.boosts.first(where: { $0.id == boostID }) else { throw Failure.missing("Boost") }
					if name == "get_boost" {
						return boostValue(boost)
					}
					try authorizeBoostMutation()
					if name == "toggle_boost" {
						boost.isEnabled.toggle()
					} else {
						if let value = optionalString(args, "name") {
							boost.name = value
						}
						if let value = optionalString(args, "css") {
							boost.css = value
						}
						if let value = optionalString(args, "javascript") {
							boost.javascript = value
						}
						if let value = optionalString(args, "domain") {
							guard let normalized = BrowserBoost.normalizedDomain(value) else { throw Failure.argument("domain") }; boost.domain = normalized
						}
						if args["enabled"] != nil {
							boost.isEnabled = try boolean(args, "enabled")
						}
					}
					guard boost.isValidForSync else { throw Failure.argument("Boost exceeds limits") }
					BrowserBoostStore.shared.update(boost)
					guard BrowserBoostStore.shared.validationMessage == nil, let saved = BrowserBoostStore.shared.boosts.first(where: { $0.id == boostID }), saved.name == boost.name, saved.css == boost.css, saved.javascript == boost.javascript, saved.domain == boost.domain, saved.isEnabled == boost.isEnabled else { throw Failure.unavailable("Boost update rejected") }
					return boostValue(saved)
				case "list_windows":
					return .array(BrowserWindowRegistry.shared.openBrowsers.filter { !$0.isPrivate && !$0.isMini }.map { browser in
						.object(["windowID": .string(browser.windowID.uuidString), "selectedTabID": .string(browser.selectedTabID.uuidString),
						         "tabCount": .int(browser.tabs.count)])
					})
				case "get_active_tab":
					let browser = try browser(args)
					guard let tab = browser.selectedTab else { throw Failure.unavailable("No active tab") }
					_ = try authorizeTab(tab.id)
					return tabValue(tab, browser)
				case "get_tab", "get_tab_state", "get_navigation_history", "close_tab", "select_tab", "duplicate_tab", "reload_tab", "go_back", "go_forward", "move_tab_to_space", "pin_tab", "set_favourite", "add_bookmark", "add_to_reading_list", "get_media_state", "get_resource_info":
					let id = try id(args, "tabID")
					let (browser, tab) = try authorizeTab(id)
					switch name {
						case "get_tab", "get_tab_state": return tabValue(tab, browser)
						case "get_navigation_history":
							let saved = tab.openTab
							return .object(["urls": .array(saved.history.map { .string(BrowserAddress.withoutCredentials($0).absoluteString) }), "index": .int(saved.historyIndex)])
						case "close_tab":
							browser.closeTab(id, confirmed: true)
							guard browser.tab(withID: id) == nil else { throw Failure.unavailable("Tab could not be closed") }
							revokeTab(id)
							return .object(["closed": .bool(true), "tabID": .string(id.uuidString)])
						case "select_tab":
							browser.selectTab(id)
							guard browser.selectedTabID == id else { throw Failure.unavailable("Tab could not be selected") }
							return tabValue(tab, browser)
						case "duplicate_tab":
							guard let duplicated = browser.duplicateTab(id) else { throw Failure.unavailable("Tab cannot be duplicated") }
							shareTab(duplicated, browser)
							return tabValue(duplicated, browser)
						case "reload_tab", "go_back", "go_forward":
							guard let controller = tab.activeController else { throw Failure.unavailable("Tab has no active page") }
							if name == "go_back", !controller.canGoBack {
								throw Failure.unavailable("No previous page")
							}
							if name == "go_forward", !controller.canGoForward {
								throw Failure.unavailable("No next page")
							}
							if name == "reload_tab" {
								controller.reload()
							} else if name == "go_back" {
								controller.goBack()
							} else {
								controller.goForward()
							}
							return .object(["navigationStarted": .bool(true), "tabID": .string(id.uuidString)])
						case "move_tab_to_space":
							try mutation(authorizeNativeMutation)
							let target = try space(browser, args)
							browser.moveTab(id, to: .normal, in: target.id)
							guard browser.workspace.spaces.first(where: { $0.id == target.id })?.tabIDs.contains(id) == true else { throw Failure.unavailable("Tab was not moved") }
							revokeTab(id)
							return .object(["moved": .bool(true), "spaceID": .string(target.id.uuidString), "grantRevoked": .bool(true)])
						case "pin_tab":
							try mutation(authorizeNativeMutation)
							let desired = args["pinned"] == nil ? true : try boolean(args, "pinned")
							let current = browser.workspace.spaces.first(where: { $0.tabIDs.contains(id) })
							guard let current else { throw Failure.unavailable("Tab is not in a Space") }
							if current.pinnedTabIDs.contains(id) != desired {
								browser.moveTab(id, to: desired ? .pinned : .normal, in: current.id)
							}
							guard browser.workspace.spaces.first(where: { $0.id == current.id })?.pinnedTabIDs.contains(id) == desired else { throw Failure.unavailable("Pin state did not change") }
							return .object(["pinned": .bool(desired)])
						case "set_favourite":
							try mutation(authorizeNativeMutation)
							let desired = try boolean(args, "favourite")
							if browser.workspace.favouriteTabIDs.contains(id) != desired {
								browser.moveTab(id, to: desired ? .favourite : .normal)
							}
							guard browser.workspace.favouriteTabIDs.contains(id) == desired else { throw Failure.unavailable("Favourite state did not change") }
							return .object(["favourite": .bool(desired)])
						case "add_bookmark":
							try mutation(authorizeNativeMutation)
							browser.bookmarkTabs([id])
							guard let url = tab.currentURL.map(BrowserAddress.withoutCredentials), let bookmark = browser.bookmarks.first(where: { $0.url == url }) else { throw Failure.unavailable("Page could not be bookmarked") }
							return .object(["bookmarkID": .string(bookmark.id.uuidString)])
						case "add_to_reading_list":
							try mutation(authorizeNativeMutation)
							browser.addToReadingList(tabID: id)
							guard let url = tab.currentURL, let item = browser.readingList.first(where: { $0.url == url }) else { throw Failure.unavailable("Page could not be added to Reading List") }
							return .object(["itemID": .string(item.id.uuidString)])
						case "get_media_state":
							guard let controller = tab.activeController else { throw Failure.unavailable("Page is hibernated or not loaded") }
							_ = await controller.refreshActivity()
							try Task.checkCancellation()
							_ = try authorizeTab(id)
							return .object(["tabID": .string(id.uuidString), "playing": .bool(controller.isPlayingMedia), "muted": .bool(controller.areMediaElementsMuted), "title": .string(controller.mediaTitle ?? ""), "artist": .string(controller.mediaArtist ?? ""), "source": .string("Astra native WebKit activity telemetry")])
						case "get_resource_info":
							return .object(["tabID": .string(id.uuidString), "hibernated": .bool(tab.isHibernated), "loaded": .bool(tab.activeController?.webViewIfLoaded != nil), "memory": .object(["available": .bool(false), "reason": .string("Public WebKit APIs do not expose per-tab process memory; existing private process-ID telemetry is intentionally excluded")])])
						default: throw Failure.argument("Unknown native tab action")
					}
				case "list_spaces", "create_space", "select_space", "rename_space", "delete_space", "list_pinned_folders", "create_pinned_folder", "list_bookmarks", "list_reading_list", "list_history", "list_easels", "list_downloads", "remove_bookmark", "remove_reading_list_item", "create_easel", "get_easel", "cancel_download":
					let browser = try browser(args)
					switch name {
						case "list_spaces": return try page(browser.workspace.spaces.map(spaceValue), args)
						case "create_space":
							try mutation(authorizeNativeMutation)
							let old = Set(browser.workspace.spaces.map(\.id))
							browser.createSpace()
							guard let created = browser.workspace.spaces.first(where: { !old.contains($0.id) }) else { throw Failure.unavailable("Space was not created") }
							return spaceValue(created)
						case "select_space":
							try mutation(authorizeNativeMutation)
							let target = try space(browser, args)
							browser.selectSpace(target.id)
							guard browser.workspace.selectedSpaceID == target.id else { throw Failure.unavailable("Space was not selected") }
							return spaceValue(target)
						case "rename_space":
							try mutation(authorizeNativeMutation)
							let target = try space(browser, args)
							let name = try string(args, "name")
							guard name.utf8.count <= 256 else { throw Failure.argument("name too long") }
							let previouslySelectedSpaceID = browser.workspace.selectedSpaceID
							browser.selectSpace(target.id)
							defer { browser.selectSpace(previouslySelectedSpaceID) }
							browser.renameSelectedSpace(name)
							guard let updated = browser.workspace.spaces.first(where: { $0.id == target.id }), updated.name == name else { throw Failure.unavailable("Space was not renamed") }
							return spaceValue(updated)
						case "delete_space":
							try mutation(authorizeNativeMutation)
							let target = try space(browser, args)
							browser.deleteSpace(target.id)
							guard !browser.workspace.spaces.contains(where: { $0.id == target.id }) else { throw Failure.unavailable("Space was not deleted; at least one Space must remain") }
							target.tabIDs.forEach(revokeTab)
							return .object(["deleted": .bool(true)])
						case "list_pinned_folders":
							let target = try space(browser, args)
							return try page(target.pinnedFolders.map { .object(["folderID": .string($0.id.uuidString), "name": .string($0.name), "tabIDs": .array($0.tabIDs.map { .string($0.uuidString) })]) }, args)
						case "create_pinned_folder":
							try mutation(authorizeNativeMutation)
							let target = try space(browser, args)
							let name = try string(args, "name")
							guard name.utf8.count <= 256 else { throw Failure.argument("name too long") }
							let old = Set(target.pinnedFolders.map(\.id))
							browser.createPinnedFolder(named: name, in: target.id)
							guard let folder = browser.workspace.spaces.first(where: { $0.id == target.id })?.pinnedFolders.first(where: { !old.contains($0.id) }) else { throw Failure.unavailable("Folder was not created") }
							return .object(["folderID": .string(folder.id.uuidString), "name": .string(folder.name)])
						case "list_bookmarks": return try page(browser.bookmarks.map { .object(["bookmarkID": .string($0.id.uuidString), "name": .string($0.name), "url": .string(BrowserAddress.withoutCredentials($0.url).absoluteString), "folder": .string($0.folder)]) }, args)
						case "list_reading_list": return try page(browser.readingList.map { .object(["itemID": .string($0.id.uuidString), "title": .string($0.title), "url": .string(BrowserAddress.withoutCredentials($0.url).absoluteString), "isRead": .bool($0.isRead)]) }, args)
						case "list_history": return try page(browser.recentHistoryVisits.map { .object(["visitID": .string($0.id.uuidString), "title": .string($0.title), "url": .string(BrowserAddress.withoutCredentials($0.url).absoluteString)]) }, args)
						case "list_easels": return try page(browser.tabs.filter { $0.internalPage == .easel }.map { .object(["easelID": .string($0.id.uuidString), "title": .string($0.title), "itemCount": .int($0.easelDocument.items.count)]) }, args)
						case "list_downloads": return try page(browser.session.downloads.items.map { .object(["downloadID": .string($0.id.uuidString), "name": .string($0.name), "status": .string($0.status.rawValue), "progress": .double($0.progress)]) }, args)
						case "remove_bookmark":
							try mutation(authorizeNativeMutation)
							let id = try id(args, "bookmarkID")
							guard browser.bookmarks.contains(where: { $0.id == id }) else { throw Failure.missing("Bookmark") }
							browser.removeBookmark(id)
							return .object(["removed": .bool(!browser.bookmarks.contains(where: { $0.id == id }))])
						case "remove_reading_list_item":
							try mutation(authorizeNativeMutation)
							let id = try id(args, "itemID")
							guard browser.readingList.contains(where: { $0.id == id }) else { throw Failure.missing("Reading List item") }
							browser.removeReadingListItem(id)
							return .object(["removed": .bool(!browser.readingList.contains(where: { $0.id == id }))])
						case "create_easel":
							try mutation(authorizeNativeMutation)
							guard let tab = browser.createEasel() else { throw Failure.unavailable("Easel could not be created") }
							return .object(["easelID": .string(tab.id.uuidString)])
						case "get_easel":
							let id = try id(args, "easelID")
							guard let tab = browser.tab(withID: id), tab.internalPage == .easel else { throw Failure.missing("Easel") }
							let contents = try page(tab.easelDocument.items.map { item in
								var value: [String: Value] = ["itemID": .string(item.id.uuidString), "kind": .string(item.kind.rawValue), "text": .string(String(item.text.prefix(8192))), "textTruncated": .bool(item.text.count > 8192), "x": .double(item.x), "y": .double(item.y), "width": .double(item.width), "height": .double(item.height)]
								if let url = item.url {
									value["url"] = .string(BrowserAddress.withoutCredentials(url).absoluteString)
								}
								if let quote = item.quote {
									value["quote"] = .object(["url": .string(BrowserAddress.withoutCredentials(quote.url).absoluteString), "text": .string(quote.text), "prefix": .string(quote.prefix), "suffix": .string(quote.suffix)])
								}
								if let image = item.imageData {
									value["imageBytes"] = .int(image.count)
								}
								return .object(value)
							}, args)
							return .object(["easelID": .string(id.uuidString), "contents": contents])
						case "cancel_download":
							try mutation(authorizeNativeMutation)
							let id = try id(args, "downloadID")
							guard let item = browser.session.downloads.items.first(where: { $0.id == id }), [.downloading, .paused, .finalizing].contains(item.status) else { throw Failure.missing("Active download") }
							browser.session.downloads.cancel(id)
							guard browser.session.downloads.items.first(where: { $0.id == id })?.status == .cancelled else { throw Failure.unavailable("Download cancellation did not complete") }
							return .object(["cancelled": .bool(true)])
						default: throw Failure.argument("Unknown native browser action")
					}
				case "list_boosts":
					return try page(BrowserBoostStore.shared.boosts.map { .object(["boostID": .string($0.id.uuidString), "name": .string($0.name), "domain": .string($0.domain ?? ""), "enabled": .bool($0.isEnabled)]) }, args)
				case "create_boost":
					try authorizeBoostMutation()
					let domain = try string(args, "domain")
					guard let normalized = BrowserBoost.normalizedDomain(domain) else { throw Failure.argument("domain") }
					let boost = BrowserBoostStore.shared.create(domain: normalized)
					return .object(["boostID": .string(boost.id.uuidString), "domain": .string(normalized)])
				case "set_boost_enabled", "delete_boost":
					try authorizeBoostMutation()
					let id = try id(args, "boostID")
					guard let boost = BrowserBoostStore.shared.boosts.first(where: { $0.id == id }) else { throw Failure.missing("Boost") }
					if name == "delete_boost" {
						BrowserBoostStore.shared.delete(id)
						return .object(["deleted": .bool(!BrowserBoostStore.shared.boosts.contains(where: { $0.id == id }))])
					}
					let enabled = try boolean(args, "enabled")
					if boost.isEnabled != enabled {
						BrowserBoostStore.shared.toggle(id)
					}
					guard BrowserBoostStore.shared.boosts.first(where: { $0.id == id })?.isEnabled == enabled else { throw Failure.unavailable("Boost state did not change") }
					return .object(["enabled": .bool(enabled)])
				default: throw Failure.argument("Unknown native action")
			}
		}
	}
#endif
