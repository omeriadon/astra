import SwiftUI

struct BrowserHistoryView: View {
	let browser: Browser

	var body: some View {
		List {
			Section("Open Tabs") {
				ForEach(browser.openHistoryTabs) { tab in
					tabHistory(tab)
				}
			}

			Section("Closed Tabs") {
				ForEach(Array(browser.closedHistoryTabs.enumerated()), id: \.offset) { item in
					tabHistory(item.element)
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
			if browser.openHistoryTabs.isEmpty, browser.closedHistoryTabs.isEmpty {
				ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath")
			}
		}
	}

	private func tabHistory(_ tab: OpenTab) -> some View {
		DisclosureGroup {
			ForEach(Array(tab.history.enumerated()), id: \.offset) { index, url in
				HistoryRow(
					title: url.host ?? url.absoluteString,
					detail: url.absoluteString,
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
				symbol: "rectangle.on.rectangle",
				identifier: "history-tab-\(tab.id.uuidString)",
				open: { browser.openHistoryTab(tab, inBackground: false) },
				openInBackground: { browser.openHistoryTab(tab, inBackground: true) }
			)
		}
	}
}

private struct HistoryRow: View {
	let title: String
	let detail: String
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
					Image(systemName: symbol)
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
