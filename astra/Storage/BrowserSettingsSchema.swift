import Defaults
import Foundation

@MainActor
enum BrowserSettingsSchema {
	static let currentVersion = 1

	/// Settings that may leave the device through Astra's timestamped sync document.
	static var portableNames: Set<String> {
		Defaults.Keys.syncedSettingNames
	}

	/// Settings that intentionally stay on this device because they describe local UI,
	/// local filesystem/capability state, an account endpoint, or developer behavior.
	static let deviceOnlyNames: Set<String> = [
		"sidebarShown",
		"syncServerURL",
		"miniAstraEnabled",
		"miniAstraWindowAnimation",
		"miniAstraShortcutEnabled",
		"webInspectorEnabled",
		"aiLinkPreviews",
		"aiTabGroups",
		"aiFind",
		"aiFindContextLimit",
		"aiSidebar",
		"aiTabTitles",
		"aiProvider",
		"aiCodexModel",
		"aiClaudeModel",
		"aiFeaturePresets",
		"downloadsFolderBookmark",
	]

	static let forbiddenPortableNames: Set<String> = [
		"syncServerURL",
		"downloadsFolderBookmark",
		"sidebarShown",
	]

	static var schemaIsConsistent: Bool {
		portableNames.isDisjoint(with: deviceOnlyNames)
			&& portableNames.isDisjoint(with: forbiddenPortableNames)
	}

	/// Restore browser preferences without clearing browsing data, bookmarks,
	/// downloads, extension packages, credentials, account identity, or cookies.
	static func resetBrowserSettings() {
		Defaults[.newTabStyle] = .page
		Defaults[.startupBehavior] = .restore
		Defaults[.homepageURL] = "https://www.google.com"
		Defaults[.tryHTTPSFirst] = true
		Defaults[.globalPrivacyControl] = true
		Defaults[.historyRetentionDays] = 0
		Defaults[.searchSuggestionsEnabled] = true
		Defaults[.browserSearchConfiguration] = BrowserSearchConfiguration.default.encoded
		Defaults[.startPagePreferences] = BrowserStartPagePreferences.default.encoded
		Defaults[.browserTheme] = BrowserTheme()
		Defaults[.renameDownloadsWithAppleIntelligence] = true
		Defaults[.aiLinkPreviews] = true
		Defaults[.aiTabGroups] = true
		Defaults[.aiFind] = true
		Defaults[.aiFindContextLimit] = true
		Defaults[.aiSidebar] = true
		Defaults[.aiTabTitles] = true
		Defaults[.aiProvider] = "presets"
		Defaults[.aiCodexModel] = ""
		Defaults[.aiClaudeModel] = ""
		Defaults[.aiFeaturePresets] = "{}"
		Defaults[.downloadsAskWhereToSave] = false
		Defaults[.copyMailtoAddresses] = true
		Defaults[.requireDoublePressToQuit] = true
		Defaults[.addressDisplayStyle] = .simple
		Defaults[.peekLevel] = .none
		Defaults[.zoomOutInPeeks] = true
		Defaults[.defaultPageZoom] = 1
		BrowserSitePreferences.shared.resetAll()

		Defaults[.sidebarShown] = true
		Defaults[.miniAstraEnabled] = true
		Defaults[.miniAstraWindowAnimation] = true
		Defaults[.miniAstraShortcutEnabled] = false
		Defaults[.webInspectorEnabled] = false
		Defaults[.downloadsFolderBookmark] = ""
	}
}
