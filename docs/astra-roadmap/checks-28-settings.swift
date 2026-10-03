import Foundation

@main
struct SettingsSchemaChecks {
	static func main() {
		precondition(BrowserSettingsSchema.currentVersion == 1)
		precondition(BrowserSettingsSchema.schemaIsConsistent)
		precondition(BrowserSettingsSchema.portableNames.contains("browserSearchConfiguration"))
		precondition(BrowserSettingsSchema.portableNames.contains("startPagePreferences"))
		precondition(BrowserSettingsSchema.portableNames.contains("homepageURL"))
		precondition(BrowserSettingsSchema.deviceOnlyNames.contains("downloadsFolderBookmark"))
		precondition(BrowserSettingsSchema.deviceOnlyNames.contains("syncServerURL"))
		precondition(!BrowserSettingsSchema.portableNames.contains("downloadsFolderBookmark"))
		precondition(!BrowserSettingsSchema.portableNames.contains("syncServerURL"))
		print("settings schema checks passed")
	}
}
