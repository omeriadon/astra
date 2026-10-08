import Defaults
import SwiftUI

struct BrowserAITabDivider: View {
	let browser: Browser
	let tabs: [BrowserTab]
	@Default(.aiTabGroups) private var groupingEnabled
	@Default(.aiTabTitles) private var titlesEnabled
	@Default(.aiFeaturesEnabled) private var allFeatures
	@State private var hovered = false
	@Binding var action: String?
	@Binding var error: String?
	let canUndoGrouping: Bool
	@Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 8) {
				Rectangle()
					.fill(.secondary.opacity(0.3))
					.frame(height: 1)
				if canUndoGrouping || (allFeatures && !browser.isPrivate && (hovered || voiceOver || action != nil)) {
					if canUndoGrouping {
						Button("Undo Grouping", systemImage: "arrow.uturn.backward") { action = "undo-groups" }
							.accessibilityIdentifier("ai-undo-today-tab-groups")
							.help("Undo Today tab grouping")
					} else if tabs.count > 6, groupingEnabled {
						Button("Tidy Today Tabs", systemImage: "rectangle.3.group") { action = "groups" }
							.accessibilityIdentifier("ai-tidy-today-tabs")
							.help("Group Today tabs by topic")
					}
					if allFeatures, !browser.isPrivate, !tabs.isEmpty, titlesEnabled {
						Button("Clean Tab Titles", systemImage: "text.badge.checkmark") { action = "titles" }
							.accessibilityIdentifier("ai-clean-tab-titles")
							.help("Remove clutter from Today tab titles")
					}
					if action != nil {
						ProgressView().controlSize(.mini)
					}
				}
			}
			.frame(height: 28)
			.contentShape(Rectangle())
			.onHover { hovered = $0 }
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.disabled(action != nil)
			if let error {
				Text(error)
					.font(.caption)
					.foregroundStyle(.secondary)
					.accessibilityIdentifier("ai-tab-cleanup-error")
			}
		}

		.accessibilityLabel("Today tabs actions")
		.accessibilityIdentifier("today-tabs-divider")
	}
}
