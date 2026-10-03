import Foundation

enum BrowserSearchMatching {
	nonisolated static func normalized(_ text: String) -> String {
		text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Exact > prefix > words > substring > typo/abbreviation.
	nonisolated static func score(_ query: String, in text: String) -> Double {
		let query = normalized(query)
		let text = normalized(text)
		guard !query.isEmpty, !text.isEmpty else { return 0 }
		if query == text {
			return 1
		}
		if text.hasPrefix(query) {
			return 0.92
		}
		if text.contains(query) {
			return 0.78
		}
		let queryWords = query.split(whereSeparator: \.isWhitespace).map(String.init)
		let textWords = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
		let scores = queryWords.map { word in
			textWords.map { wordScore(word, in: $0) }.max() ?? 0
		}
		guard scores.allSatisfy({ $0 > 0 }) else { return 0 }
		return scores.reduce(0, +) / Double(scores.count)
	}

	private nonisolated static func wordScore(_ query: String, in word: String) -> Double {
		if query == word {
			return 0.9
		}
		if word.hasPrefix(query) {
			return 0.85
		}
		if word.contains(query) {
			return 0.72
		}
		// ponytail: one-edit typos and compact abbreviations; broaden tolerance if real queries require it.
		if query.count >= 4, abs(query.count - word.count) <= 1,
		   editDistance(query, word) <= 1
		{
			return 0.62
		}
		guard query.count >= 3, Double(query.count) / Double(word.count) >= 0.5 else { return 0 }
		var remaining = query[...]
		for character in word where remaining.first == character {
			remaining = remaining.dropFirst()
		}
		return remaining.isEmpty ? 0.5 : 0
	}

	private nonisolated static func editDistance(_ lhs: String, _ rhs: String) -> Int {
		let lhs = Array(lhs)
		let rhs = Array(rhs)
		var previousPrevious: [Int] = []
		var previous = Array(0 ... rhs.count)
		for (row, character) in lhs.enumerated() {
			var current = [row + 1]
			for (column, other) in rhs.enumerated() {
				current.append(min(
					current[column] + 1,
					previous[column + 1] + 1,
					previous[column] + (character == other ? 0 : 1)
				))
				if row > 0, column > 0,
				   character == rhs[column - 1], lhs[row - 1] == other
				{
					current[column + 1] = min(current[column + 1], previousPrevious[column - 1] + 1)
				}
			}
			previousPrevious = previous
			previous = current
		}
		return previous[rhs.count]
	}
}
