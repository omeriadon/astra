import Foundation

/// Value-owned by one tab or peek controller. WebKit's internal list is not authoritative.
struct BrowserHistory {
	private(set) var entries: [URL]
	private(set) var index: Int
	private var addsEntry = false

	var currentURL: URL? {
		entries.isEmpty ? nil : entries[index]
	}

	var canGoBack: Bool {
		index > 0
	}

	var canGoForward: Bool {
		index + 1 < entries.count
	}

	init(entries: [URL] = [], index: Int = 0, initialURL: URL? = nil) {
		self.entries = entries.isEmpty ? initialURL.map { [$0] } ?? [] : entries
		self.index = self.entries.isEmpty ? 0 : min(max(index, 0), self.entries.count - 1)
	}

	mutating func beginVisit() {
		addsEntry = true
	}

	mutating func cancelVisit() {
		addsEntry = false
	}

	mutating func select(_ destination: Int) -> URL? {
		guard entries.indices.contains(destination), destination != index else { return nil }
		addsEntry = false
		index = destination
		return entries[index]
	}

	mutating func record(_ url: URL) {
		if entries.isEmpty {
			entries.append(url)
			index = 0
		} else if addsEntry, currentURL != url {
			entries.removeSubrange((index + 1)...)
			entries.append(url)
			index = entries.count - 1
		} else {
			entries[index] = url
		}
		addsEntry = false
	}
}
