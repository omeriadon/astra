import Foundation

struct BrowserDiagnosticReport: Codable, Equatable {
	static let schemaVersion = 2
	static let maximumEncodedBytes = 32768
	static let maximumEvents = 64

	struct Event: Codable, Equatable {
		enum Category: String, Codable, CaseIterable {
			case applicationCrash
			case webContentTermination
			case navigationFailure
			case downloadFailure
			case extensionFailure
		}

		let category: Category
		let code: String
		let ageSeconds: Int
	}

	struct Memory: Codable, Equatable {
		let measuredControllers: Int
		let controllerCount: Int
		let uniqueProcessCount: Int
		let uniqueProcessBytes: UInt64?
		let webContentBytes: UInt64?
		let graphicsBytes: UInt64?
		let networkBytes: UInt64?
		let modelBytes: UInt64?
		let webContentMappingCount: Int
		let webContentUnavailableCount: Int
		let sharedWebContentProcessCount: Int
		let webContentAttribution: String
		let unavailableControllerCount: Int
	}

	let schema: Int
	let applicationVersion: String
	let applicationBuild: String
	let operatingSystem: String
	let engine: String
	let webKitVersion: String
	let scope: String
	let tabCount: Int?
	let hibernatedTabCount: Int?
	let loadingTabCount: Int?
	let navigationFailures: [String: Int]?
	var memory: Memory? = nil
	let events: [Event]

	func encoded() -> Data? {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		guard let data = try? encoder.encode(self), data.count <= Self.maximumEncodedBytes else { return nil }
		return data
	}

	static func sanitizedCode(_ raw: String) -> String? {
		guard !raw.isEmpty, raw.utf8.count <= 64,
		      raw.unicodeScalars.allSatisfy({ scalar in
		      	CharacterSet.alphanumerics.contains(scalar) || ".-_".unicodeScalars.contains(scalar)
		      })
		else { return nil }
		return raw
	}
}

@MainActor
final class BrowserDiagnosticEventStore {
	static let shared = BrowserDiagnosticEventStore()

	private struct StoredEvent {
		let category: BrowserDiagnosticReport.Event.Category
		let code: String
		let date: Date
	}

	private var events: [StoredEvent] = []

	func record(_ category: BrowserDiagnosticReport.Event.Category, code rawCode: String, isPrivate: Bool) {
		BrowserLog.debug(.diagnostics, "diagnostic-event.record", metadata: ["category": category.rawValue, "code": rawCode, "private": String(isPrivate)])
		guard !isPrivate, let code = BrowserDiagnosticReport.sanitizedCode(rawCode) else { return }
		events.append(StoredEvent(category: category, code: code, date: .now))
		if events.count > BrowserDiagnosticReport.maximumEvents {
			events.removeFirst(events.count - BrowserDiagnosticReport.maximumEvents)
		}
	}

	func snapshot(now: Date = .now) -> [BrowserDiagnosticReport.Event] {
		events.suffix(BrowserDiagnosticReport.maximumEvents).map { event in
			BrowserDiagnosticReport.Event(
				category: event.category,
				code: event.code,
				ageSeconds: max(0, min(Int(now.timeIntervalSince(event.date)), 7 * 24 * 60 * 60))
			)
		}
	}
}
