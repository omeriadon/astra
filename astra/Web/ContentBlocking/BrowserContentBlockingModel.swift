import CryptoKit
import Foundation

nonisolated enum BrowserContentBlockingRuleSource {
	static let maximumBytes = 2 * 1024 * 1024
	static let maximumRuleCount = 50000
	static let maximumPatternBytes = 4096

	static var builtInRules: [[String: Any]] {
		// Adapted from Search's Shield.swift; see SEARCH-SHIELD-LICENSE.txt.
		let domains = [
			"doubleclick.net", "googlesyndication.com", "googleadservices.com",
			"googletagservices.com", "google-analytics.com", "googletagmanager.com",
			"adservice.google.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org",
			"criteo.com", "criteo.net", "taboola.com", "outbrain.com", "rubiconproject.com",
			"pubmatic.com", "openx.net", "casalemedia.com", "smartadserver.com",
			"sharethrough.com", "indexww.com", "bidswitch.net", "33across.com", "teads.tv",
			"moatads.com", "adroll.com", "scorecardresearch.com", "quantserve.com",
			"chartbeat.com", "hotjar.com", "mouseflow.com", "fullstory.com", "clarity.ms",
			"mixpanel.com", "amplitude.com", "segment.com", "segment.io", "branch.io",
			"appsflyer.com", "adjust.com", "analytics.tiktok.com", "connect.facebook.net",
			"ads-twitter.com", "analytics.twitter.com",
		]
		let slots = [
			".adsbygoogle", "ins.adsbygoogle", "[id^=\"google_ads_\"]",
			"[id^=\"div-gpt-ad\"]", "[id^=\"taboola-\"]", "#taboola-below-article",
			"iframe[src*=\"doubleclick.net\"]", "iframe[src*=\"googlesyndication\"]",
			"iframe[src*=\"amazon-adsystem\"]", ".ad-slot", ".ad-slot-container",
			".top-banner-ad-container", ".ad-leaderboard", ".ad-billboard", ".ad-giga",
			".ad-mpu", ".ad-mrec", ".ad-unit", ".adunit", ".adslot", ".dfp-ad", ".gpt-ad", ".w_ad",
		]
		let slotsBySite: [(sites: [String], selector: String)] = [
			(["*as.com", "*elpais.com"], ".ad"),
			(["*theguardian.com"], ".top-fronts-banner-ad-container"),
			(["*independent.co.uk", "*the-independent.com"], "#billboard-wrapper"),
			(["*cnn.com"], ".ad-slot-header__wrapper"),
		]
		var rules: [[String: Any]] = domains.map { domain in
			let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
			return [
				"trigger": [
					"url-filter": "^https?://([^/:?#]+\\.)?\(escaped)(:[0-9]+)?/",
					"load-type": ["third-party"],
				],
				"action": ["type": "block"],
			]
		}
		rules.append([
			"trigger": ["url-filter": ".*"],
			"action": ["type": "css-display-none", "selector": slots.joined(separator: ", ")],
		])
		rules += slotsBySite.map { entry in
			[
				"trigger": ["url-filter": ".*", "if-domain": entry.sites],
				"action": ["type": "css-display-none", "selector": entry.selector],
			]
		}
		return rules
	}

	static let builtInData = (try? JSONSerialization.data(withJSONObject: builtInRules, options: [.sortedKeys])) ?? Data()

	#if DEBUG
		static let builtInRulesAreValid: Void = {
			assert((try? validate(builtInData)) != nil)
			let trigger = builtInRules[0]["trigger"] as! [String: Any]
			let regex = try! NSRegularExpression(pattern: trigger["url-filter"] as! String)
			for url in ["https://doubleclick.net/ad", "https://ads.doubleclick.net:8443/ad"] {
				assert(regex.firstMatch(in: url, range: NSRange(location: 0, length: url.utf16.count)) != nil)
			}
			for url in ["https://doubleclick.net.evil.test/ad", "https://notdoubleclick.net/ad"] {
				assert(regex.firstMatch(in: url, range: NSRange(location: 0, length: url.utf16.count)) == nil)
			}
		}()
	#endif

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
			      let type = action["type"] as? String
			else {
				throw ValidationError.invalidRule
			}
			guard ["block", "block-cookies", "css-display-none", "ignore-previous-rules", "make-https"].contains(type) else {
				throw ValidationError.unsupportedAction
			}
			if type == "css-display-none" {
				guard let selector = action["selector"] as? String,
				      !selector.isEmpty,
				      selector.utf8.count <= 16384
				else {
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
		if disposition == .redirect {
			return nil
		}
		guard isMainFrame, disposition == .allow else { return currentOrigin }
		return destinationOrigin
	}

	enum NavigationDisposition: Equatable, Sendable {
		case allow
		case cancel
		case download
		case redirect
	}
}
