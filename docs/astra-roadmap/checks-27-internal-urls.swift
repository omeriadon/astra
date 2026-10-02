import Foundation

@main
struct InternalURLChecks {
	static func main() {
		func route(_ value: String, source: BrowserInternalURL.Source = .userInterface) -> BrowserInternalURL.Destination? {
			URL(string: value).flatMap { BrowserInternalURL.destination(for: $0, source: source) }
		}

		precondition(route("astra://new-tab") == .newTab)
		precondition(route("astra://history") == .history)
		precondition(route("astra://bookmarks") == .bookmarks)
		precondition(route("astra://theme") == .themeEditor)
		precondition(route("astra://extensions") == .settings(.extensions))
		precondition(route("astra://version") == .settings(.about))
		precondition(route("astra://settings") == .settings(nil))
		precondition(route("astra://settings?page=privacy") == .settings(.privacyAndSecurity))
		precondition(route("astra://settings?page=extensions") == .settings(.extensions))

		precondition(route("astra://unknown") == nil)
		precondition(route("astra://settings/extra") == nil)
		precondition(route("astra://settings?page=about&page=privacy") == nil)
		precondition(route("astra://history?clear=true") == nil)
		precondition(route("astra://user@history") == nil)
		precondition(route("astra://history#fragment") == nil)
		precondition(route("astra://history:8080") == nil)
		precondition(route("https://history") == nil)

		for source in [BrowserInternalURL.Source.webContent, .extensionContent, .importedData] {
			precondition(route("astra://settings?page=privacy", source: source) == nil)
		}
		precondition(route("astra://settings?page=privacy", source: .operatingSystem) == .settings(.privacyAndSecurity))
		print("internal URL checks passed")
	}
}
