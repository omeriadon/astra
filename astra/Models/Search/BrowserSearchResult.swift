import Foundation

struct BrowserSearchResult: Identifiable {
	enum Kind: String {
		case typed
		case search
		case history
		case action

		var limit: Int {
			switch self {
				case .typed: 1
				case .search, .history: 4
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
	let perform: @MainActor () -> Void

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
			guard seen.insert(result.id).inserted,
			      counts[result.kind, default: 0] < result.kind.limit
			else { return false }
			counts[result.kind, default: 0] += 1
			return true
		}
	}
}
