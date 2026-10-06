import Foundation

@MainActor
struct BrowserLinkSummaryFeature: BrowserAIFeature {
	struct Input {
		let sourceURL: URL
		let destinationURL: URL
		let page: BrowserAIPageText
	}

	nonisolated struct Summary: Decodable, Sendable {
		let title: String
		let header: String
		struct Bullet: Decodable, Sendable {
			let text: String
			let symbol: String
		}

		let bullets: [Bullet]
	}

	var model: BrowserAIModel {
		BrowserAIFeatureID.linkPreview.model
	}

	var logName: String {
		"Link Previews"
	}

	func request(for input: Input) -> BrowserAIRequest {
		let sourceURL = BrowserAddress.withoutCredentials(input.sourceURL)
		let destinationURL = BrowserAddress.withoutCredentials(input.destinationURL)
		let query = Self.searchQuery(from: sourceURL)
		return BrowserAIRequest(
			instructions: BrowserAIPrompts.linkPreview + "\nAllowed SF Symbols: " + BrowserAISymbols.names.joined(separator: ", "),
			prompt: "Source page URL: \(sourceURL.absoluteString)\nPreviewed link URL: \(destinationURL.absoluteString)\nSearch query: \(query ?? "None supplied")\n\(input.page.prompt)",
			maximumResponseTokens: 512
		)
	}

	private static func searchQuery(from url: URL) -> String? {
		guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery else { return nil }
		for pair in query.split(separator: "&") {
			let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
			guard parts.count == 2,
			      let name = String(parts[0]).removingPercentEncoding,
			      ["q", "query", "search", "search_query", "p"].contains(name.lowercased()) else { continue }
			return String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
		}
		return nil
	}

	func output(from text: String) throws -> Summary {
		let summary = try JSONDecoder().decode(Summary.self, from: BrowserAIOutput.jsonData(text))
		guard BrowserAIOutput.validLine(summary.title, maximumWords: 30),
		      BrowserAIOutput.validLine(summary.header, maximumWords: 25),
		      (1 ... 5).contains(summary.bullets.count),
		      summary.bullets.allSatisfy({ BrowserAIOutput.validLine($0.text, maximumWords: 20) && BrowserAISymbols.allowed.contains($0.symbol) }) else { throw BrowserAIError.emptyResponse }
		return summary
	}
}

@MainActor
struct BrowserTabTitleFeature: BrowserAIFeature {
	var logName: String {
		"Clean Tab Titles"
	}

	var model: BrowserAIModel {
		BrowserAIFeatureID.tabTitles.model
	}

	func request(for input: BrowserAIPageText) -> BrowserAIRequest {
		BrowserAIRequest(
			instructions: BrowserAIPrompts.cleanTitle,
			prompt: input.prompt,
			maximumResponseTokens: 64
		)
	}

	func output(from text: String) throws -> String {
		let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard BrowserAIOutput.validLine(title, maximumWords: 7) else { throw BrowserAIError.emptyResponse }
		return title
	}
}

@MainActor
struct BrowserTabGroupingFeature: BrowserAIFeature {
	var logName: String {
		"Tidy Today Tabs"
	}

	nonisolated struct Group: Codable, Equatable, Identifiable, Sendable {
		var id: String {
			name
		}

		let name: String
		let tabIDs: [UUID]
	}

	nonisolated struct Tab: Encodable, Sendable {
		let id: UUID
		let title: String
		let url: String
	}

	var model: BrowserAIModel {
		BrowserAIFeatureID.tabGroups.model
	}

	func request(for input: [Tab]) throws -> BrowserAIRequest {
		try BrowserAIRequest(
			instructions: BrowserAIPrompts.tabGroups,
			prompt: String(decoding: JSONEncoder().encode(input), as: UTF8.self),
			maximumResponseTokens: 2048
		)
	}

	func output(from text: String) throws -> [Group] {
		let groups = try JSONDecoder().decode([Group].self, from: BrowserAIOutput.jsonData(text))
		guard !groups.isEmpty, Set(groups.map(\.name)).count == groups.count,
		      groups.allSatisfy({ BrowserAIOutput.validLine($0.name, maximumWords: 4) && !$0.tabIDs.isEmpty }) else { throw BrowserAIError.emptyResponse }
		return groups
	}

	static func validate(_ groups: [Group], expectedIDs: [UUID]) throws {
		let ids = groups.flatMap(\.tabIDs)
		guard ids.count == expectedIDs.count, Set(ids).count == ids.count,
		      Set(ids) == Set(expectedIDs) else { throw BrowserAIError.emptyResponse }
	}
}

@MainActor
struct BrowserPageAnswerFeature: BrowserAIFeature {
	var logName: String {
		feature.title
	}

	struct Input {
		let question: String
		let context: String
		var images: [BrowserAIImage] = []
	}

	let feature: BrowserAIFeatureID
	var model: BrowserAIModel {
		feature.model
	}

	func request(for input: Input) -> BrowserAIRequest {
		BrowserAIRequest(
			instructions: BrowserAIPrompts.pageAnswer,
			prompt: "<context>\n\(input.context)\n</context>\nQuestion: \(input.question)",
			maximumResponseTokens: 2048,
			images: input.images.isEmpty ? nil : input.images
		)
	}

	func output(from text: String) throws -> String {
		let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !answer.isEmpty else { throw BrowserAIError.emptyResponse }
		return answer
	}
}

nonisolated enum BrowserAIOutput {
	static func validLine(_ text: String, maximumWords: Int) -> Bool {
		!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& !text.contains(where: \.isNewline)
			&& text.split(whereSeparator: \.isWhitespace).count <= maximumWords
			&& text.utf8.count <= 1024
			&& !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
	}

	static func jsonData(_ text: String) -> Data {
		var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if value.hasPrefix("```"), let first = value.firstIndex(of: "\n"), let last = value.range(of: "```", options: .backwards), first < last.lowerBound {
			value = String(value[value.index(after: first) ..< last.lowerBound])
		}
		return Data(value.utf8)
	}
}
