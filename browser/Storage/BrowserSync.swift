import AuthenticationServices
import Defaults
import Foundation
import Observation

@MainActor
@Observable
final class BrowserSync {
	static let shared = BrowserSync()

	private(set) var isSignedIn: Bool
	private(set) var isSyncing = false
	private(set) var lastSync: Date?
	private(set) var errorDescription: String?

	@ObservationIgnored private weak var browser: Browser?
	@ObservationIgnored private var sessionToken: String?
	@ObservationIgnored private var scheduledSync: Task<Void, Never>?
	@ObservationIgnored private var syncRequestedWhileBusy = false
	@ObservationIgnored private var knownSettings: [String: Data]
	@ObservationIgnored private var settingVersions: [String: Date]
	@ObservationIgnored private let deviceID: UUID

	private init() {
		sessionToken = try? BrowserSessionStore.load()
		isSignedIn = sessionToken != nil
		let storedVersions = UserDefaults.standard.dictionary(forKey: "syncSettingVersions") as? [String: Double] ?? [:]
		settingVersions = storedVersions.mapValues(Date.init(timeIntervalSince1970:))
		knownSettings = (try? Self.readSettings()) ?? [:]
		if let storedID = UserDefaults.standard.string(forKey: "syncDeviceID"),
		   let id = UUID(uuidString: storedID)
		{
			deviceID = id
		} else {
			let id = UUID()
			UserDefaults.standard.set(id.uuidString, forKey: "syncDeviceID")
			deviceID = id
		}
	}

	func attach(_ browser: Browser) {
		self.browser = browser
		if isSignedIn {
			Task { await syncNow() }
		}
	}

	func settingsDidChange() {
		do {
			let current = try Self.readSettings()
			for key in Defaults.Keys.syncedSettingNames where current[key] != knownSettings[key] {
				settingVersions[key] = .now
			}
			guard current != knownSettings else { return }
			knownSettings = current
			UserDefaults.standard.set(
				settingVersions.mapValues(\.timeIntervalSince1970),
				forKey: "syncSettingVersions"
			)
			scheduleSync()
		} catch {
			errorDescription = error.localizedDescription
		}
	}

	func scheduleSync() {
		guard isSignedIn, browser != nil else { return }
		scheduledSync?.cancel()
		scheduledSync = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(2))
			guard !Task.isCancelled else { return }
			await self?.syncNow()
		}
	}

	func signIn(result: Result<ASAuthorization, any Error>) async {
		do {
			let authorization = try result.get()
			guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
			      let identityToken = credential.identityToken,
			      let token = String(data: identityToken, encoding: .utf8)
			else {
				throw BrowserSyncError.missingAppleToken
			}
			let response: AuthenticationResponse = try await request(
				path: "v1/auth/apple",
				method: "POST",
				body: AuthenticationRequest(identityToken: token),
				bearer: nil
			)
			try BrowserSessionStore.save(response.token)
			sessionToken = response.token
			isSignedIn = true
			errorDescription = nil
			await syncNow()
		} catch {
			errorDescription = error.localizedDescription
		}
	}

	func signOut() {
		do {
			try BrowserSessionStore.delete()
			sessionToken = nil
			isSignedIn = false
			scheduledSync?.cancel()
			errorDescription = nil
		} catch {
			errorDescription = error.localizedDescription
		}
	}

	func syncNow() async {
		guard let browser, let sessionToken else { return }
		guard !isSyncing else {
			syncRequestedWhileBusy = true
			return
		}
		isSyncing = true
		defer {
			isSyncing = false
			if syncRequestedWhileBusy {
				syncRequestedWhileBusy = false
				scheduleSync()
			}
		}

		do {
			let snapshots: [ServerSnapshot] = try await request(
				path: "v1/sync",
				method: "GET",
				body: AuthenticationRequest?.none,
				bearer: sessionToken
			)
			let local = browser.syncDocument(settings: settingSnapshot())
			let decoder = JSONDecoder()
			let documents = try snapshots.map { try decoder.decode(BrowserSyncDocument.self, from: $0.payload) }
			guard documents.allSatisfy({ $0.version == 1 }) else {
				throw BrowserSyncError.unsupportedVersion
			}
			let merged = documents.reduce(local) { $0.merging($1) }
			if merged != local {
				browser.applySyncDocument(merged)
				try applySettings(merged.settings)
			}

			let outgoing = browser.syncDocument(settings: settingSnapshot())
			let ownDocument = try snapshots
				.first(where: { $0.deviceID == deviceID })
				.map { try decoder.decode(BrowserSyncDocument.self, from: $0.payload) }
			if ownDocument != outgoing {
				let payload = try JSONEncoder().encode(outgoing)
				let _: ServerSnapshot = try await request(
					path: "v1/sync",
					method: "PUT",
					body: SyncRequest(deviceID: deviceID, payload: payload),
					bearer: sessionToken
				)
			}
			lastSync = .now
			errorDescription = nil
		} catch {
			errorDescription = error.localizedDescription
		}
	}

	private func settingSnapshot() -> [String: SyncedSetting] {
		var settings: [String: SyncedSetting] = [:]
		for key in Defaults.Keys.syncedSettingNames where knownSettings[key] != nil || settingVersions[key] != nil {
			settings[key] = SyncedSetting(
				value: knownSettings[key],
				modifiedAt: settingVersions[key] ?? .distantPast
			)
		}
		return settings
	}

	private func applySettings(_ settings: [String: SyncedSetting]) throws {
		for key in Defaults.Keys.syncedSettingNames {
			guard let setting = settings[key],
			      setting.modifiedAt > (settingVersions[key] ?? .distantPast)
			else { continue }
			if let data = setting.value {
				let object = try PropertyListSerialization.propertyList(from: data, format: nil)
				guard let wrapped = object as? [String: Any], let value = wrapped["value"] else {
					throw BrowserSyncError.invalidSetting
				}
				UserDefaults.standard.set(value, forKey: key)
			} else {
				UserDefaults.standard.removeObject(forKey: key)
			}
			settingVersions[key] = setting.modifiedAt
		}
		knownSettings = try Self.readSettings()
		UserDefaults.standard.set(
			settingVersions.mapValues(\.timeIntervalSince1970),
			forKey: "syncSettingVersions"
		)
	}

	private static func readSettings() throws -> [String: Data] {
		var settings: [String: Data] = [:]
		for key in Defaults.Keys.syncedSettingNames {
			guard let value = UserDefaults.standard.object(forKey: key) else { continue }
			settings[key] = try PropertyListSerialization.data(
				fromPropertyList: ["value": value],
				format: .binary,
				options: 0
			)
		}
		return settings
	}

	private func request<Response: Decodable>(
		path: String,
		method: String,
		body: (some Encodable)?,
		bearer: String?
	) async throws -> Response {
		let address = Defaults[.syncServerURL].trimmingCharacters(in: .whitespacesAndNewlines)
		guard let baseURL = URL(string: address), let host = baseURL.host,
		      !host.isEmpty,
		      baseURL.scheme == "https" || Self.isAllowedLocalHTTP(baseURL)
		else {
			throw BrowserSyncError.invalidServerURL
		}
		var request = URLRequest(url: baseURL.appending(path: path))
		request.httpMethod = method
		request.timeoutInterval = 30
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		if let body {
			request.httpBody = try JSONEncoder().encode(body)
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		if let bearer {
			request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
		}
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let response = response as? HTTPURLResponse else {
			throw BrowserSyncError.invalidResponse
		}
		guard 200 ..< 300 ~= response.statusCode else {
			throw BrowserSyncError.http(response.statusCode)
		}
		return try JSONDecoder().decode(Response.self, from: data)
	}

	private static func isAllowedLocalHTTP(_ url: URL) -> Bool {
		#if DEBUG
			url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host)
		#else
			false
		#endif
	}
}

private struct AuthenticationRequest: Encodable {
	let identityToken: String
}

private struct AuthenticationResponse: Decodable {
	let token: String
}

private struct SyncRequest: Encodable {
	let deviceID: UUID
	let payload: Data
}

private struct ServerSnapshot: Decodable {
	let deviceID: UUID
	let payload: Data
}

private enum BrowserSyncError: LocalizedError {
	case http(Int)
	case invalidResponse
	case invalidServerURL
	case invalidSetting
	case missingAppleToken
	case unsupportedVersion

	var errorDescription: String? {
		switch self {
			case let .http(status):
				"Sync server returned HTTP \(status)."
			case .invalidResponse:
				"The sync server returned an invalid response."
			case .invalidServerURL:
				"Enter a valid HTTPS sync server URL."
			case .invalidSetting:
				"The sync server returned an invalid setting."
			case .missingAppleToken:
				"Apple did not return an identity token."
			case .unsupportedVersion:
				"The sync server contains data from a newer browser version."
		}
	}
}
