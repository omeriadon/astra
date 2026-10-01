import SwiftUI

struct BrowserHistoryView: View {
	let browser: Browser
	@State private var searchText = ""
	@State private var filteredVisits: [BrowserVisit] = []
	@State private var confirmsClear = false

	var body: some View {
		List {
			Section("Visited Pages") {
				ForEach(filteredVisits) { visit in
					HistoryRow(
						title: visit.title,
						detail: visit.url.absoluteString,
						url: visit.url,
						symbol: "clock.arrow.circlepath",
						identifier: "history-visit-\(visit.id)",
						open: { browser.openHistoryURL(visit.url, inBackground: false) },
						openInBackground: { browser.openHistoryURL(visit.url, inBackground: true) }
					)
					.contextMenu {
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
					Button("Clear History", systemImage: "trash", role: .destructive) {
						confirmsClear = true
					}
					.disabled(browser.historyVisits.isEmpty)
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
			Text("This removes visited-page records and recently closed tabs on this Mac. Your open pages and bookmarks are kept.")
		}
		.overlay {
			if filteredVisits.isEmpty {
				ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath")
			}
		}
	}

	private func updateVisits() {
		filteredVisits = browser.historyVisits.filter { visit in
			searchText.isEmpty || visit.title.localizedCaseInsensitiveContains(searchText)
				|| visit.url.absoluteString.localizedCaseInsensitiveContains(searchText)
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
