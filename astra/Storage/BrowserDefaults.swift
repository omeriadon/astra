import Defaults

extension AddressDisplayStyle: Defaults.Serializable {}
extension PeekLevel: Defaults.Serializable {}
extension BrowserTheme: Defaults.Serializable {}

extension Defaults.Keys {
	static let miniAstraEnabled = Key<Bool>("miniAstraEnabled", default: true)
	static let miniAstraWindowAnimation = Key<Bool>("miniAstraWindowAnimation", default: true)
	static let miniAstraShortcutEnabled = Key<Bool>("miniAstraShortcutEnabled", default: false)

	static let sidebarShown = Key<Bool>(
		"sidebarShown",
		default: true
	)

	static let syncServerURL = Key<String>(
		"syncServerURL",
		default: "https://203.17.177.58:9644"
	)

	static let syncedSettingNames: Set<String> = [
		"addressDisplayStyle",
		"peekLevel",
		"zoomOutInPeeks",
		"renameDownloadsWithAppleIntelligence",
		"copyMailtoAddresses",
		"requireDoublePressToQuit",
		"browserTheme",
	]

	static let browserTheme = Key<BrowserTheme>(
		"browserTheme",
		default: BrowserTheme()
	)

	static let renameDownloadsWithAppleIntelligence = Key<Bool>(
		"renameDownloadsWithAppleIntelligence",
		default: true
	)

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
}
