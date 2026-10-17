// Minimal host models for exercising the production MCP server without user data.
// These fixtures do not replace the separate checks against real WebKit DOM actions.
import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserWindowRegistry {
	static let shared = BrowserWindowRegistry()
	var openBrowsers: [Browser] = []
	var activeBrowser: Browser? {
		openBrowsers.first
	}

	func ownsTab(_ id: UUID, in browser: Browser) -> Bool {
		browser.tabs.contains { $0.id == id }
	}
}

@MainActor
final class Browser {
	let windowID = UUID()
	var isPrivate = false
	var isMini = false
	var tabs: [BrowserTab] = []
	func openHistoryURL(_ url: URL, inBackground _: Bool) -> BrowserTab {
		let tab = BrowserTab(url: url)
		tabs.append(tab)
		return tab
	}
}

@MainActor
final class BrowserTab {
	let id = UUID()
	var internalPage: String?
	let controller: BrowserController?
	var activeController: BrowserController? {
		controller
	}

	var currentURL: URL? {
		controller?.url
	}

	var copyableURL: URL? {
		currentURL
	}

	var title: String {
		"Fixture"
	}

	init(url: URL) {
		controller = BrowserController(url: url)
	}
}

@MainActor
final class BrowserController {
	let id = UUID()
	var navigationIdentifier = 0
	var url: URL
	var committedURL: URL? {
		url
	}

	var readerHTML: String?
	var isLoading = false
	var hasCurrentPageDocument = true
	var webViewIfLoaded: WKWebView? {
		nil
	}

	init(url: URL) {
		self.url = url
	}

	func load(_ destination: URL) {
		url = destination
		navigationIdentifier += 1
	}

	func captureScreenshot() async throws -> BrowserScreenshot {
		throw CocoaError(.coderInvalidValue)
	}
}

struct BrowserScreenshot {
	let image: NSImage
}

@MainActor
enum BrowserAddress {
	static func withoutCredentials(_ url: URL) -> URL {
		var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
		components.user = nil
		components.password = nil
		return components.url!
	}
}

struct BrowserAIPageText {
	let title: String
	let url: URL
	let text: String
	@MainActor
	static func extract(from controller: BrowserController) async throws -> Self {
		try await Task.sleep(for: .milliseconds(300))
		return Self(title: "Fixture", url: controller.url, text: "fixture-content")
	}
}
