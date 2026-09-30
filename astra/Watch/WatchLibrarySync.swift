#if os(watchOS)
	import AuthenticationServices
	import Foundation
	import Observation

	@MainActor
	@Observable
	final class WatchLibrarySync {
		private(set) var isSignedIn = false
		private(set) var isLoading = false
		private(set) var library: WatchLibrary?
		private(set) var errorDescription: String?

		@ObservationIgnored private var sessionToken: String?
		@ObservationIgnored private var sessionGeneration = UUID()

		func restoreSession() async {
			guard !isLoading, sessionToken == nil else { return }
			isLoading = true
			do {
				sessionToken = try await Task.detached(priority: .utility) {
					try BrowserSessionStore.load()
				}.value
				isSignedIn = sessionToken != nil
			} catch {
				errorDescription = error.localizedDescription
			}
			isLoading = false
			await refresh()
		}

		func signIn(result: Result<ASAuthorization, any Error>) async {
			guard !isLoading else { return }
			isLoading = true
			do {
				let authorization = try result.get()
				guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
				      let data = credential.identityToken,
				      let identityToken = String(data: data, encoding: .utf8)
				else {
					throw WatchSyncError.missingAppleToken
				}
				let response: WatchAuthenticationResponse = try await request(
					path: "v1/auth/apple",
					body: JSONEncoder().encode(["identityToken": identityToken])
				)
				guard !response.token.isEmpty else { throw BrowserSessionStoreError.invalidToken }
				try BrowserSessionStore.save(response.token)
				sessionGeneration = UUID()
				sessionToken = response.token
				isSignedIn = true
				library = nil
				errorDescription = nil
			} catch {
				if (error as? ASAuthorizationError)?.code != .canceled {
					errorDescription = error.localizedDescription
				}
			}
			isLoading = false
			await refresh()
		}

		func signOut() {
			sessionGeneration = UUID()
			sessionToken = nil
			isSignedIn = false
			library = nil
			errorDescription = nil
			do {
				try BrowserSessionStore.delete()
			} catch {
				errorDescription = error.localizedDescription
			}
		}

		func refresh() async {
			guard let sessionToken, !isLoading else { return }
			let generation = sessionGeneration
			isLoading = true
			defer { isLoading = false }
			do {
				let snapshots: [WatchServerSnapshot] = try await request(path: "v1/sync", bearer: sessionToken)
				let merged = try await Task.detached(priority: .utility) {
					let documents = try snapshots.map { try JSONDecoder().decode(BrowserSyncDocument.self, from: $0.payload) }
					guard documents.allSatisfy({ $0.version == 1 || $0.version == 2 }) else {
						throw WatchSyncError.unsupportedVersion
					}
					return documents.dropFirst().reduce(documents.first) { $0?.merging($1) }
				}.value
				try Task.checkCancellation()
				guard generation == sessionGeneration else { return }
				library = WatchLibrary(document: merged)
				errorDescription = nil
			} catch {
				guard generation == sessionGeneration else { return }
				if case WatchSyncError.http(401) = error {
					signOut()
				}
				errorDescription = error.localizedDescription
			}
		}

		private func request<Response: Decodable>(
			path: String,
			body: Data? = nil,
			bearer: String? = nil
		) async throws -> Response {
			let baseURL = URL(string: "https://203.17.177.58:9644")!
			var request = URLRequest(url: baseURL.appending(path: path))
			request.httpMethod = body == nil ? "GET" : "POST"
			request.httpBody = body
			request.timeoutInterval = 30
			request.cachePolicy = .reloadIgnoringLocalCacheData
			request.setValue("application/json", forHTTPHeaderField: "Accept")
			if body != nil {
				request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			}
			if let bearer {
				request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
			}
			let (data, response) = try await URLSession.shared.data(for: request)
			guard let response = response as? HTTPURLResponse else { throw WatchSyncError.invalidResponse }
			guard 200 ..< 300 ~= response.statusCode else { throw WatchSyncError.http(response.statusCode) }
			return try JSONDecoder().decode(Response.self, from: data)
		}
	}

	private struct WatchAuthenticationResponse: Decodable {
		let token: String
	}

	private struct WatchServerSnapshot: Decodable, Sendable {
		let payload: Data
	}

	private enum WatchSyncError: LocalizedError, Sendable {
		case missingAppleToken
		case invalidResponse
		case http(Int)
		case unsupportedVersion

		var errorDescription: String? {
			switch self {
				case .missingAppleToken:
					"Apple did not return an identity token."
				case .invalidResponse:
					"The sync server returned an invalid response."
				case .http(401):
					"Your session expired. Sign in with Apple again."
				case let .http(status):
					"Sync server returned HTTP \(status)."
				case .unsupportedVersion:
					"The server contains data from a newer browser version."
			}
		}
	}
#endif
