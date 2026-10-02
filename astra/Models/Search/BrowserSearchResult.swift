import Foundation

struct BrowserSearchResult: Identifiable {
	enum Kind: String {
		case typed
		case search
		case history
		case bookmark
		case openTab
		case action

		var limit: Int {
			switch self {
				case .typed: 1
				case .search, .history, .bookmark, .openTab: 4
				case .action: 3
			}
		}
	}

	let id: String
	let kind: Kind
	let title: String
	let detail: String
	let symbol: String
	let score: Double
	let destination: String?
	let perform: @MainActor () -> Void

	static func selected(in results: [Self], id: String?, automaticallySelectFirst: Bool) -> Self? {
		if let result = results.first(where: { $0.id == id }) {
			return result
		}
		return automaticallySelectFirst ? results.first : nil
	}

	static func ranked(_ results: [Self]) -> [Self] {
		let sorted = results.sorted {
			if $0.score != $1.score {
				return $0.score > $1.score
			}
			return $0.id < $1.id
		}
		var counts: [Kind: Int] = [:]
		var seen = Set<String>()
		return sorted.filter { result in
			let identity = "\(result.kind.rawValue):\(result.destination ?? result.id)"
			guard seen.insert(identity).inserted,
			      counts[result.kind, default: 0] < result.kind.limit
			else { return false }
			counts[result.kind, default: 0] += 1
			return true
		}
	}
}

struct BrowserSearchEngineDiscovery: Equatable {
	let template: String
	let tabID: UUID
	let controllerID: UUID
	let webViewID: ObjectIdentifier
	let documentID: Int
	let pageURL: URL
	let query: String
	let queryGeneration: Int
	let configuration: String

	func matches(
		tabID: UUID,
		controllerID: UUID,
		webViewID: ObjectIdentifier,
		documentID: Int,
		pageURL: URL,
		query: String,
		queryGeneration: Int,
		configuration: String
	) -> Bool {
		self.tabID == tabID
			&& self.controllerID == controllerID
			&& self.webViewID == webViewID
			&& self.documentID == documentID
			&& self.pageURL == pageURL
			&& self.query == query
			&& self.queryGeneration == queryGeneration
			&& self.configuration == configuration
	}
}

enum BrowserSearchEngineDiscoveryOutcome {
	case found(String)
	case notPublished
	case blocked
	case invalid
	case cancelled
	case failed
}
