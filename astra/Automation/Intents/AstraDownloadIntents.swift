#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
	import AppIntents
	import AppKit
	import AstraAutomationCore
	import Foundation

	struct AstraDownloadEntity: AppEntity {
		static var typeDisplayRepresentation: TypeDisplayRepresentation {
			"Astra Download"
		}

		static let defaultQuery = Query()
		let id: String
		@Property(title: "Filename") var name: String
		@Property(title: "Status") var status: String

		init(id: String, name: String, status: String) {
			self.id = id
			self.name = name
			self.status = status
		}

		var displayRepresentation: DisplayRepresentation {
			DisplayRepresentation(title: "\(name)", subtitle: "\(status)")
		}

		struct Query: EntityStringQuery {
			static let persistentIdentifier = "com.omeriadon.astra.query.downloads"

			@MainActor
			private func live() -> [AstraDownloadEntity] {
				BrowserDownloadManager.shared.items.map {
					AstraDownloadEntity(id: $0.id.uuidString, name: $0.name, status: $0.status.rawValue)
				}
			}

			@MainActor
			func entities(for identifiers: [String]) async throws -> [AstraDownloadEntity] {
				let wanted = Set(identifiers)
				return live().filter { wanted.contains($0.id) }
			}

			@MainActor
			func entities(matching string: String) async throws -> [AstraDownloadEntity] {
				live().filter { $0.name.localizedCaseInsensitiveContains(string) }
			}

			@MainActor
			func suggestedEntities() async throws -> [AstraDownloadEntity] {
				Array(live().prefix(30))
			}
		}
	}

	struct AstraListDownloadsIntent: AppIntent {
		static let title: LocalizedStringResource = "List Astra Downloads"
		static var supportedModes: IntentModes {
			.foreground(.immediate)
		}

		@MainActor
		func perform() async throws -> some ReturnsValue<[AstraDownloadEntity]> {
			try await .result(value: AstraDownloadEntity.Query().suggestedEntities())
		}
	}

	struct AstraPauseDownloadIntent: AppIntent {
		static let title: LocalizedStringResource = "Pause Astra Download"
		static var supportedModes: IntentModes {
			.foreground(.immediate)
		}

		@Parameter(title: "Download") var download: AstraDownloadEntity
		@MainActor
		func perform() async throws -> some IntentResult {
			guard let id = UUID(uuidString: download.id),
			      BrowserDownloadManager.shared.items.contains(where: { $0.id == id && $0.status == .downloading })
			else {
				throw AstraSystemActions.Failure.unsupportedAction
			}
			BrowserDownloadManager.shared.pause(id)
			return .result()
		}
	}

	struct AstraResumeDownloadIntent: AppIntent {
		static let title: LocalizedStringResource = "Resume Astra Download"
		static var supportedModes: IntentModes {
			.foreground(.immediate)
		}

		@Parameter(title: "Download") var download: AstraDownloadEntity
		@MainActor
		func perform() async throws -> some IntentResult {
			guard let id = UUID(uuidString: download.id),
			      BrowserDownloadManager.shared.items.contains(where: { $0.id == id && $0.canResume })
			else {
				throw AstraSystemActions.Failure.unsupportedAction
			}
			BrowserDownloadManager.shared.resume(id)
			return .result()
		}
	}
#endif
