@testable import AstraAutomationCore
import Foundation
import XCTest

final class AstraAutomationCoreTests: XCTestCase {
	func testTabReferencesAreLosslessAndWindowScoped() {
		let first = AstraTabReference(windowID: UUID(), tabID: UUID())
		XCTAssertEqual(AstraTabReference(rawValue: first.rawValue), first)
		XCTAssertNil(AstraTabReference(rawValue: "invalid"))
		XCTAssertNil(AstraTabReference(rawValue: UUID().uuidString))
		XCTAssertNil(AstraTabReference(rawValue: first.rawValue + ":extra"))
	}

	func testLibraryDeepLinksAreConstrainedToKnownKindsAndUUIDs() throws {
		let items: [AstraLibraryItem] = [
			.bookmark(UUID()), .readingList(UUID()), .space(UUID()),
		]
		for item in items {
			XCTAssertEqual(AstraLibraryItem(url: item.url), item)
			XCTAssertEqual(AstraLibraryItem(spotlightIdentifier: item.spotlightIdentifier), item)
		}
		XCTAssertNil(try AstraLibraryItem(url: XCTUnwrap(URL(string: "astra://bookmark/not-a-uuid"))))
		XCTAssertNil(try AstraLibraryItem(url: XCTUnwrap(URL(string: "astra://bookmark/\(UUID())/extra"))))
		XCTAssertNil(try AstraLibraryItem(url: XCTUnwrap(URL(string: "astra://bookmark/\(UUID())?foo=bar"))))
		XCTAssertNil(try AstraLibraryItem(url: XCTUnwrap(URL(string: "astra://other/\(UUID())"))))
	}

	func testOnlyCredentialFreeWebURLs() throws {
		XCTAssertEqual(try AstraWebAddress(XCTUnwrap(URL(string: "https://example.com/path?q=a"))).url.host, "example.com")
		for candidate in ["javascript:alert(1)", "file:///tmp/file", "https://user:secret@example.com", "ftp://example.com"] {
			XCTAssertThrowsError(try AstraWebAddress(XCTUnwrap(URL(string: candidate))))
		}
		XCTAssertThrowsError(try AstraWebAddress(URL(string: "https://example.com/" + String(repeating: "x", count: 17000))!))
	}
}
