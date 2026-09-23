import Defaults

extension AddressDisplayStyle: Defaults.Serializable {}
extension TabSwitchingOrder: Defaults.Serializable {}
extension TopBarBackgroundStyle: Defaults.Serializable {}
extension PeekLevel: Defaults.Serializable {}
extension BrowserTheme: Defaults.Serializable {}

extension Defaults.Keys {
	static let syncServerURL = Key<String>(
		"syncServerURL",
		default: ""
	)

	static let syncedSettingNames: Set<String> = [
		"addressDisplayStyle",
		"tabSwitchingOrder",
		"topBarBackgroundStyle",
		"peekLevel",
		"zoomOutInPeeks",
		"renameDownloadsWithAppleIntelligence",
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

	static let addressDisplayStyle = Key<AddressDisplayStyle>(
		"addressDisplayStyle",
		default: .simple
	)
	static let tabSwitchingOrder = Key<TabSwitchingOrder>(
		"tabSwitchingOrder",
		default: .visibleTabList
	)
	static let topBarBackgroundStyle = Key<TopBarBackgroundStyle>(
		"topBarBackgroundStyle",
		default: .blur
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
