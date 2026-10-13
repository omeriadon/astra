import Foundation
import XCTest
@testable import AstraSystemKit

final class AstraSystemContractsTests: XCTestCase {
    func testSpotlightLinksRejectUntrustedPayloads() throws {
        let id = UUID()
        let link = AstraSystemLink(resource: .bookmark, id: id)
        XCTAssertEqual(AstraSystemLink(url: link.url), link)
        XCTAssertEqual(AstraSystemLink(spotlightIdentifier: link.spotlightIdentifier), link)
        XCTAssertNil(AstraSystemLink(url: URL(string: "astra://bookmark/\(id.uuidString)/another")!))
        XCTAssertNil(AstraSystemLink(url: URL(string: "astra://bookmark/\(id.uuidString)?x=1")!))
        XCTAssertNil(AstraSystemLink(url: URL(string: "astra://unknown/\(id.uuidString)")!))
        XCTAssertNil(AstraSystemLink(spotlightIdentifier: "tab:\(id.uuidString)"))
    }

    func testTabIDsRequireWindowIdentity() throws {
        let item = AstraSystemTabID(windowID: UUID(), tabID: UUID())
        XCTAssertEqual(AstraSystemTabID(rawValue: item.rawValue), item)
        XCTAssertNil(AstraSystemTabID(rawValue: item.tabID.uuidString))
        XCTAssertNil(AstraSystemTabID(rawValue: item.rawValue + ":extra"))
    }

    func testHTTPURLPolicyBlocksCredentialsAndOtherSchemes() throws {
        XCTAssertNotNil(AstraSystemURLPolicy.validate(URL(string: "https://example.org/page")!))
        XCTAssertNotNil(AstraSystemURLPolicy.validate(URL(string: "http://example.org/")!))
        XCTAssertNil(AstraSystemURLPolicy.validate(URL(string: "file:///etc/passwd")!))
        XCTAssertNil(AstraSystemURLPolicy.validate(URL(string: "javascript:alert(1)")!))
        XCTAssertNil(AstraSystemURLPolicy.validate(URL(string: "https://user:secret@example.org")!))
    }
}
