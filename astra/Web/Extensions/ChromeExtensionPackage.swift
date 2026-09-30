import Foundation

enum ChromeExtensionPackage {
	nonisolated static func extensionID(from url: URL?) -> String? {
		guard let url, url.scheme == "https", url.host == "chromewebstore.google.com",
		      url.pathComponents.dropFirst().first == "detail",
		      let id = url.pathComponents.last,
		      id.count == 32,
		      id.utf8.allSatisfy({ (97 ... 112).contains($0) }) else { return nil }
		return id
	}

	nonisolated static func archive(from package: Data) throws -> Data {
		guard package.count >= 16, package.count <= 50_000_000,
		      package.prefix(4) == Data("Cr24".utf8) else { throw PackageError.invalid }
		func integer(at offset: Int) -> UInt32 {
			(0 ..< 4).reduce(0) { $0 | (UInt32(package[offset + $1]) << ($1 * 8)) }
		}
		let version = integer(at: 4)
		let headerSize = Int(integer(at: 8))
		guard version == 3, headerSize <= 1_000_000, headerSize <= package.count - 16 else {
			throw PackageError.invalid
		}
		let archive = package.subdata(in: (12 + headerSize) ..< package.count)
		guard archive.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]) else { throw PackageError.invalid }
		return archive
	}

	#if DEBUG
		nonisolated static func checkParsing() {
			let payload = Data([0x50, 0x4B, 0x03, 0x04])
			let package = Data("Cr24".utf8) + Data([3, 0, 0, 0, 0, 0, 0, 0]) + payload
			assert((try? archive(from: package)) == payload)
			assert((try? archive(from: package.prefix(11))) == nil)
			var invalidHeader = package
			invalidHeader[8] = 255
			assert((try? archive(from: invalidHeader)) == nil)
			assert(extensionID(from: URL(string: "https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh")) == "eimadpbcbfnmbkopoojfekhnkhdbieeh")
			assert(extensionID(from: URL(string: "https://example.com/detail/eimadpbcbfnmbkopoojfekhnkhdbieeh")) == nil)
		}
	#endif

	enum PackageError: LocalizedError {
		case invalid

		var errorDescription: String? {
			"The Chrome Web Store returned an invalid extension package."
		}
	}
}
