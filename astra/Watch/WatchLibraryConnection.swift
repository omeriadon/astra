#if os(iOS) || os(watchOS)
	import Foundation
	import Observation
	import WatchConnectivity

	@MainActor
	@Observable
	final class WatchLibraryConnection: NSObject, WCSessionDelegate {
		static let shared = WatchLibraryConnection()
		private(set) var library: WatchLibrary?
		private(set) var errorDescription: String?
		@ObservationIgnored private var latestData: Data?
		@ObservationIgnored private let cacheURL = URL.documentsDirectory.appendingPathComponent("watch-library.json")

		override private init() {
			super.init()
			#if os(watchOS)
				if let data = try? Data(contentsOf: cacheURL) {
					library = try? JSONDecoder().decode(WatchLibrary.self, from: data)
				}
			#endif
			guard WCSession.isSupported() else { return }
			WCSession.default.delegate = self
			WCSession.default.activate()
		}

		#if os(iOS)
			func publish(_ library: WatchLibrary) {
				do {
					guard self.library != library else { return }
					var outgoing = library
					outgoing.updatedAt = .now
					latestData = try JSONEncoder().encode(outgoing)
					self.library = library
					sendLatest()
				} catch {
					errorDescription = error.localizedDescription
				}
			}

			private func sendLatest() {
				let session = WCSession.default
				guard session.activationState == .activated, session.isPaired,
				      session.isWatchAppInstalled, let latestData else { return }
				do {
					if latestData.count < 60000 {
						try session.updateApplicationContext(["library": latestData])
					} else {
						try session.updateApplicationContext(["libraryFile": true])
						// Application context has a 65 KB ceiling; larger libraries use file transfer.
						try latestData.write(to: cacheURL, options: .atomic)
						for transfer in session.outstandingFileTransfers {
							transfer.cancel()
						}
						session.transferFile(cacheURL, metadata: ["library": true])
					}
					errorDescription = nil
				} catch {
					errorDescription = error.localizedDescription
				}
			}

			nonisolated func session(_: WCSession, didFinish _: WCSessionFileTransfer, error: (any Error)?) {
				guard let message = error?.localizedDescription else { return }
				Task { @MainActor in self.errorDescription = message }
			}

			nonisolated func sessionDidBecomeInactive(_: WCSession) {}

			nonisolated func sessionDidDeactivate(_ session: WCSession) {
				session.activate()
			}

			nonisolated func sessionWatchStateDidChange(_: WCSession) {
				Task { @MainActor in sendLatest() }
			}

			nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
				guard message["refresh"] as? Bool == true else { return }
				Task { @MainActor in sendLatest() }
			}
		#else
			func refresh() {
				let session = WCSession.default
				guard session.activationState == .activated, session.isReachable else { return }
				session.sendMessage(["refresh": true], replyHandler: nil) { error in
					let message = error.localizedDescription
					Task { @MainActor in self.errorDescription = message }
				}
			}

			private func receive(_ data: Data) {
				do {
					let next = try JSONDecoder().decode(WatchLibrary.self, from: data)
					guard next.updatedAt >= (library?.updatedAt ?? .distantPast) else { return }
					try data.write(to: cacheURL, options: .atomic)
					library = next
					errorDescription = nil
				} catch {
					errorDescription = error.localizedDescription
				}
			}

			nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
				guard let data = applicationContext["library"] as? Data else { return }
				Task { @MainActor in receive(data) }
			}

			nonisolated func session(_: WCSession, didReceive file: WCSessionFile) {
				guard file.metadata?["library"] as? Bool == true else { return }
				do {
					let data = try Data(contentsOf: file.fileURL)
					Task { @MainActor in receive(data) }
				} catch {
					let message = error.localizedDescription
					Task { @MainActor in self.errorDescription = message }
				}
			}
		#endif

		nonisolated func session(
			_ session: WCSession,
			activationDidCompleteWith _: WCSessionActivationState,
			error: (any Error)?
		) {
			let message = error?.localizedDescription
			#if os(watchOS)
				let data = session.receivedApplicationContext["library"] as? Data
			#endif
			Task { @MainActor in
				if let message {
					errorDescription = message
					return
				}
				#if os(iOS)
					sendLatest()
				#else
					if let data {
						receive(data)
					}
					refresh()
				#endif
			}
		}
	}
#endif
