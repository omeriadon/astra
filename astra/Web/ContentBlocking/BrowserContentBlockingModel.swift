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

	struct Stored: Codable, Sendable {
		static let version = 1

		var formatVersion = version
		var fileName: String
		var data: Data
		var updatedAt: Date
		var isEnabled: Bool

		static func decodeSupported(_ data: Data) -> Self? {
			guard let stored = try? JSONDecoder().decode(Self.self, from: data),
			      stored.formatVersion == version,
			      stored.data.count <= maximumBytes,
			      !stored.fileName.isEmpty,
			      stored.fileName.utf8.count <= 255,
			      stored.updatedAt.timeIntervalSince1970.isFinite,
			      canRewrite(data) else { return nil }
			return stored
		}

		private static func canRewrite(_ data: Data) -> Bool {
			guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
			return Set(object.keys).isSubset(of: ["formatVersion", "fileName", "data", "updatedAt", "isEnabled"])
		}
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

	static func readBounded(from url: URL) throws -> Data {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		var data = Data()
		while data.count <= maximumBytes {
			let remaining = maximumBytes + 1 - data.count
			guard remaining > 0 else { throw ValidationError.sourceTooLarge }
			let chunk = try handle.read(upToCount: min(64 * 1024, remaining)) ?? Data()
			guard !chunk.isEmpty else { break }
			data.append(chunk)
		}
		guard data.count <= maximumBytes else { throw ValidationError.sourceTooLarge }
		return data
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

	static func originAfterNavigationDecision(
		isMainFrame: Bool,
		disposition: NavigationDisposition,
		currentOrigin: String?,
		destinationOrigin: String?
	) -> String? {
		guard isMainFrame, disposition == .allow else { return currentOrigin }
		return destinationOrigin
	}

	enum NavigationDisposition: Equatable, Sendable {
		case allow
		case cancel
		case download
	}
}
