import Foundation
import Observation
import WebKit

enum BrowserUsageLimitsProvider: String, CaseIterable, Codable, Sendable {
	case none
	case codex
	case claude

	var title: String {
		switch self {
			case .none: "None"
			case .codex: "Codex"
			case .claude: "Claude"
		}
	}
}

enum BrowserUsageCookiePolicy {
	static func matchesDomain(host: String, cookieDomain: String) -> Bool {
		let domain = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
		return host == domain || host.hasSuffix(".\(domain)")
	}

	static func matchesPath(urlPath: String, cookiePath: String) -> Bool {
		urlPath == cookiePath
			|| (urlPath.hasPrefix(cookiePath) && cookiePath.hasSuffix("/"))
			|| urlPath.hasPrefix(cookiePath + "/")
	}
}

struct BrowserUsageWindow: Equatable, Sendable {
	let title: String
	let usedPercent: Double
	let resetAt: Date?

	var remainingPercent: Double {
		max(0, 100 - usedPercent)
	}
}

enum BrowserUsageLimitsError: LocalizedError, Equatable, Sendable {
	case unauthorized
	case forbidden
	case rateLimited
	case unavailable
	case invalidResponse
	case network

	var errorDescription: String? {
		switch self {
			case .unauthorized: "Sign in to this provider in Astra first."
			case .forbidden: "The provider denied access to usage limits."
			case .rateLimited: "The provider temporarily rate-limited this request."
			case .unavailable: "Usage limits are unavailable for this account."
			case .invalidResponse: "The provider returned an unreadable usage response."
			case .network: "The usage request could not be completed."
		}
	}
}

@MainActor
@Observable
final class BrowserUsageLimitsStore {
	private let dataStore: WKWebsiteDataStore
	private var refreshTask: Task<Void, Never>?
	private var generation = 0
	private var consumers = Set<UUID>()

	private(set) var provider: BrowserUsageLimitsProvider = .none
	private(set) var windows: [BrowserUsageWindow] = []
	private(set) var error: BrowserUsageLimitsError?
	private(set) var isRefreshing = false
	private(set) var updatedAt: Date?

	init(dataStore: WKWebsiteDataStore) {
		self.dataStore = dataStore
	}

	func start(provider: BrowserUsageLimitsProvider, consumerID: UUID) {
		guard provider != .none else {
			stop(consumerID: consumerID)
			return
		}
		consumers.insert(consumerID)
		if self.provider == provider, refreshTask != nil {
			return
		}
		if self.provider != provider {
			stopAll()
		}
		refreshTask?.cancel()
		refreshTask = nil
		self.provider = provider
		let generation = generation
		refreshTask = Task { [weak self] in
			while !Task.isCancelled {
				let nextRefresh = Date().addingTimeInterval(120)
				guard self != nil else { break }
				await self?.refreshNow(provider: provider, generation: generation)
				do {
					try await Task.sleep(for: .seconds(max(0, nextRefresh.timeIntervalSinceNow)))
				} catch {
					break
				}
			}
			await MainActor.run {
				guard let self, self.generation == generation else { return }
				self.refreshTask = nil
			}
		}
	}

	func stop(consumerID: UUID) {
		consumers.remove(consumerID)
		if consumers.isEmpty {
			stopAll()
		}
	}

	private func stopAll() {
		generation += 1
		refreshTask?.cancel()
		refreshTask = nil
		provider = .none
		windows = []
		error = nil
		isRefreshing = false
		updatedAt = nil
	}

	private func refreshNow(provider: BrowserUsageLimitsProvider, generation: Int) async {
		guard self.provider == provider, self.generation == generation else { return }
		isRefreshing = true
		defer {
			if self.generation == generation {
				isRefreshing = false
			}
		}
		do {
			let values = try await BrowserUsageLimitsClient(dataStore: dataStore).fetch(provider)
			guard !Task.isCancelled, self.generation == generation, self.provider == provider else { return }
			windows = values
			error = nil
			updatedAt = Date()
		} catch is CancellationError {
			return
		} catch let error as BrowserUsageLimitsError {
			guard self.generation == generation, self.provider == provider else { return }
			self.error = error
			windows = []
		} catch is DecodingError {
			guard self.generation == generation, self.provider == provider else { return }
			self.error = .invalidResponse
			windows = []
		} catch {
			guard self.generation == generation, self.provider == provider else { return }
			self.error = .network
			windows = []
		}
	}
}

private struct BrowserUsageLimitsClient {
	let dataStore: WKWebsiteDataStore

	func fetch(_ provider: BrowserUsageLimitsProvider) async throws -> [BrowserUsageWindow] {
		switch provider {
			case .none: []
			case .codex: try await fetchCodex()
			case .claude: try await fetchClaude()
		}
	}

	private func fetchCodex() async throws -> [BrowserUsageWindow] {
		let response: (data: Data, response: HTTPURLResponse)
		do {
			response = try await get(URL(string: "https://chatgpt.com/backend-api/wham/usage")!, host: "chatgpt.com")
		} catch BrowserUsageLimitsError.unauthorized {
			let session = try await get(URL(string: "https://chatgpt.com/api/auth/session")!, host: "chatgpt.com")
			let auth = try JSONDecoder().decode(CodexSession.self, from: session.data)
			guard let token = auth.accessToken,
			      !token.isEmpty,
			      token.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace && $0.value >= 0x20 && $0.value != 0x7F })
			else { throw BrowserUsageLimitsError.unauthorized }
			response = try await get(URL(string: "https://chatgpt.com/backend-api/wham/usage")!, host: "chatgpt.com", authorization: token)
		}
		let usage = try JSONDecoder().decode(CodexUsage.self, from: response.data)
		guard let rateLimit = usage.rateLimit else { throw BrowserUsageLimitsError.unavailable }
		let values = [rateLimit.primaryWindow, rateLimit.secondaryWindow]
		let windows = values.enumerated().compactMap { index, window -> BrowserUsageWindow? in
			guard let window else { return nil }
			return BrowserUsageWindow(
				title: window.limitWindowSeconds.map(Self.codexTitle) ?? (index == 0 ? "Primary window" : "Secondary window"),
				usedPercent: window.usedPercent,
				resetAt: window.resetAt.map(Date.init(timeIntervalSince1970:))
			)
		}
		guard !windows.isEmpty else { throw BrowserUsageLimitsError.unavailable }
		return windows
	}

	private func fetchClaude() async throws -> [BrowserUsageWindow] {
		let organizationsResponse = try await get(URL(string: "https://claude.ai/api/organizations")!, host: "claude.ai")
		let organizations = try JSONDecoder().decode([ClaudeOrganization].self, from: organizationsResponse.data)
		let lastActiveOrganization = await cookieValue(named: "lastActiveOrg", for: "claude.ai")
		let organization = lastActiveOrganization.flatMap { value in
			organizations.first { $0.uuid == value }
		} ?? organizations.first(where: { $0.capabilities?.contains("chat") == true }) ?? organizations.first
		guard let organization else { throw BrowserUsageLimitsError.unavailable }
		guard UUID(uuidString: organization.uuid) != nil else { throw BrowserUsageLimitsError.invalidResponse }
		let usageURL = URL(string: "https://claude.ai")!
			.appendingPathComponent("api")
			.appendingPathComponent("organizations")
			.appendingPathComponent(organization.uuid)
			.appendingPathComponent("usage")
		let response = try await get(usageURL, host: "claude.ai")
		let usage = try JSONDecoder().decode(ClaudeUsage.self, from: response.data)
		let values = [
			usage.fiveHour.map { BrowserUsageWindow(title: "5-hour", usedPercent: $0.utilization, resetAt: $0.resetsAt) },
			usage.sevenDay.map { BrowserUsageWindow(title: "7-day", usedPercent: $0.utilization, resetAt: $0.resetsAt) },
			usage.sevenDaySonnet.map { BrowserUsageWindow(title: "7-day Sonnet", usedPercent: $0.utilization, resetAt: $0.resetsAt) },
			usage.sevenDayOpus.map { BrowserUsageWindow(title: "7-day Opus", usedPercent: $0.utilization, resetAt: $0.resetsAt) },
		].compactMap(\.self)
		guard !values.isEmpty else { throw BrowserUsageLimitsError.unavailable }
		return values
	}

	private func get(_ url: URL, host: String, authorization: String? = nil) async throws -> (data: Data, response: HTTPURLResponse) {
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.httpShouldHandleCookies = false
		request.timeoutInterval = 30
		try await request.setValue(cookieHeader(for: url, host: host), forHTTPHeaderField: "Cookie")
		if let authorization {
			request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
		}
		let session = URLSession(configuration: .ephemeral, delegate: BrowserUsageRedirectDelegate(), delegateQueue: nil)
		defer { session.invalidateAndCancel() }
		let (data, response): (Data, URLResponse)
		do {
			(data, response) = try await session.data(for: request)
		} catch {
			if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
				throw CancellationError()
			}
			throw BrowserUsageLimitsError.network
		}
		try Task.checkCancellation()
		guard let response = response as? HTTPURLResponse else { throw BrowserUsageLimitsError.invalidResponse }
		switch response.statusCode {
			case 200 ..< 300: return (data, response)
			case 401: throw BrowserUsageLimitsError.unauthorized
			case 403: throw BrowserUsageLimitsError.forbidden
			case 429: throw BrowserUsageLimitsError.rateLimited
			default: throw BrowserUsageLimitsError.invalidResponse
		}
	}

	private func cookieHeader(for url: URL, host: String) async throws -> String {
		let cookies = await dataStore.httpCookieStore.allCookies()
		let now = Date()
		return cookies.filter { cookie in
			let domainMatches = BrowserUsageCookiePolicy.matchesDomain(host: host, cookieDomain: cookie.domain)
			let pathMatches = BrowserUsageCookiePolicy.matchesPath(urlPath: url.path, cookiePath: cookie.path)
			let secure = !cookie.isSecure || url.scheme == "https"
			return domainMatches && pathMatches && secure && (cookie.expiresDate == nil || cookie.expiresDate! > now)
		}.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
	}

	private func cookieValue(named name: String, for host: String) async -> String? {
		await (dataStore.httpCookieStore.allCookies()).first {
			let validExpiry = $0.expiresDate == nil || $0.expiresDate! > Date()
			return $0.name == name && validExpiry && BrowserUsageCookiePolicy.matchesDomain(host: host, cookieDomain: $0.domain)
		}?.value
	}

	private static func codexTitle(_ seconds: Int) -> String {
		if seconds % 86400 == 0 {
			return "\(seconds / 86400)-day"
		}
		if seconds % 3600 == 0 {
			return "\(seconds / 3600)-hour"
		}
		return "\(seconds / 60)-minute"
	}
}

private final class BrowserUsageRedirectDelegate: NSObject, URLSessionTaskDelegate {
	func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse, newRequest _: URLRequest, completionHandler: @Sendable @escaping (URLRequest?) -> Void) {
		completionHandler(nil)
	}
}

private struct CodexSession: Decodable {
	let accessToken: String?
}

struct CodexUsage: Decodable {
	let rateLimit: RateLimit?

	enum CodingKeys: String, CodingKey {
		case rateLimit = "rate_limit"
	}

	struct RateLimit: Decodable {
		let primaryWindow: Window?
		let secondaryWindow: Window?

		enum CodingKeys: String, CodingKey {
			case primaryWindow = "primary_window"
			case secondaryWindow = "secondary_window"
		}
	}

	struct Window: Decodable {
		let usedPercent: Double
		let limitWindowSeconds: Int?
		let resetAt: TimeInterval?

		enum CodingKeys: String, CodingKey {
			case usedPercent = "used_percent"
			case limitWindowSeconds = "limit_window_seconds"
			case resetAt = "reset_at"
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			let value = try container.decode(Double.self, forKey: .usedPercent)
			guard value.isFinite, (0 ... 100).contains(value) else {
				throw DecodingError.dataCorruptedError(forKey: .usedPercent, in: container, debugDescription: "Usage percentage is outside 0...100")
			}
			usedPercent = value
			limitWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .limitWindowSeconds)
			resetAt = try container.decodeIfPresent(TimeInterval.self, forKey: .resetAt)
		}
	}
}

struct ClaudeOrganization: Decodable {
	let uuid: String
	let capabilities: Set<String>?
}

struct ClaudeUsage: Decodable {
	let fiveHour: Window?
	let sevenDay: Window?
	let sevenDaySonnet: Window?
	let sevenDayOpus: Window?

	enum CodingKeys: String, CodingKey {
		case fiveHour = "five_hour"
		case sevenDay = "seven_day"
		case sevenDaySonnet = "seven_day_sonnet"
		case sevenDayOpus = "seven_day_opus"
	}

	struct Window: Decodable {
		let utilization: Double
		let resetsAt: Date?

		enum CodingKeys: String, CodingKey {
			case utilization
			case resetsAt = "resets_at"
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			let value = try container.decode(Double.self, forKey: .utilization)
			guard value.isFinite, (0 ... 100).contains(value) else {
				throw DecodingError.dataCorruptedError(forKey: .utilization, in: container, debugDescription: "Usage percentage is outside 0...100")
			}
			utilization = value
			if let value = try container.decodeIfPresent(String.self, forKey: .resetsAt) {
				let formatter = ISO8601DateFormatter()
				formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
				resetsAt = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
			} else {
				resetsAt = nil
			}
		}
	}
}
