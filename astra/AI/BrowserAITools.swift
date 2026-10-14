import CoreFoundation
import Defaults
import Foundation
import SwiftUI
#if os(macOS)
	import AppKit
#else
	import UIKit
#endif

nonisolated enum BrowserAIAction: String, CaseIterable, Identifiable, Sendable {
	case createSpaceFolder = "create_space_folder"
	case createBookmarkFolder = "create_bookmark_folder"
	case createBookmark = "create_bookmark"
	case deleteBookmark = "delete_bookmark"
	case openTab = "open_tab"
	case closeTab = "close_tab"
	case pinTab = "pin_tab"
	case favouriteTab = "favourite_tab"
	case moveTabToFolder = "move_tab_to_folder"
	case renameTab = "rename_tab"
	case selectTab = "select_tab"
	case listTabs = "list_tabs"
	case githubAccount = "github_account"
	case moveTabsToSpace = "move_tabs_to_space"
	case readPage = "read_page"
	case webSearch = "web_search"

	var id: String {
		rawValue
	}

	var title: String {
		switch self {
			case .createSpaceFolder: "Create Space Folders"
			case .createBookmarkFolder: "Create Bookmark Folders"
			case .createBookmark: "Create Bookmarks"
			case .deleteBookmark: "Delete Bookmarks"
			case .openTab: "Create Tabs"
			case .closeTab: "Close Tabs"
			case .pinTab: "Pin or Unpin Tabs"
			case .favouriteTab: "Favourite or Unfavourite Tabs"
			case .moveTabToFolder: "Move Tabs into Folders"
			case .renameTab: "Rename Tabs"
			case .selectTab: "Select Tabs"
			case .listTabs: "List Tabs and Spaces"
			case .githubAccount: "Identify Signed-in GitHub Account"
			case .moveTabsToSpace: "Move Tabs Between Spaces"
			case .readPage: "Read Open Pages"
			case .webSearch: "Search the Web"
		}
	}

	var destructive: Bool {
		self == .deleteBookmark || self == .closeTab
	}

	@MainActor var enabled: Bool {
		get { Self.permissions[rawValue] ?? !destructive }
		nonmutating set {
			var values = Self.permissions
			values[rawValue] = newValue
			if let data = try? JSONEncoder().encode(values), let text = String(data: data, encoding: .utf8) {
				Defaults[.aiBrowserActionPermissions] = text
			}
		}
	}

	@MainActor private static var permissions: [String: Bool] {
		(try? JSONDecoder().decode([String: Bool].self, from: Data(Defaults[.aiBrowserActionPermissions].utf8))) ?? [:]
	}
}

nonisolated struct BrowserAIToolCall: Codable, Sendable {
	let name: String
	let arguments: [String: String]
}

#if !ASTRA_WEBSITE_APP_RUNTIME
	@MainActor
	struct BrowserAIChatTurnFeature: BrowserAIFeature {
		struct Input {
			let context: String
			let question: String
			let catalog: String
			let images: [BrowserAIImage]
			let reasoning: String
			var files: [BrowserAIFile] = []
		}

		nonisolated struct Turn: Decodable, Sendable {
			let response: String
			let actions: [BrowserAIToolCall]
		}

		var model: BrowserAIModel {
			BrowserAIFeatureID.chat.model
		}

		var logName: String {
			"AI Sidebar"
		}

		func request(for input: Input) -> BrowserAIRequest {
			.init(instructions: BrowserAIPrompts.chatTools + "\nEnabled tools and arguments (all argument values are strings):\n" + input.catalog,
			      prompt: "<context>\n\(input.context)\n</context>\nUser request: \(input.question)", maximumResponseTokens: 2048,
			      images: input.images.isEmpty ? nil : input.images, reasoningEffort: input.reasoning, files: input.files.isEmpty ? nil : input.files)
		}

		func output(from text: String) throws -> Turn {
			let data = BrowserAIOutput.jsonData(text)
			if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
				guard let response = object["response"] as? String else { throw BrowserAIError.invalidResponse("The AI returned an action response without readable response text.") }
				let rawActions = object["actions"] ?? []
				guard let actions = rawActions as? [[String: Any]], actions.count <= 5 else { throw BrowserAIError.invalidResponse("The AI returned malformed browser actions. Incomplete or invalid actions were not applied.") }
				let calls = try actions.map { item -> BrowserAIToolCall in
					guard let name = item["name"] as? String, BrowserAIAction(rawValue: name) != nil,
					      let values = item["arguments"] as? [String: Any], values.count <= 8 else { throw BrowserAIError.invalidResponse("The AI returned malformed browser actions. Incomplete or invalid actions were not applied.") }
					var arguments: [String: String] = [:]
					for (key, value) in values {
						let string: String
						if let value = value as? String {
							string = value
						} else if let value = value as? NSNumber {
							string = CFGetTypeID(value) == CFBooleanGetTypeID() ? (value.boolValue ? "true" : "false") : value.stringValue
						} else {
							throw BrowserAIError.invalidResponse("The AI returned malformed browser actions. Incomplete or invalid actions were not applied.")
						}
						guard string.utf8.count <= 8192 else { throw BrowserAIError.invalidResponse("The AI returned malformed browser actions. Incomplete or invalid actions were not applied.") }
						arguments[key] = string
					}
					return BrowserAIToolCall(name: name, arguments: arguments)
				}
				return Turn(response: response, actions: calls)
			}
			guard !String(decoding: data, as: UTF8.self).hasPrefix("{") else { throw BrowserAIError.invalidResponse("The AI returned malformed browser actions. Incomplete or invalid actions were not applied.") }
			guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BrowserAIError.invalidResponse("The AI returned malformed browser actions. Incomplete or invalid actions were not applied.") }
			return Turn(response: text, actions: [])
		}
	}
#endif

@MainActor
struct BrowserAIWebSearchFeature: BrowserAIFeature {
	var model: BrowserAIModel {
		BrowserAIFeatureID.chat.model
	}

	var logName: String {
		"Web Search"
	}

	func request(for input: String) -> BrowserAIRequest {
		.init(instructions: BrowserAIPrompts.webSearch, prompt: input, maximumResponseTokens: 2048, webSearch: true)
	}

	func output(from text: String) throws -> String {
		guard !text.isEmpty else { throw BrowserAIError.emptyResponse }
		return text
	}
}

@MainActor
enum BrowserAITools {
	static func catalog() -> String {
		BrowserAIAction.allCases.filter(\.enabled).map { action in
			let arguments = switch action {
				case .createSpaceFolder, .createBookmarkFolder: "name"
				case .createBookmark: "url, name, optional folder"
				case .deleteBookmark: "bookmarkID"
				case .openTab: "url, optional name"
				case .closeTab: "tabID for one tab; for bulk close use phase=preview with tabIDs (comma-separated) OR domain (exact host), optional keepOwner (GitHub repository owner), then phase=apply with planID"
			case .selectTab, .readPage: "tabID"
			case .listTabs: "optional spaceID (UUID, current or all), offset, limit (1–100)"
			case .githubAccount: "no arguments"
			case .moveTabsToSpace: "phase=preview with tabIDs (comma-separated) and destinationSpaceID; then phase=apply with planID"
				case .pinTab, .favouriteTab: "tabID, enabled (true or false)"
				case .moveTabToFolder: "tabID, folderID"
				case .renameTab: "tabID, name"
				case .webSearch: "query"
			}
			return "\(action.rawValue): \(arguments)"
		}.joined(separator: "\n")
	}

	static func inventory(_ browser: Browser) -> String {
		let tabs = browser.visibleTabs.map { "tabID=\($0.id) title=\($0.title) url=\($0.currentURL?.absoluteString ?? "")" }
		let folders = browser.selectedSpace.pinnedFolders.map { "folderID=\($0.id) name=\($0.name)" }
		let bookmarks = browser.bookmarks.map { "bookmarkID=\($0.id) name=\($0.name) folder=\($0.folder) url=\($0.url.absoluteString)" }
		let spaces = browser.workspace.spaces.map { "spaceID=\($0.id) name=\($0.name)" }.joined(separator: "\n")
		return "Current space: \(browser.selectedSpace.name) (\(browser.selectedSpace.id))\nAvailable spaces:\n\(spaces)\n" + (tabs + folders + bookmarks).joined(separator: "\n")
	}

	static func execute(_ call: BrowserAIToolCall, browser: Browser, spaceID: UUID, model: BrowserAIModel) async throws -> String {
		guard Defaults[.aiFeaturesEnabled], !browser.isPrivate, browser.selectedSpace.id == spaceID,
		      let action = BrowserAIAction(rawValue: call.name), action.enabled else { throw BrowserAIError.toolDenied }
		#if os(macOS)
			let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.25)
		#else
			let animation: Animation? = UIAccessibility.isReduceMotionEnabled ? nil : .smooth(duration: 0.25)
		#endif
		let arguments = call.arguments
		func name() throws -> String {
			guard let value = arguments["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value.utf8.count <= 500 else { throw BrowserAIError.invalidRequest }
			return value
		}
		func url() throws -> URL {
			guard let value = arguments["url"], let url = BrowserHomepage.validURL(value), url.user == nil, url.password == nil else { throw BrowserAIError.invalidRequest }
			return url
		}
		func tab() throws -> BrowserTab {
			guard let id = arguments["tabID"].flatMap(UUID.init(uuidString:)), let tab = browser.visibleTabs.first(where: { $0.id == id }), tab.internalPage == nil else { throw BrowserAIError.pageUnavailable }
			return tab
		}
		switch action {
			case .createSpaceFolder:
				try withAnimation(animation) { try browser.createPinnedFolder(named: name()) }
			case .createBookmarkFolder:
				try withAnimation(animation) { try browser.createBookmarkFolder(name()) }
			case .createBookmark:
				let destination = try url()
				let folder = arguments["folder"] ?? ""
				guard folder.utf8.count <= 500 else { throw BrowserAIError.invalidRequest }
				if let existing = browser.bookmarks.first(where: { $0.url == destination }) {
					return "Already bookmarked as \(existing.id)."
				}
				try withAnimation(animation) { try browser.importBookmarks([Bookmark(name: name(), url: destination, folder: folder)]) }
			case .deleteBookmark:
				guard let id = arguments["bookmarkID"].flatMap(UUID.init(uuidString:)), browser.bookmarks.contains(where: { $0.id == id }) else { throw BrowserAIError.invalidRequest }
				withAnimation(animation) { browser.removeBookmark(id) }
			case .openTab:
				let opened = try withAnimation(animation) { try browser.openHistoryURL(url(), inBackground: true) }
				if let name = arguments["name"], !name.isEmpty {
					withAnimation(animation) { opened.rename(to: String(name.prefix(200))) }
				}
				return "Created tab \(opened.id)."
			case .closeTab:
				if arguments["phase"] != nil {
					return try bulkAction(arguments, kind: .close, browser: browser)
				}
				let target = try tab()
				withAnimation(animation) { browser.closeTab(target.id) }
				return browser.tabs.contains(where: { $0.id == target.id }) ? "The tab remains open or hibernated; closing was not completed." : "Closed tab \(target.id)."
			case .pinTab, .favouriteTab:
				let target = try tab()
				guard ["true", "false"].contains(arguments["enabled"] ?? "") else { throw BrowserAIError.invalidRequest }
				let pinned = browser.selectedSpace.pinnedTabIDs.contains(target.id)
				let favourite = browser.workspace.favouriteTabIDs.contains(target.id)
				if action == .favouriteTab, pinned, !BrowserAIAction.pinTab.enabled {
					throw BrowserAIError.toolDenied
				}
				if action == .pinTab, favourite, !BrowserAIAction.favouriteTab.enabled {
					throw BrowserAIError.toolDenied
				}
				if arguments["enabled"] == "false", !(action == .pinTab ? pinned : favourite) {
					return "The tab already has the requested state."
				}
				withAnimation(animation) { browser.moveTab(target.id, to: arguments["enabled"] == "false" ? .normal : action == .pinTab ? .pinned : .favourite) }
			case .moveTabToFolder:
				let target = try tab()
				guard let id = arguments["folderID"].flatMap(UUID.init(uuidString:)), browser.selectedSpace.pinnedFolders.contains(where: { $0.id == id }) else { throw BrowserAIError.invalidRequest }
				guard browser.selectedSpace.pinnedTabIDs.contains(target.id) || BrowserAIAction.pinTab.enabled else { throw BrowserAIError.toolDenied }
				withAnimation(animation) {
					browser.moveTab(target.id, to: .pinned)
					browser.movePinnedTab(target.id, toFolder: id)
				}
			case .renameTab:
				try withAnimation(animation) { try tab().rename(to: name()) }
			case .selectTab: try browser.selectTab(tab().id)
			case .listTabs:
				return try listTabs(arguments, in: browser)
			case .githubAccount:
				return try await githubAccount(in: browser, originSpaceID: spaceID)
			case .moveTabsToSpace:
				return try bulkAction(arguments, kind: .move, browser: browser)
			case .readPage:
				guard let controller = try tab().activeController else { throw BrowserAIError.pageUnavailable }
				return try await BrowserAIPageText.extract(from: controller).prompt
			case .webSearch:
				guard let query = arguments["query"], !query.isEmpty else { throw BrowserAIError.invalidRequest }
				return try await BrowserAI.shared.perform(BrowserAIWebSearchFeature(), input: query, model: model)
		}
		return "Completed \(action.title)."
	}

	// Plans capture the browser's exact tab identity, URL, membership and pin state.
	// Preview creates no side effects. Apply is single-use and rejects stale state
	// before the first mutation; the model cannot submit unreviewed tab IDs to apply.
	private enum BulkKind {
		case close
		case move
	}

	private struct PlannedTab {
		let id: UUID
		let url: String
		let sourceSpaceID: UUID?
		let pinned: Bool
		let favourite: Bool
		let title: String
	}

	private struct BulkPlan {
		let kind: BulkKind
		let windowID: UUID
		let originatingSpaceID: UUID
		let destinationSpaceID: UUID?
		let tabs: [PlannedTab]
		let createdAt: Date
	}

	private static var bulkPlans: [UUID: BulkPlan] = [:]


	/// Read the signed-in account from an already-loaded GitHub main document.
	/// No new network request, cookie access, local file access, or guessed owner.
	/// GitHub may change its metadata: a missing or contradictory result is unknown.
	private static func githubAccount(in browser: Browser, originSpaceID: UUID) async throws -> String {
		guard BrowserAIAction.readPage.enabled else { throw BrowserAIError.toolDenied }
		var found = Set<String>()
		for tab in browser.tabs {
			guard tab.internalPage == nil, tab.currentURL?.host?.lowercased() == "github.com",
			      let webView = tab.activeController?.webViewIfLoaded,
			      webView.url?.host?.lowercased() == "github.com", !webView.isLoading else { continue }
			let script = "return document.querySelector('meta[name=\"user-login\"]')?.getAttribute('content') || '';"
			guard let result = try? await webView.callAsyncJavaScript(
				script, arguments: [:], in: nil, contentWorld: .defaultClient
			), let owner = result as? String, (1...39).contains(owner.count),
				owner.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { continue }
			guard !browser.isPrivate, browser.selectedSpace.id == originSpaceID else { throw BrowserAIError.toolDenied }
			found.insert(owner.lowercased())
		}
		guard found.count == 1, let owner = found.first else {
			return "GitHub account unknown: no unambiguous signed-in account metadata found in loaded github.com tabs. Ask the user for the repository owner; do not guess."
		}
		return "Verified from an open GitHub document: signed-in GitHub account owner=\(owner). Use this exact owner for keepOwner."
	}

	private static func requestedIDs(_ value: String?) throws -> [UUID] {
		guard let value, value.utf8.count <= 8192 else { throw BrowserAIError.invalidRequest }
		let raw = value.split(separator: ",", omittingEmptySubsequences: false)
		guard !raw.isEmpty, raw.count <= 100 else { throw BrowserAIError.invalidRequest }
		var seen = Set<UUID>()
		return try raw.map { text in
			guard let id = UUID(uuidString: String(text).trimmingCharacters(in: .whitespacesAndNewlines)),
			      seen.insert(id).inserted else { throw BrowserAIError.invalidRequest }
			return id
		}
	}

	private static func listTabs(_ arguments: [String: String], in browser: Browser) throws -> String {
		let scope = arguments["spaceID"] ?? "all"
		let spaceID: UUID?
		if scope == "all" {
			spaceID = nil
		} else if scope == "current" {
			spaceID = browser.selectedSpace.id
		} else {
			guard let id = UUID(uuidString: scope), browser.workspace.spaces.contains(where: { $0.id == id }) else {
				throw BrowserAIError.invalidRequest
			}
			spaceID = id
		}
		let offset = arguments["offset"].flatMap(Int.init) ?? 0
		let limit = arguments["limit"].flatMap(Int.init) ?? 50
		guard (arguments["offset"] == nil || arguments["offset"].flatMap(Int.init) != nil),
		      (arguments["limit"] == nil || arguments["limit"].flatMap(Int.init) != nil),
		      offset >= 0, (1...100).contains(limit) else { throw BrowserAIError.invalidRequest }
		var rows: [String] = []
		let spaces = browser.workspace.spaces.filter { spaceID == nil || $0.id == spaceID }
		for space in spaces {
			for id in space.tabIDs {
				guard let tab = browser.tab(withID: id), tab.internalPage == nil else { continue }
				let pin = space.pinnedTabIDs.contains(id) ? "pinned" : "normal"
				rows.append("spaceID=\(space.id) space=\(clean(space.name)) tabID=\(id) type=\(pin) title=\(clean(tab.title)) url=\(tab.currentURL?.absoluteString ?? "")")
			}
		}
		if spaceID == nil || spaceID == browser.selectedSpace.id {
			for id in browser.workspace.favouriteTabIDs {
				guard let tab = browser.tab(withID: id), tab.internalPage == nil else { continue }
				rows.append("spaceID=global type=favourite tabID=\(id) title=\(clean(tab.title)) url=\(tab.currentURL?.absoluteString ?? "")")
			}
		}
		let page = rows.dropFirst(offset).prefix(limit)
		let header = "Tabs total=\(rows.count) offset=\(offset) shown=\(page.count) nextOffset=\(offset + page.count < rows.count ? String(offset + page.count) : "none")."
		return header + "\n" + page.joined(separator: "\n")
	}

	private static func clean(_ value: String) -> String {
		String(value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").prefix(240))
	}

	private static func snapshot(_ id: UUID, in browser: Browser) throws -> PlannedTab {
		guard let tab = browser.tab(withID: id), tab.internalPage == nil,
		      let url = tab.currentURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
			throw BrowserAIError.pageUnavailable
		}
		let space = browser.workspace.spaces.first(where: { $0.tabIDs.contains(id) })
		let favourite = browser.workspace.favouriteTabIDs.contains(id)
		guard space != nil || favourite else { throw BrowserAIError.pageUnavailable }
		return .init(id: id, url: url.absoluteString, sourceSpaceID: space?.id,
		             pinned: space?.pinnedTabIDs.contains(id) ?? false, favourite: favourite, title: tab.title)
	}

	private static func sameTab(_ expected: PlannedTab, in browser: Browser) -> Bool {
		guard let current = try? snapshot(expected.id, in: browser) else { return false }
		return current.url == expected.url && current.sourceSpaceID == expected.sourceSpaceID
			&& current.pinned == expected.pinned && current.favourite == expected.favourite
	}

	private static func bulkAction(_ arguments: [String: String], kind: BulkKind, browser: Browser) throws -> String {
		let now = Date()
		bulkPlans = bulkPlans.filter { now.timeIntervalSince($0.value.createdAt) < 180 }
		switch arguments["phase"] {
			case "preview":
				let ids: [UUID]
				var destination: UUID?
				if kind == .move {
					guard let target = arguments["destinationSpaceID"].flatMap(UUID.init(uuidString:)),
					      browser.workspace.spaces.contains(where: { $0.id == target }) else {
						throw BrowserAIError.invalidRequest
					}
					destination = target
					ids = try requestedIDs(arguments["tabIDs"])
				} else if let rawDomain = arguments["domain"] {
					let domain = rawDomain.lowercased()
					guard domain.utf8.count <= 253, !domain.isEmpty,
					      domain.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
					      !domain.hasPrefix("."), !domain.hasSuffix(".") else { throw BrowserAIError.invalidRequest }
					let owner = arguments["keepOwner"]
					if let owner {
						guard domain == "github.com", (1...39).contains(owner.count),
						      owner.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
							throw BrowserAIError.invalidRequest
						}
					}
					ids = browser.visibleTabs.filter { tab in
						guard tab.internalPage == nil, let url = tab.currentURL,
						      url.host?.lowercased() == domain else { return false }
						if let owner {
							let components = url.pathComponents.filter { $0 != "/" }
							if components.count >= 2 && components[0].caseInsensitiveCompare(owner) == .orderedSame {
								return false
							}
						}
						return true
					}.map(\.id)
				} else {
					guard arguments["keepOwner"] == nil else { throw BrowserAIError.invalidRequest }
					ids = try requestedIDs(arguments["tabIDs"])
				}
				guard !ids.isEmpty else { return "No matching tabs; nothing to change." }
				guard ids.count <= 100 else { throw BrowserAIError.toolLimit }
				let tabs = try ids.map { try snapshot($0, in: browser) }
				if kind == .close {
					let visible = Set(browser.visibleTabs.map(\.id))
					guard tabs.allSatisfy({ visible.contains($0.id) }) else { throw BrowserAIError.toolDenied }
					try checkClosable(tabs, in: browser)
				} else if let destination {
					guard tabs.allSatisfy({ $0.sourceSpaceID != destination || $0.favourite }) else {
						throw BrowserAIError.invalidResponse("One or more tabs already belong to the destination space.")
					}
					guard !tabs.contains(where: { $0.favourite }) || BrowserAIAction.favouriteTab.enabled else {
						throw BrowserAIError.toolDenied
					}
				}
				let token = UUID()
				if bulkPlans.count >= 20 { bulkPlans.removeAll() }
				bulkPlans[token] = .init(kind: kind, windowID: browser.windowID,
				                       originatingSpaceID: browser.selectedSpace.id,
				                       destinationSpaceID: destination, tabs: tabs, createdAt: now)
				let items = tabs.map { "\($0.id) [\(clean($0.title))] \($0.url)" }.joined(separator: "\n")
				return "Preview only; no tabs changed. planID=\(token) count=\(tabs.count) destinationSpaceID=\(destination?.uuidString ?? "none"). Apply using phase=apply, planID. Targets:\n\(items)"
			case "apply":
				guard let token = arguments["planID"].flatMap(UUID.init(uuidString:)),
				      let plan = bulkPlans.removeValue(forKey: token),
				      plan.kind == kind, plan.windowID == browser.windowID,
				      plan.originatingSpaceID == browser.selectedSpace.id,
				      now.timeIntervalSince(plan.createdAt) < 180 else {
					throw BrowserAIError.invalidResponse("This tab action plan expired or is not valid in the current space. List and preview again.")
				}
				guard plan.tabs.allSatisfy({ sameTab($0, in: browser) }) else {
					throw BrowserAIError.invalidResponse("Tabs or URLs changed since preview. No changes were applied; preview again.")
				}
				if kind == .close {
					let visible = Set(browser.visibleTabs.map(\.id))
					guard plan.tabs.allSatisfy({ visible.contains($0.id) }) else { throw BrowserAIError.toolDenied }
					try checkClosable(plan.tabs, in: browser)
					var closed: [UUID] = []
					for item in plan.tabs {
						if item.favourite { browser.moveTab(item.id, to: .normal, in: browser.selectedSpace.id) }
						if item.pinned { browser.moveTab(item.id, to: .normal, in: item.sourceSpaceID) }
						browser.closeTab(item.id)
						guard browser.tab(withID: item.id) == nil else {
							return "Partial result: closed \(closed.count)/\(plan.tabs.count). Failed tabID=\(item.id); remaining tabs were not touched."
						}
						closed.append(item.id)
					}
					return "Closed \(closed.count) of \(plan.tabs.count) tabs; verified each ID is no longer open."
				}
				guard let destination = plan.destinationSpaceID,
				      browser.workspace.spaces.contains(where: { $0.id == destination }) else { throw BrowserAIError.toolDenied }
				let selected = plan.tabs.first(where: { $0.id == browser.selectedTabID })
				// Moving the selected tab with Browser.moveTab maintains the space/selection
				// invariant; batch the remainder to minimize SwiftUI and persistence churn.
				if let selected {
					browser.moveTab(selected.id, to: selected.pinned ? .pinned : .normal, in: destination)
				}
				let remaining = plan.tabs.filter { $0.id != selected?.id }
				let pinned = remaining.filter(\.pinned).map(\.id)
				let normal = remaining.filter { !$0.pinned }.map(\.id)
				if !pinned.isEmpty { browser.moveTabs(pinned, to: .pinned, in: destination) }
				if !normal.isEmpty { browser.moveTabs(normal, to: .normal, in: destination) }
				let moved = plan.tabs.filter {
					browser.workspace.spaces.first(where: { $0.id == destination })?.tabIDs.contains($0.id) == true
				}
				return "Moved \(moved.count) of \(plan.tabs.count) tabs to spaceID=\(destination)."
			default:
				throw BrowserAIError.invalidRequest
		}
	}

	private static func checkClosable(_ items: [PlannedTab], in browser: Browser) throws {
		guard !items.contains(where: { $0.pinned }) || BrowserAIAction.pinTab.enabled,
		      !items.contains(where: { $0.favourite }) || BrowserAIAction.favouriteTab.enabled else {
			throw BrowserAIError.toolDenied
		}
		for item in items {
			guard let tab = browser.tab(withID: item.id) else { throw BrowserAIError.pageUnavailable }
			let controllers = [tab.controller].compactMap(\.self) + tab.peeks.map(\.controller)
			guard !controllers.contains(where: { $0.hasUnsavedChanges || $0.requiresMediaTeardownConfirmation }) else {
				throw BrowserAIError.invalidResponse("Tab \(item.id) has unsaved changes or protected media. Bulk close aborted without changing any tabs.")
			}
		}
	}

}
