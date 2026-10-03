import Defaults
import Foundation

extension AddressDisplayStyle: Defaults.Serializable {}
extension PeekLevel: Defaults.Serializable {}
extension BrowserTheme: Defaults.Serializable {}

enum BrowserStartupBehavior: String, CaseIterable {
	case restore
	case blank
	case homepage
}

extension BrowserStartupBehavior: Defaults.Serializable {}

extension Defaults.Keys {
	static let startupBehavior = Key<BrowserStartupBehavior>("startupBehavior", default: .restore)
	static let homepageURL = Key<String>("homepageURL", default: "https://www.google.com")
	static let tryHTTPSFirst = Key<Bool>("tryHTTPSFirst", default: true)
	static let globalPrivacyControl = Key<Bool>("globalPrivacyControl", default: true)
	static let historyRetentionDays = Key<Int>("historyRetentionDays", default: 0)
	static let searchSuggestionsEnabled = Key<Bool>("searchSuggestionsEnabled", default: true)
	static let browserSearchConfiguration = Key<String>("browserSearchConfiguration", default: BrowserSearchConfiguration.default.encoded)
	static let startPagePreferences = Key<String>("startPagePreferences", default: BrowserStartPagePreferences.default.encoded)
	static let siteZoomPreferences = Key<Data>(BrowserSiteZoomDocument.defaultsKey, default: Data())
	static let miniAstraEnabled = Key<Bool>("miniAstraEnabled", default: true)
	static let miniAstraWindowAnimation = Key<Bool>("miniAstraWindowAnimation", default: true)
	static let miniAstraShortcutEnabled = Key<Bool>("miniAstraShortcutEnabled", default: false)
	static let webInspectorEnabled = Key<Bool>("webInspectorEnabled", default: false)

	static let sidebarShown = Key<Bool>(
		"sidebarShown",
		default: true
	)

	static let syncServerURL = Key<String>(
		"syncServerURL",
		default: "https://203.17.177.58:9644"
	)

	// Opt in portable browser preferences only; session, endpoint, credential, and device UI keys stay local.
	static let syncedSettingNames: Set<String> = [
		"addressDisplayStyle",
		"defaultPageZoom",
		"peekLevel",
		"zoomOutInPeeks",
		"renameDownloadsWithAppleIntelligence",
		"copyMailtoAddresses",
		"requireDoublePressToQuit",
		"browserTheme",
		"tryHTTPSFirst",
		"globalPrivacyControl",
		"historyRetentionDays",
		"searchSuggestionsEnabled",
		"browserSearchConfiguration",
		"startPagePreferences",
		"downloadsAskWhereToSave",
		"startupBehavior",
		"homepageURL",
		BrowserSiteZoomDocument.defaultsKey,
	]

	static let browserTheme = Key<BrowserTheme>(
		"browserTheme",
		default: BrowserTheme()
	)

	static let renameDownloadsWithAppleIntelligence = Key<Bool>(
		"renameDownloadsWithAppleIntelligence",
		default: true
	)

	static let downloadsAskWhereToSave = Key<Bool>("downloadsAskWhereToSave", default: false)
	static let downloadsFolderBookmark = Key<String>("downloadsFolderBookmark", default: "")

	static let copyMailtoAddresses = Key<Bool>(
		"copyMailtoAddresses",
		default: true
	)

	static let requireDoublePressToQuit = Key<Bool>(
		"requireDoublePressToQuit",
		default: true
	)

	static let addressDisplayStyle = Key<AddressDisplayStyle>(
		"addressDisplayStyle",
		default: .simple
	)
	static let peekLevel = Key<PeekLevel>(
		"peekLevel",
		default: .none
	)
	static let zoomOutInPeeks = Key<Bool>(
		"zoomOutInPeeks",
		default: true
	)
	static let defaultPageZoom = Key<Double>(
		"defaultPageZoom",
		default: 1
	)
}
