import AuthenticationServices
import Defaults
import Foundation
import Network
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
	@ObservationIgnored private let networkMonitor = NWPathMonitor()
	@ObservationIgnored private var networkWasAvailable: Bool?
	@ObservationIgnored private var sessionToken: String?
	@ObservationIgnored private var tokenEndpoint: String?
	@ObservationIgnored private var scheduledSync: Task<Void, Never>?
	@ObservationIgnored private var syncRequestedWhileBusy = false
	@ObservationIgnored private var knownSettings: [String: Data]
	@ObservationIgnored private var settingVersions: [String: Date]
	@ObservationIgnored private let deviceID: UUID
	@ObservationIgnored private var settingsObserver: NSObjectProtocol?
	@ObservationIgnored private var observedSettingsRefreshTask: Task<Void, Never>?
	@ObservationIgnored private var observedServerAddress: String?
	@ObservationIgnored private var authGeneration: UInt64 = 0

	private init() {
		isSignedIn = false
		let storedVersions = UserDefaults.standard.dictionary(forKey: "syncSettingVersions") as? [String: Double] ?? [:]
		settingVersions = storedVersions.mapValues(Date.init(timeIntervalSince1970:))
		tokenEndpoint = UserDefaults.standard.string(forKey: "syncTokenEndpoint")
		knownSettings = (try? Self.readSettings()) ?? [:]
		observedServerAddress = SyncServerAddress.normalized(Defaults[.syncServerURL], allowLocalHTTP: Self.allowsLocalHTTP)?.absoluteString
		for key in knownSettings.keys where settingVersions[key] == nil {
			settingVersions[key] = .distantPast
		}
		UserDefaults.standard.set(settingVersions.mapValues(\.timeIntervalSince1970), forKey: "syncSettingVersions")
		if let storedID = UserDefaults.standard.string(forKey: "syncDeviceID"),
		   let id = UUID(uuidString: storedID)
		{
			deviceID = id
		} else {
			let id = UUID()
			UserDefaults.standard.set(id.uuidString, forKey: "syncDeviceID")
			deviceID = id
		}
		settingsObserver = NotificationCenter.default.addObserver(
			forName: UserDefaults.didChangeNotification,
			object: UserDefaults.standard,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.serverAddressDidChange()
				self?.scheduleObservedSettingsRefresh()
			}
		}
		networkMonitor.pathUpdateHandler = { path in
			let available = path.status == .satisfied
			Task { @MainActor in
				let sync = BrowserSync.shared
				if sync.networkWasAvailable == false, available {
					sync.scheduleSync()
				}
				sync.networkWasAvailable = available
			}
		}
		networkMonitor.start(queue: DispatchQueue(label: "astra.sync.network"))

		// Keychain can block on crypto/disk; never on the launch path.
		Task.detached(priority: .utility) {
			guard let token = try? BrowserSessionStore.load() else { return }
			await MainActor.run { [weak self] in
				guard let self, sessionToken == nil,
				      SyncServerAddress.isBound(tokenEndpoint, to: currentServerAddress)
				else { return }
				sessionToken = token
				isSignedIn = true
				if browser != nil {
					Task { await self.syncNow() }
				}
			}
		}
	}

	func attach(_ browser: Browser) {
		BrowserLog.info(.sync, "sync.attach", metadata: ["window": BrowserLog.id(browser.windowID), "signed_in": String(isSignedIn)])
		guard !browser.isPrivate, !browser.isMini else { return }
		guard self.browser !== browser else { return }
		let hadBrowser = self.browser != nil
		self.browser = browser
		if isSignedIn, !hadBrowser, browser.isReadyForSync {
			Task { await syncNow() }
		}
	}

	private func scheduleObservedSettingsRefresh() {
		guard observedSettingsRefreshTask == nil else { return }
		observedSettingsRefreshTask = Task { @MainActor [weak self] in
			// UserDefaults emits for unrelated keys too; coalesce notifications
			// rather than encoding the entire synced settings set for each write.
			try? await Task.sleep(for: .milliseconds(250))
			guard !Task.isCancelled, let self else { return }
			observedSettingsRefreshTask = nil
			settingsDidChange()
		}
	}

	func settingsDidChange() {
		BrowserLog.debug(.sync, "sync.settings-changed")
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

	private func serverAddressDidChange() {
		let currentAddress = currentServerAddress?.absoluteString
		guard currentAddress != observedServerAddress else { return }
		observedServerAddress = currentAddress
		authGeneration &+= 1
		guard isSignedIn else { return }
		sessionToken = nil
		isSignedIn = false
		scheduledSync?.cancel()
		errorDescription = "The sync server changed. Sign in again for this server."
	}

	func scheduleSync() {
		BrowserLog.debug(.sync, "sync.schedule", metadata: ["signed_in": String(isSignedIn), "busy": String(isSyncing)])
		guard isSignedIn, browser != nil else { return }
		guard !isSyncing else {
			syncRequestedWhileBusy = true
			return
		}
		scheduledSync?.cancel()
		scheduledSync = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(2))
			guard !Task.isCancelled else { return }
			await self?.syncNow()
		}
	}

	func signIn(result: Result<ASAuthorization, any Error>) async {
		let logStarted = BrowserLog.clock()
		BrowserLog.info(.sync, "sync.sign-in.begin", metadata: ["server": BrowserLog.url(currentServerAddress)])
		authGeneration &+= 1
		let signInGeneration = authGeneration
		do {
			guard let signInAddress = currentServerAddress else {
				throw BrowserSyncError.invalidServerURL
			}
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
			guard authGeneration == signInGeneration,
			      currentServerAddress?.absoluteString == signInAddress.absoluteString
			else {
				throw BrowserSyncError.serverChanged
			}
			try BrowserSessionStore.save(response.token)
			sessionToken = response.token
			tokenEndpoint = signInAddress.absoluteString
			UserDefaults.standard.set(tokenEndpoint, forKey: "syncTokenEndpoint")
			isSignedIn = true
			errorDescription = nil
			BrowserLog.duration(.sync, "sync.sign-in.success", since: logStarted, warnAboveMilliseconds: 1000, metadata: ["server": BrowserLog.url(currentServerAddress)])
			await syncNow()
		} catch {
			BrowserLog.error(.sync, "sync.sign-in.failed", metadata: ["error": BrowserLog.errorDescription(error), "server": BrowserLog.url(currentServerAddress)])
			errorDescription = error.localizedDescription
		}
	}

	func signOut() {
		BrowserLog.notice(.sync, "sync.sign-out")
		do {
			try BrowserSessionStore.delete()
			authGeneration &+= 1
			sessionToken = nil
			tokenEndpoint = nil
			UserDefaults.standard.removeObject(forKey: "syncTokenEndpoint")
			isSignedIn = false
			scheduledSync?.cancel()
			errorDescription = nil
		} catch {
			errorDescription = error.localizedDescription
		}
	}

	func syncNow() async {
		let logStarted = BrowserLog.clock()
		BrowserLog.info(.sync, "sync.begin", metadata: ["server": BrowserLog.url(currentServerAddress), "signed_in": String(isSignedIn)])
		guard let browser, browser.isReadyForSync,
		      let sessionToken,
		      SyncServerAddress.isBound(tokenEndpoint, to: currentServerAddress)
		else { return }
		guard !isSyncing else {
			syncRequestedWhileBusy = true
			return
		}
		let syncGeneration = authGeneration
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
			guard self.sessionToken == sessionToken,
			      authGeneration == syncGeneration,
			      SyncServerAddress.isBound(tokenEndpoint, to: currentServerAddress) else { return }
			let local = browser.syncDocument(settings: settingSnapshot())
			// Decode + merge off-main; docs are Sendable values.
			let merged = try await Task.detached(priority: .utility) {
				let decoder = JSONDecoder()
				let documents = try snapshots.map { try decoder.decode(BrowserSyncDocument.self, from: $0.payload) }
				guard documents.allSatisfy(\.hasSupportedVersion) else {
					throw BrowserSyncError.unsupportedVersion
				}
				guard documents.allSatisfy(\.hasValidStructure) else {
					throw BrowserSyncError.invalidResponse
				}
				return documents.reduce(local) { $0.merging($1) }
			}.value
			guard self.sessionToken == sessionToken,
			      authGeneration == syncGeneration,
			      SyncServerAddress.isBound(tokenEndpoint, to: currentServerAddress) else { return }
			settingsDidChange()
			let currentBrowsers = BrowserWindowRegistry.shared.openBrowsers.filter {
				!$0.isPrivate && !$0.isMini && $0.session === browser.session
					&& $0.isReadyForSync
			}
			let latest = currentBrowsers.reduce(browser.syncDocument(settings: settingSnapshot())) { partial, peer in
				partial.merging(peer.syncDocument(settings: settingSnapshot()))
			}
			let protectedMerge = merged.merging(latest)
			if protectedMerge != local {
				for target in currentBrowsers {
					target.applySyncDocument(protectedMerge)
				}
				try applySettings(protectedMerge.settings)
				for target in currentBrowsers {
					await target.flushAndWaitForPersistence()
				}
				guard self.sessionToken == sessionToken,
				      authGeneration == syncGeneration,
				      SyncServerAddress.isBound(tokenEndpoint, to: currentServerAddress) else { return }
			}

			let outgoing = currentBrowsers.reduce(browser.syncDocument(settings: settingSnapshot())) { partial, peer in
				partial.merging(peer.syncDocument(settings: settingSnapshot()))
			}
			let deviceID = deviceID
			let pushPayload: Data? = try await Task.detached(priority: .utility) {
				let decoder = JSONDecoder()
				let ownDocument = try snapshots
					.first(where: { $0.deviceID == deviceID })
					.map { try decoder.decode(BrowserSyncDocument.self, from: $0.payload) }
				guard ownDocument != outgoing else { return nil }
				let payload = try JSONEncoder().encode(outgoing)
				guard payload.count <= 16 * 1024 * 1024 else {
					throw BrowserSyncError.payloadTooLarge
				}
				return payload
			}.value
			guard self.sessionToken == sessionToken,
			      authGeneration == syncGeneration,
			      SyncServerAddress.isBound(tokenEndpoint, to: currentServerAddress) else { return }
			if let payload = pushPayload {
				guard self.sessionToken == sessionToken,
				      authGeneration == syncGeneration,
				      SyncServerAddress.isBound(tokenEndpoint, to: currentServerAddress) else { return }
				let _: ServerSnapshot = try await request(
					path: "v1/sync",
					method: "PUT",
					body: SyncRequest(deviceID: deviceID, payload: payload),
					bearer: sessionToken
				)
				guard self.sessionToken == sessionToken,
				      authGeneration == syncGeneration,
				      SyncServerAddress.isBound(tokenEndpoint, to: currentServerAddress) else { return }
			}
			lastSync = .now
			errorDescription = nil
			BrowserLog.duration(.sync, "sync.success", since: logStarted, warnAboveMilliseconds: 1500, metadata: ["server": BrowserLog.url(currentServerAddress)])
		} catch {
			guard !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled else {
				BrowserLog.debug(.sync, "sync.cancelled")
				return
			}
			BrowserLog.error(.sync, "sync.failed", metadata: ["error": BrowserLog.errorDescription(error), "server": BrowserLog.url(currentServerAddress)])
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
		var updates: [(String, Any?, Date)] = []
		for key in Defaults.Keys.syncedSettingNames {
			guard let setting = settings[key],
			      setting.shouldApply(
			      	over: knownSettings[key],
			      	newerThan: settingVersions[key] ?? .distantPast
			      )
			else { continue }
			if let data = setting.value {
				let object = try PropertyListSerialization.propertyList(from: data, format: nil)
				guard let wrapped = object as? [String: Any], let value = wrapped["value"] else {
					throw BrowserSyncError.invalidSetting
				}
				updates.append((key, value, setting.modifiedAt))
			} else {
				updates.append((key, nil, setting.modifiedAt))
			}
		}
		for (key, value, modifiedAt) in updates {
			if let value {
				UserDefaults.standard.set(value, forKey: key)
			} else {
				UserDefaults.standard.removeObject(forKey: key)
			}
			settingVersions[key] = modifiedAt
		}
		knownSettings = try Self.readSettings()
		UserDefaults.standard.set(
			settingVersions.mapValues(\.timeIntervalSince1970),
			forKey: "syncSettingVersions"
		)
	}

	private static func readSettings() throws -> [String: Data] {
		var settings: [String: Data] = [:]
		let bundleID = Bundle.main.bundleIdentifier ?? "com.omeriadon.astra"
		let storedValues = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
		for key in Defaults.Keys.syncedSettingNames {
			guard let value = storedValues[key] else { continue }
			settings[key] = try PropertyListSerialization.data(
				fromPropertyList: ["value": value],
				format: .binary,
				options: 0
			)
		}
		return settings
	}

	func requireAIAuthentication() throws -> UInt64 {
		guard isSignedIn, sessionToken != nil,
		      SyncServerAddress.isBound(tokenEndpoint, to: currentServerAddress)
		else {
			throw BrowserAIError.signInRequired
		}
		return authGeneration
	}

	func websiteMonitors() async throws -> [BrowserWebsiteMonitor] {
		let generation = try requireAIAuthentication()
		let result: [BrowserWebsiteMonitor] = try await request(path: "v1/monitors", method: "GET", body: String?.none, bearer: sessionToken)
		try validateAIAuthentication(generation)
		return result
	}

	func createWebsiteMonitor(_ input: BrowserWebsiteMonitorInput) async throws -> BrowserWebsiteMonitor {
		let generation = try requireAIAuthentication()
		let result: BrowserWebsiteMonitor = try await request(path: "v1/monitors", method: "POST", body: input, bearer: sessionToken)
		try validateAIAuthentication(generation)
		return result
	}

	func setWebsiteMonitorsEnabled(_ enabled: Bool) async throws {
		_ = try requireAIAuthentication()
		let _: BrowserMonitorState = try await request(path: "v1/monitors/enabled", method: "PUT", body: BrowserMonitorState(enabled: enabled), bearer: sessionToken)
	}

	func deleteWebsiteMonitor(_ id: UUID) async throws {
		_ = try requireAIAuthentication()
		let _: BrowserMonitorDeleted = try await request(path: "v1/monitors/\(id.uuidString)", method: "DELETE", body: String?.none, bearer: sessionToken)
	}

	func validateAIAuthentication(_ generation: UInt64) throws {
		guard try requireAIAuthentication() == generation else {
			throw BrowserAIError.signInRequired
		}
	}

	func generateAI(_ body: BrowserAICloudRequest) async throws -> BrowserAIResponse {
		let generation = try requireAIAuthentication()
		let response: BrowserAIResponse = try await request(
			path: "v1/ai/generate",
			method: "POST",
			body: body,
			bearer: sessionToken,
			timeout: 90
		)
		try validateAIAuthentication(generation)
		return response
	}

	func streamAI(
		_ body: BrowserAICloudRequest,
		onSnapshot: @MainActor (String) -> Void
	) async throws -> String {
		let generation = try requireAIAuthentication()
		guard let baseURL = currentServerAddress, let bearer = sessionToken else {
			throw BrowserAIError.signInRequired
		}
		var request = URLRequest(url: baseURL.appending(path: "v1/ai/stream"))
		request.httpMethod = "POST"
		request.httpBody = try JSONEncoder().encode(body)
		guard (request.httpBody?.count ?? 0) <= 20 * 1024 * 1024 else { throw BrowserAIError.server(413, nil) }
		request.timeoutInterval = 90
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
		request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = 90
		configuration.timeoutIntervalForResource = 90
		let session = URLSession(configuration: configuration)
		defer { session.invalidateAndCancel() }
		return try await withTaskCancellationHandler {
			try Task.checkCancellation()
			let (bytes, response) = try await session.bytes(for: request)
			try validateAIAuthentication(generation)
			guard let response = response as? HTTPURLResponse else {
				throw BrowserAIError.invalidStream
			}
			if response.statusCode == 401 {
				signOut()
				throw BrowserAIError.signInRequired
			}
			guard response.statusCode == 200 else {
				var message = ""
				for try await line in bytes.lines {
					message += String(line.prefix(16384 - min(message.utf8.count, 16384)))
					if message.utf8.count >= 16384 {
						break
					}
				}
				throw BrowserAIError.http(response.statusCode, data: Data(message.utf8))
			}
			guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else {
				throw BrowserAIError.invalidStream
			}
			var totalBytes = 0
			for try await line in bytes.lines {
				try Task.checkCancellation()
				try validateAIAuthentication(generation)
				totalBytes += line.utf8.count
				guard line.utf8.count <= 524_288, totalBytes <= 32 * 1024 * 1024 else {
					throw BrowserAIError.invalidStream
				}
				guard line.hasPrefix("data: ") else { continue }
				let event = try JSONDecoder().decode(BrowserAIStreamEvent.self, from: Data(line.dropFirst(6).utf8))
				if let error = event.error {
					throw BrowserAIError.server(502, String(error.prefix(300)))
				}
				guard let text = event.text, let isFinal = event.isFinal else {
					throw BrowserAIError.invalidStream
				}
				onSnapshot(text)
				if isFinal {
					guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
						throw BrowserAIError.emptyResponse
					}
					return text
				}
			}
			throw BrowserAIError.invalidStream
		} onCancel: {
			session.invalidateAndCancel()
		}
	}

	private func request<Response: Decodable>(
		path: String,
		method: String,
		body: (some Encodable)?,
		bearer: String?,
		timeout: TimeInterval = 30
	) async throws -> Response {
		BrowserLog.debug(.sync, "sync.http-request", metadata: ["method": method, "path": path, "server": BrowserLog.url(currentServerAddress)])
		guard let baseURL = SyncServerAddress.normalized(Defaults[.syncServerURL], allowLocalHTTP: Self.allowsLocalHTTP)
		else {
			throw BrowserSyncError.invalidServerURL
		}
		var request = URLRequest(url: baseURL.appending(path: path))
		request.httpMethod = method
		request.timeoutInterval = timeout
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		if let body {
			request.httpBody = try JSONEncoder().encode(body)
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		if let bearer {
			guard bearer == sessionToken, SyncServerAddress.isBound(tokenEndpoint, to: baseURL) else {
				throw BrowserSyncError.serverChanged
			}
			request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
		}
		for attempt in 0 ..< 3 {
			do {
				try Task.checkCancellation()
				let (data, response) = try await URLSession.shared.data(for: request)
				guard let response = response as? HTTPURLResponse, data.count <= 16 * 1024 * 1024 else {
					throw BrowserSyncError.invalidResponse
				}
				if response.statusCode == 401, bearer != nil, sessionToken == bearer {
					signOut()
				}
				guard 200 ..< 300 ~= response.statusCode else {
					if path.hasPrefix("v1/ai/") {
						throw BrowserAIError.http(response.statusCode, data: data)
					}
					throw BrowserSyncError.http(response.statusCode)
				}
				return try JSONDecoder().decode(Response.self, from: data)
			} catch {
				let transient: Bool = if case let BrowserSyncError.http(status) = error {
					[429, 500, 502, 503, 504].contains(status)
				} else if let networkError = error as? URLError {
					[.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(networkError.code)
				} else {
					false
				}
				guard attempt < 2, transient, ["GET", "PUT"].contains(method) else { throw error }
				try await Task.sleep(for: .seconds(attempt == 0 ? 1 : 3))
			}
		}
		throw BrowserSyncError.invalidResponse
	}

	private var currentServerAddress: URL? {
		SyncServerAddress.normalized(Defaults[.syncServerURL], allowLocalHTTP: Self.allowsLocalHTTP)
	}

	private static var allowsLocalHTTP: Bool {
		#if DEBUG
			true
		#else
			false
		#endif
	}

	func hydrationDidFinish(_ browser: Browser) {
		guard self.browser === browser, isSignedIn else { return }
		Task { await syncNow() }
	}
}

private nonisolated struct BrowserAIStreamEvent: Decodable {
	let text: String?
	let isFinal: Bool?
	let error: String?
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

private struct ServerSnapshot: Decodable, Sendable {
	let deviceID: UUID
	let payload: Data
}

private enum BrowserSyncError: LocalizedError, Sendable {
	case http(Int)
	case invalidResponse
	case invalidServerURL
	case invalidSetting
	case missingAppleToken
	case unsupportedVersion
	case serverChanged
	case payloadTooLarge

	var errorDescription: String? {
		switch self {
			case let .http(status):
				"Sync server returned HTTP \(status)."
			case .invalidResponse:
				"The sync server returned an invalid response."
			case .invalidServerURL:
				"Enter a valid sync server URL using HTTPS. The scheme may be omitted."
			case .invalidSetting:
				"The sync server returned an invalid setting."
			case .missingAppleToken:
				"Apple did not return an identity token."
			case .unsupportedVersion:
				"The sync server contains data from a newer browser version."
			case .serverChanged:
				"The sync server changed during sign-in. Sign in again."
			case .payloadTooLarge:
				"Local sync data exceeds the server's 16 MB request limit. The local copy is safe."
		}
	}
}
