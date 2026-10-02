import CryptoKit
import Foundation

nonisolated enum BrowserContentBlockingRuleSource {
	static let maximumBytes = 2 * 1024 * 1024
	static let maximumRuleCount = 50_000
	static let maximumPatternBytes = 4_096

	struct Validated: Equatable, Sendable {
		let data: Data
		let ruleCount: Int
		let identifier: String
	}

	enum ValidationError: Error {
		case sourceTooLarge
		case invalidJSON
		case invalidRuleCount
		case invalidRule
		case unsupportedAction
	}

	static func validate(_ data: Data) throws -> Validated {
		guard !data.isEmpty, data.count <= maximumBytes else {
			throw ValidationError.sourceTooLarge
		}
		guard let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
			throw ValidationError.invalidJSON
		}
		guard !rules.isEmpty, rules.count <= maximumRuleCount else {
			throw ValidationError.invalidRuleCount
		}

		for rule in rules {
			guard let trigger = rule["trigger"] as? [String: Any],
			      let pattern = trigger["url-filter"] as? String,
			      !pattern.isEmpty,
			      pattern.utf8.count <= maximumPatternBytes,
			      !pattern.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
			      let action = rule["action"] as? [String: Any],
			      let type = action["type"] as? String else {
				throw ValidationError.invalidRule
			}
			guard ["block", "block-cookies", "css-display-none", "ignore-previous-rules", "make-https"].contains(type) else {
				throw ValidationError.unsupportedAction
			}
			if type == "css-display-none" {
				guard let selector = action["selector"] as? String,
				      !selector.isEmpty,
				      selector.utf8.count <= 16_384 else {
					throw ValidationError.invalidRule
				}
			}
		}

		let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
		return Validated(
			data: data,
			ruleCount: rules.count,
			identifier: "astra.user-content-rules.\(digest)"
		)
	}

	static func lastGood(
		current: Validated?,
		candidate: Validated,
		compiledIdentifier: String?
	) -> Validated? {
		guard compiledIdentifier == candidate.identifier else { return current }
		return candidate
	}

	static func shouldApply(enabled: Bool, hasCompiledList: Bool, isSiteException: Bool) -> Bool {
		enabled && hasCompiledList && !isSiteException
	}
}
