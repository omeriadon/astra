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
				case .closeTab, .selectTab, .readPage: "tabID"
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
		return "Current space: \(browser.selectedSpace.name)\n" + (tabs + folders + bookmarks).joined(separator: "\n")
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
			case .readPage:
				guard let controller = try tab().activeController else { throw BrowserAIError.pageUnavailable }
				return try await BrowserAIPageText.extract(from: controller).prompt
			case .webSearch:
				guard let query = arguments["query"], !query.isEmpty else { throw BrowserAIError.invalidRequest }
				return try await BrowserAI.shared.perform(BrowserAIWebSearchFeature(), input: query, model: model)
		}
		return "Completed \(action.title)."
	}
}
