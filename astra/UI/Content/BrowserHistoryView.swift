import SwiftUI

struct BrowserHistoryView: View {
	let browser: Browser
	@State private var searchText = ""
	@State private var filteredVisits: [BrowserVisit] = []
	@State private var confirmsClear = false
	@State private var confirmsRangeDelete = false
	@State private var rangeStart = Date.now
	@State private var rangeEnd = Date.now

	var body: some View {
		let visitCountsByURL = Dictionary(grouping: browser.historyVisits, by: \.url).mapValues(\.count)
		List {
			Section("Visited Pages") {
				ForEach(filteredVisits) { visit in
					HistoryRow(
						title: visit.title,
						detail: "\(visit.url.absoluteString) · \(visitCountsByURL[visit.url, default: 1]) visits",
						url: visit.url,
						symbol: "clock.arrow.circlepath",
						identifier: "history-visit-\(visit.id)",
						open: { browser.openHistoryURL(visit.url, inBackground: false) },
						openInBackground: { browser.openHistoryURL(visit.url, inBackground: true) }
					)
					.contextMenu {
						Button("Remove This Page from History", systemImage: "trash", role: .destructive) {
							browser.removeHistory(for: visit.url)
						}
						Button("Remove from History", systemImage: "trash", role: .destructive) {
							browser.removeHistory([visit.id])
						}
					}
				}
				.onDelete { offsets in
					browser.removeHistory(Set(offsets.map { filteredVisits[$0].id }))
				}
			}
		}
		#if os(iOS)
		.listStyle(.insetGrouped)
		#else
		.listStyle(.sidebar)
		#endif
		.scrollContentBackground(.hidden)
		.safeAreaBar(edge: .top) {
			VStack(alignment: .leading, spacing: 12) {
				HStack {
					Label("History", systemImage: "clock.arrow.circlepath")
						.font(.title2.bold())
					Spacer()
					BrowserLibraryTransferControls(browser: browser, scope: .history)
					Menu {
						Button("Last Hour", systemImage: "clock") { confirmDeleteRange(seconds: 3600) }
						Button("Last Day", systemImage: "calendar") { confirmDeleteRange(seconds: 86400) }
						Button("Last Week", systemImage: "calendar") { confirmDeleteRange(seconds: 604_800) }
						Button("Last Month", systemImage: "calendar") { confirmDeleteRange(seconds: 2_592_000) }
					} label: {
						Label("Delete History by Time Range", systemImage: "calendar.badge.clock")
					}
					.labelStyle(.iconOnly)
					.accessibilityLabel("Delete History by Time Range")
					.accessibilityIdentifier("delete-history-range")
					.disabled(browser.historyVisits.isEmpty)
					Button("Clear History", systemImage: "trash", role: .destructive) {
						confirmsClear = true
					}
					.disabled(browser.historyVisits.isEmpty && browser.closedHistoryTabs.isEmpty)
					.accessibilityIdentifier("clear-browsing-history")
				}
				TextField("Search History", text: $searchText)
					.textFieldStyle(.plain)
					.accessibilityIdentifier("history-search")
			}
			.padding(.horizontal, 24)
			.padding(.vertical, 14)
		}
		.onChange(of: browser.historyVisits, initial: true) { _, _ in updateVisits() }
		.onChange(of: searchText) { _, _ in updateVisits() }
		.confirmationDialog("Clear browsing history?", isPresented: $confirmsClear) {
			Button("Clear History", systemImage: "trash", role: .destructive) {
				browser.clearHistory()
			}
			Button(role: .cancel) {}
		} message: {
			Text("When sync is enabled, this removes browsing history from all synced devices. Recently closed tabs are cleared on this Mac. Open pages and bookmarks are kept.")
		}
		.confirmationDialog("Delete history from this time range?", isPresented: $confirmsRangeDelete) {
			Button("Delete History", systemImage: "trash", role: .destructive) {
				browser.removeHistory(from: rangeStart, until: rangeEnd)
			}
			Button(role: .cancel) {}
		} message: {
			Text("This removes visits from the selected period across normal windows and synced devices. Live pages remain open.")
		}
		.overlay {
			if filteredVisits.isEmpty {
				ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath")
			}
		}
	}

	private func updateVisits() {
		filteredVisits = BrowserVisit.matching(browser.recentHistoryVisits, query: searchText)
	}

	private func confirmDeleteRange(seconds: TimeInterval) {
		rangeEnd = Date.now.addingTimeInterval(0.001)
		rangeStart = rangeEnd.addingTimeInterval(-seconds)
		confirmsRangeDelete = true
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
			#if os(iOS)
				.frame(minHeight: 44)
			#endif
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
		#if os(iOS)
			.frame(width: 44, height: 44)
			.contentShape(Rectangle())
		#endif
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
