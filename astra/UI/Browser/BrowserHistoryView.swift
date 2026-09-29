import SwiftUI

struct BrowserHistoryView: View {
	let browser: Browser

	private var historyTabs: [OpenTab] {
		// Filter live tabs by currentURL before copying full histories via openTab.
		let live = browser.tabs.filter { $0.internalPage == nil && $0.currentURL != nil }
			.map(\.openTab)
			.filter { $0.url != nil }
		return (live + browser.closedHistoryTabs.filter { $0.url != nil })
			.sorted { $0.modifiedAt > $1.modifiedAt }
	}

	var body: some View {
		HistoryListView(browser: browser, historyTabs: historyTabs)
	}
}

private struct HistoryListView: View {
	let browser: Browser
	let historyTabs: [OpenTab]

	var body: some View {
		List {
			Section("Tabs") {
				ForEach(historyTabs) { tab in
					HistoryTabGroup(browser: browser, tab: tab)
				}
			}
		}
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
		.safeAreaBar(edge: .top) {
			Label("History", systemImage: "clock.arrow.circlepath")
				.font(.title2.bold())
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 24)
				.padding(.vertical, 14)
		}
		.overlay {
			if historyTabs.isEmpty {
				ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath")
			}
		}
	}
}

private struct HistoryTabGroup: View {
	let browser: Browser
	let tab: OpenTab
	@State private var isExpanded = false

	var body: some View {
		DisclosureGroup(isExpanded: $isExpanded) {
			ForEach(Array(tab.history.enumerated().reversed()), id: \.offset) { index, url in
				HistoryRow(
					title: url.host ?? url.absoluteString,
					detail: url.absoluteString,
					url: url,
					symbol: index == tab.historyIndex ? "circle.fill" : "clock",
					identifier: "history-visit-\(tab.id.uuidString)-\(index)",
					open: { browser.openHistoryURL(url, inBackground: false) },
					openInBackground: { browser.openHistoryURL(url, inBackground: true) }
				)
			}
		} label: {
			HistoryRow(
				title: tab.customTitle ?? tab.pageTitle,
				detail: tab.url?.absoluteString ?? "",
				url: tab.url,
				symbol: "rectangle.on.rectangle",
				identifier: "history-tab-\(tab.id.uuidString)",
				open: { browser.openHistoryTab(tab, inBackground: false) },
				openInBackground: { browser.openHistoryTab(tab, inBackground: true) }
			)
		}
	}
}

private struct HistoryFaviconIcon: View {
	let url: URL?
	let symbol: String

	var body: some View {
		Group {
			if let favicon = FaviconStore.shared.image(for: url) {
				favicon.resizable().scaledToFit()
			} else {
				Image(systemName: symbol)
			}
		}
		.frame(width: 16, height: 16)
	}
}

private struct HistoryRow: View {
	let title: String
	let detail: String
	let url: URL?
	let symbol: String
	let identifier: String
	let open: () -> Void
	let openInBackground: () -> Void
	@State private var isHovered = false

	var body: some View {
		HStack(spacing: 8) {
			Button(action: open) {
				Label {
					VStack(alignment: .leading, spacing: 2) {
						Text(verbatim: title)
							.lineLimit(1)
						Text(verbatim: detail)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				} icon: {
					HistoryFaviconIcon(url: url, symbol: symbol)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open \(title)")
			.accessibilityIdentifier(identifier)

			#if os(macOS)
				if isHovered {
					backgroundButton
				}
			#else
				backgroundButton
			#endif
		}
		.onHover { isHovered = $0 }
	}

	private var backgroundButton: some View {
		Button(action: openInBackground) {
			Label("Open in Background", systemImage: "plus.square.on.square")
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.plain)
		.accessibilityLabel("Open \(title) in background")
		.accessibilityIdentifier("\(identifier)-background")
	}
}
