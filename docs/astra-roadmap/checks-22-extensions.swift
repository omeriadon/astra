import Foundation

@main
struct BrowserExtensionChecks {
	static func main() throws {
		let validID = "eimadpbcbfnmbkopoojfekhnkhdbieeh"
		precondition(ChromeExtensionPackage.extensionID(from: URL(string: "https://chromewebstore.google.com/detail/dark-reader/\(validID)")) == validID)
		precondition(ChromeExtensionPackage.extensionID(from: URL(string: "http://chromewebstore.google.com/detail/dark-reader/\(validID)")) == nil)
		precondition(ChromeExtensionPackage.extensionID(from: URL(string: "https://example.com/detail/dark-reader/\(validID)")) == nil)
		precondition(ChromeExtensionPackage.extensionID(from: URL(string: "https://chromewebstore.google.com/detail/dark-reader/not-an-extension-id")) == nil)

		let payload = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])
		let package = Data("Cr24".utf8) + Data([3, 0, 0, 0, 0, 0, 0, 0]) + payload
		let archive = try ChromeExtensionPackage.archive(from: package)
		precondition(archive == payload)

		var wrongVersion = package
		wrongVersion[4] = 2
		precondition(throwsPackageError(wrongVersion))

		var oversizedHeader = package
		oversizedHeader[8] = 0xFF
		oversizedHeader[9] = 0xFF
		oversizedHeader[10] = 0x0F
		precondition(throwsPackageError(oversizedHeader))

		precondition(throwsPackageError(Data("not a crx".utf8)))
		precondition(throwsPackageError(Data(repeating: 0, count: 50_000_001)))
	}

	private static func throwsPackageError(_ data: Data) -> Bool {
		do {
			_ = try ChromeExtensionPackage.archive(from: data)
			return false
		} catch {
			return true
		}
	}
}
