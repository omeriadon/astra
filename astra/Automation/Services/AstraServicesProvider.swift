#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
	import AppKit
	import Foundation

	@MainActor
	final class AstraServicesProvider: NSObject {
		static let shared = AstraServicesProvider()

		private func value(_ pasteboard: NSPasteboard) -> String? {
			let string = pasteboard.string(forType: .string)?
				.trimmingCharacters(in: .whitespacesAndNewlines)
			guard let string, !string.isEmpty, string.utf8.count <= 16384 else { return nil }
			return string
		}

		private func url(_ pasteboard: NSPasteboard) -> URL? {
			if let raw = pasteboard.string(forType: .URL), let candidate = URL(string: raw) {
				return try? AstraSystemActions.validated(candidate)
			}
			guard let string = value(pasteboard), let candidate = URL(string: string) else { return nil }
			return try? AstraSystemActions.validated(candidate)
		}

		@objc(searchInAstra:userData:error:)
		func searchInAstra(_ pasteboard: NSPasteboard, userData _: String?,
		                   error: AutoreleasingUnsafeMutablePointer<NSString?>?)
		{
			guard let text = value(pasteboard) else {
				unsafe error?.pointee = "Select some text to search." as NSString
				return
			}
			Task { @MainActor in
				do { try await AstraSystemActions.search(text) }
				catch { BrowserLog.error(.navigation, "service.search-failed", metadata: ["error": BrowserLog.errorDescription(error)]) }
			}
		}

		@objc(openInAstra:userData:error:)
		func openInAstra(_ pasteboard: NSPasteboard, userData _: String?,
		                 error: AutoreleasingUnsafeMutablePointer<NSString?>?)
		{
			guard let link = url(pasteboard) else {
				unsafe error?.pointee = "Select a valid HTTP or HTTPS URL." as NSString
				return
			}
			Task { @MainActor in
				do { try await AstraSystemActions.open(link) }
				catch { BrowserLog.error(.navigation, "service.open-failed", metadata: ["error": BrowserLog.errorDescription(error)]) }
			}
		}

		@objc(openInMiniAstra:userData:error:)
		func openInMiniAstra(_ pasteboard: NSPasteboard, userData _: String?,
		                     error: AutoreleasingUnsafeMutablePointer<NSString?>?)
		{
			guard let link = url(pasteboard) else {
				unsafe error?.pointee = "Select a valid HTTP or HTTPS URL." as NSString
				return
			}
			Task { @MainActor in
				do { try await AstraSystemActions.mini(link) }
				catch { BrowserLog.error(.navigation, "service.mini-failed", metadata: ["error": BrowserLog.errorDescription(error)]) }
			}
		}

		@objc(saveToAstraReadingList:userData:error:)
		func saveToAstraReadingList(_ pasteboard: NSPasteboard, userData _: String?,
		                            error: AutoreleasingUnsafeMutablePointer<NSString?>?)
		{
			guard let link = url(pasteboard) else {
				unsafe error?.pointee = "Select a valid HTTP or HTTPS URL." as NSString
				return
			}
			Task { @MainActor in
				do { try await AstraSystemActions.readLater(link) }
				catch { BrowserLog.error(.navigation, "service.reading-failed", metadata: ["error": BrowserLog.errorDescription(error)]) }
			}
		}

		@objc(createAstraEasel:userData:error:)
		func createAstraEasel(_ pasteboard: NSPasteboard, userData _: String?,
		                      error: AutoreleasingUnsafeMutablePointer<NSString?>?)
		{
			guard let text = value(pasteboard) else {
				unsafe error?.pointee = "Select text or a URL to add to an easel." as NSString
				return
			}
			let link = url(pasteboard)
			Task { @MainActor in
				do {
					if let link {
						try await AstraSystemActions.createEasel(link: link)
					} else {
						try await AstraSystemActions.createEasel(with: text)
					}
				} catch {
					BrowserLog.error(.navigation, "service.easel-failed", metadata: ["error": BrowserLog.errorDescription(error)])
				}
			}
		}
	}
#endif
