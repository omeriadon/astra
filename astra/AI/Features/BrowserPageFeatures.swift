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

	static func preview(
		sourceURL: URL,
		destinationURL: URL,
		onSnapshot: @MainActor (String, BrowserAIPageText) -> Void
	) async throws -> (summary: Summary, page: BrowserAIPageText) {
		let id = UUID()
		let started = ContinuousClock.now
		let model = BrowserAISettings.effectiveModel(BrowserAIFeatureID.linkPreview.model)
		let provider = switch model {
			case .codex: "Codex"
			case .claude: "Claude"
			default: "Default"
		}
		var loaded: ContinuousClock.Instant?
		var prepared: ContinuousClock.Instant?
		var firstSnapshot: ContinuousClock.Instant?
		var firstText: ContinuousClock.Instant?
		func milliseconds(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant?) -> Int {
			guard let end else { return -1 }
			let duration = start.duration(to: end).components
			return Int(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000)
		}
		func record(_ outcome: String) async {
			await BrowserAIUsageLog.shared.record(
				id: id, feature: "Link Preview Timing", provider: provider, event: outcome,
				details: "page_load_ms=\(milliseconds(started, loaded)) context_prepare_ms=\(loaded.map { milliseconds($0, prepared) } ?? -1) request_to_first_snapshot_ms=\(prepared.map { milliseconds($0, firstSnapshot) } ?? -1) request_to_first_text_ms=\(prepared.map { milliseconds($0, firstText) } ?? -1) total_first_text_ms=\(milliseconds(started, firstText)) total_ms=\(milliseconds(started, .now))"
			)
		}
		do {
			let page = try await BrowserAIPageLoader().page(at: destinationURL, forPreview: true)
			loaded = .now
			let context = model == .appleIntelligence ? try await page.limited(to: 1000) : page.previewContext
			try Task.checkCancellation()
			prepared = .now
			let summary = try await BrowserAI.shared.performStreaming(Self(), input: .init(sourceURL: sourceURL, destinationURL: destinationURL, page: context)) { snapshot in
				guard !Task.isCancelled else { return }
				if firstSnapshot == nil, !snapshot.isEmpty {
					firstSnapshot = .now
				}
				if firstText == nil {
					let title = BrowserAIOutput.streamedString("title", in: snapshot)
					let header = BrowserAIOutput.streamedString("header", in: snapshot)
					let plain = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
					if title?.isEmpty == false || header?.isEmpty == false || (!plain.isEmpty && !plain.hasPrefix("{") && !plain.contains("```")) {
						firstText = .now
					}
				}
				onSnapshot(snapshot, page)
			}
			try Task.checkCancellation()
			await record("success")
			return (summary, page)
		} catch {
			await record(Task.isCancelled ? "cancelled" : "failed")
			throw error
		}
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
		if let summary = try? JSONDecoder().decode(Summary.self, from: BrowserAIOutput.jsonData(text)),
		   !summary.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
		   !summary.header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		{
			return Summary(title: summary.title, header: summary.header, bullets: summary.bullets.prefix(5).compactMap { bullet in
				guard !bullet.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
				return Summary.Bullet(text: bullet.text, symbol: BrowserAISymbols.allowed.contains(bullet.symbol) ? bullet.symbol : "text.alignleft")
			})
		}
		let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !value.isEmpty, !value.hasPrefix("{"), !value.hasPrefix("[") else {
			throw BrowserAIError.invalidResponse("The preview response was incomplete. Retry the preview.")
		}
		return Summary(title: "Page Preview", header: value, bullets: [])
	}

	static func streamingSummary(_ text: String, title: String) -> Summary? {
		guard let header = BrowserAIOutput.streamedString("header", in: text), !header.isEmpty else { return nil }
		let bullets = BrowserAIOutput.completedObjects(in: text).compactMap { data -> Summary.Bullet? in
			guard let bullet = try? JSONDecoder().decode(Summary.Bullet.self, from: data) else { return nil }
			return Summary.Bullet(text: bullet.text, symbol: BrowserAISymbols.allowed.contains(bullet.symbol) ? bullet.symbol : "text.alignleft")
		}
		return Summary(title: BrowserAIOutput.streamedString("title", in: text) ?? title, header: header, bullets: Array(bullets.prefix(5)))
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
		let title = BrowserAIOutput.title(text)
		guard BrowserAIOutput.validLine(title, maximumWords: 40) else { throw BrowserAIError.invalidResponse("The AI returned an invalid title. Retry title cleanup.") }
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
			maximumResponseTokens: nil
		)
	}

	func output(from text: String) throws -> [Group] {
		guard let groups = try? JSONDecoder().decode([Group].self, from: BrowserAIOutput.jsonData(text)) else {
			throw BrowserAIError.invalidResponse("The AI did not return tab sections with valid tab identifiers. Retry Tidy Today Tabs.")
		}
		guard !groups.isEmpty, Set(groups.map(\.name)).count == groups.count,
		      groups.allSatisfy({ Self.validSectionName($0.name) && !$0.tabIDs.isEmpty }) else { throw BrowserAIError.invalidResponse("The AI returned empty or duplicate tab sections. Retry Tidy Today Tabs.") }
		return groups
	}

	static func validate(_ groups: [Group], expectedIDs: [UUID]) throws {
		let ids = groups.flatMap(\.tabIDs)
		guard ids.count == expectedIDs.count, Set(ids).count == ids.count,
		      Set(ids) == Set(expectedIDs),
		      Set(groups.map(\.name)).count == groups.count,
		      groups.allSatisfy({ validSectionName($0.name) && !$0.tabIDs.isEmpty }) else { throw BrowserAIError.invalidResponse("The proposed tab sections omitted or repeated tabs. No final organization was applied.") }
	}

	static func validSectionName(_ name: String) -> Bool {
		!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& name.count <= 30
			&& !name.contains(where: \.isNewline)
			&& !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
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

	static func title(_ text: String) -> String {
		text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"`")))
	}

	/// Recover one complete JSON value, including fenced output or explanatory prose.
	static func jsonData(_ text: String) -> Data {
		let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)) != nil {
			return Data(value.utf8)
		}
		for start in value.indices where value[start] == "{" || value[start] == "[" {
			var stack: [Character] = []
			var quoted = false
			var escaped = false
			for index in value[start...].indices {
				let character = value[index]
				if quoted {
					if escaped {
						escaped = false
					} else if character == "\\" {
						escaped = true
					} else if character == "\"" {
						quoted = false
					}
					continue
				}
				if character == "\"" {
					quoted = true
				} else if character == "{" || character == "[" {
					stack.append(character)
				} else if character == "}" || character == "]" {
					guard stack.last == (character == "}" ? "{" : "[") else { break }
					stack.removeLast()
					if stack.isEmpty {
						let data = Data(value[start ... index].utf8)
						if (try? JSONSerialization.jsonObject(with: data)) != nil {
							return data
						}
						break
					}
				}
			}
		}
		return Data(value.utf8)
	}

	/// Complete nested objects only; incomplete streamed objects are never actionable.
	static func completedObjects(in text: String) -> [Data] {
		var starts: [String.Index] = []
		var objects: [Data] = []
		var quoted = false
		var escaped = false
		for index in text.indices {
			let character = text[index]
			if quoted {
				if escaped {
					escaped = false
				} else if character == "\\" {
					escaped = true
				} else if character == "\"" {
					quoted = false
				}
				continue
			}
			if character == "\"" {
				quoted = true
			} else if character == "{" {
				starts.append(index)
			} else if character == "}", let start = starts.popLast() {
				let data = Data(text[start ... index].utf8)
				if (try? JSONSerialization.jsonObject(with: data)) != nil {
					objects.append(data)
				}
			}
		}
		return objects
	}

	/// Decode display-only partial strings without publishing raw JSON syntax.
	static func streamedString(_ key: String, in text: String) -> String? {
		guard let keyRange = text.range(of: "\"" + key + "\""),
		      let colon = text[keyRange.upperBound...].firstIndex(of: ":") else { return nil }
		let suffix = text[text.index(after: colon)...].drop(while: \.isWhitespace)
		guard suffix.first == "\"" else { return nil }
		var encoded = "\""
		var escaped = false
		for character in suffix.dropFirst() {
			encoded.append(character)
			if escaped {
				escaped = false
			} else if character == "\\" {
				escaped = true
			} else if character == "\"" {
				return try? JSONDecoder().decode(String.self, from: Data(encoded.utf8))
			}
		}
		while encoded.count > 1 {
			if let value = try? JSONDecoder().decode(String.self, from: Data((encoded + "\"").utf8)) {
				return value
			}
			encoded.removeLast()
		}
		return ""
	}
}
