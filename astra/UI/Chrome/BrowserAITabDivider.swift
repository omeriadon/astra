import Defaults
import SwiftUI

struct BrowserAITabDivider: View {
	let browser: Browser
	let space: BrowserSpace
	let tabs: [BrowserTab]
	@Default(.aiTabGroups) private var groupingEnabled
	@Default(.aiTabTitles) private var titlesEnabled
	@State private var hovered = false
	@State private var action: String?
	@State private var error: String?
	@Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 8) {
				Rectangle()
					.fill(.secondary.opacity(0.3))
					.frame(height: 1)
				if !browser.isPrivate, hovered || voiceOver || action != nil {
					if tabs.count > 6, groupingEnabled {
						Button("Tidy Today Tabs", systemImage: "rectangle.3.group") { action = "groups" }
							.accessibilityIdentifier("ai-tidy-today-tabs")
							.help("Group Today tabs by topic")
					}
					if !tabs.isEmpty, titlesEnabled {
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
		.task(id: action) {
			guard let action else { return }
			error = nil
			defer { self.action = nil }
			do {
				let snapshot = tabs.filter { $0.internalPage == nil && $0.currentURL != nil }
				let metadata = snapshot.map { BrowserTabGroupingFeature.Tab(id: $0.id, title: $0.title, url: BrowserAddress.withoutCredentials($0.currentURL!).absoluteString) }
				if action == "groups" {
					let groups = try await BrowserAI.shared.perform(BrowserTabGroupingFeature(), input: metadata)
					try Task.checkCancellation()
					try BrowserTabGroupingFeature.validate(groups, expectedIDs: metadata.map(\.id))
					guard snapshot.enumerated().allSatisfy({ index, tab in
						tab.title == metadata[index].title && tab.currentURL.map(BrowserAddress.withoutCredentials)?.absoluteString == metadata[index].url
					}) else { throw BrowserAIError.pageUnavailable }
					browser.applyTodayTabGroups(groups, in: space.id, expectedIDs: tabs.map(\.id))
				} else {
					var titles: [(BrowserTab, String, String, URL)] = []
					for tab in snapshot {
						try Task.checkCancellation()
						let originalTitle = tab.title
						guard let url = tab.currentURL else { continue }
						var text = ""
						if let controller = tab.controller, controller.webViewIfLoaded != nil {
							if let page = try? await BrowserAIPageText.extract(from: controller).limited(to: 2000) {
								text = page.text
							}
						}
						let title = try await BrowserAI.shared.perform(
							BrowserTabTitleFeature(),
							input: BrowserAIPageText(title: originalTitle, url: url, text: text)
						)
						titles.append((tab, title, originalTitle, url))
					}
					try Task.checkCancellation()
					guard browser.workspace.spaces.contains(where: { $0.id == space.id && $0.tabIDs == space.tabIDs && $0.pinnedTabIDs == space.pinnedTabIDs }),
					      titles.allSatisfy({ $0.0.title == $0.2 && $0.0.currentURL == $0.3 }) else { throw BrowserAIError.pageUnavailable }
					for (tab, title, _, _) in titles {
						tab.rename(to: title)
					}
				}
			} catch {
				if !Task.isCancelled {
					self.error = error.localizedDescription
				}
			}
		}
		.accessibilityLabel("Today tabs actions")
		.accessibilityIdentifier("today-tabs-divider")
	}
}
