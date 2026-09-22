import Defaults

extension AddressDisplayStyle: Defaults.Serializable {}
extension TabSwitchingOrder: Defaults.Serializable {}
extension TopBarBackgroundStyle: Defaults.Serializable {}

extension Defaults.Keys {
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
}
