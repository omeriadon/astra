import SwiftUI

struct BrowserHistoryView: View {
	let browser: Browser
	@State private var cachedHistory: [OpenTab]
	@State private var cachedHistoryKey: HistoryCacheKey

	init(browser: Browser) {
		self.browser = browser
		let history = Self.computeHistoryTabs(browser: browser)
		_cachedHistory = State(initialValue: history)
		_cachedHistoryKey = State(initialValue: Self.historyKey(browser: browser))
	}

	/// Every openTab mutation bumps modifiedAt to now (which always exceeds the
	/// previous maximum), so counts + maxima capture all inputs to the compute.
	private struct HistoryCacheKey: Equatable {
		var tabCount: Int
		var closedCount: Int
		var latestTabModification: Double
		var latestClosedModification: Double
	}

	private static func historyKey(browser: Browser) -> HistoryCacheKey {
		HistoryCacheKey(
			tabCount: browser.tabs.count,
			closedCount: browser.closedHistoryTabs.count,
			latestTabModification: browser.tabs.map(\.modifiedAt.timeIntervalSince1970).max() ?? 0,
			latestClosedModification: browser.closedHistoryTabs.map(\.modifiedAt.timeIntervalSince1970).max() ?? 0
		)
	}

	private static func computeHistoryTabs(browser: Browser) -> [OpenTab] {
		// Filter live tabs by currentURL before copying full histories via openTab.
		let live = browser.tabs.filter { $0.internalPage == nil && $0.currentURL != nil }
			.map(\.openTab)
			.filter { $0.url != nil }
		return (live + browser.closedHistoryTabs.filter { $0.url != nil })
			.sorted { $0.modifiedAt > $1.modifiedAt }
	}

	var body: some View {
		HistoryListView(browser: browser, historyTabs: cachedHistory)
			.onChange(of: Self.historyKey(browser: browser)) { _, _ in
				cachedHistoryKey = Self.historyKey(browser: browser)
				cachedHistory = Self.computeHistoryTabs(browser: browser)
			}
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
			Text("History")
				.monospaced()
				.font(.largeTitle.bold())
				.lineLimit(1)
				.minimumScaleFactor(0.7)
				.contentTransition(.numericText())
				.geometryGroup()
				.environment(\.contentTransitionAddsDrawingGroup, true)
				.frame(height: 42)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 24)
				.padding(.top, 12)
				.padding(.bottom, 12)
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
				.equatable()
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
			.equatable()
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

struct HistoryRow: View {
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

/// Actions are derived from (browser, tab, url), so data equality implies
/// action equality; closures are intentionally excluded.
extension HistoryRow: Equatable {
	static func == (lhs: HistoryRow, rhs: HistoryRow) -> Bool {
		lhs.title == rhs.title
			&& lhs.detail == rhs.detail
			&& lhs.url == rhs.url
			&& lhs.symbol == rhs.symbol
			&& lhs.identifier == rhs.identifier
	}
}
