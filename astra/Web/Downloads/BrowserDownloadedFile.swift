#if os(macOS)
	import CoreServices
	import Foundation

	enum BrowserDownloadedFile {
		static func quarantine(_ url: URL, downloadURL: URL?, sourceURL: URL?) throws {
			var properties: [String: Any] = [
				kLSQuarantineAgentNameKey as String: "Astra",
				kLSQuarantineAgentBundleIdentifierKey as String: Bundle.main.bundleIdentifier ?? "browser",
				kLSQuarantineTimeStampKey as String: Date(),
				kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
			]
			if let downloadURL, ["http", "https"].contains(downloadURL.scheme?.lowercased() ?? "") {
				properties[kLSQuarantineDataURLKey as String] = downloadURL
			}
			if let sourceURL, ["http", "https"].contains(sourceURL.scheme?.lowercased() ?? "") {
				properties[kLSQuarantineOriginURLKey as String] = sourceURL
			}
			try (url as NSURL).setResourceValue(properties, forKey: .quarantinePropertiesKey)
		}
	}
#endif
