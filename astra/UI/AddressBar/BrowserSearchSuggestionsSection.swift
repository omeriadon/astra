import SwiftUI

struct BrowserSearchSuggestionsSection: View {
	let browser: Browser
	let results: [BrowserSearchResult]
	let query: String
	let generation: Int
	let selectedResultID: String?
	let fromNewTab: Bool
	let onSelect: (BrowserSearchResult) -> Void

	var body: some View {
		Section(query.isEmpty ? "Browser Actions" : "Suggestions") {
			ForEach(results) { result in
				Button {
					onSelect(result)
				} label: {
					Label {
						VStack(alignment: .leading, spacing: 2) {
							Text(verbatim: result.title).lineLimit(1)
							Text(verbatim: result.detail)
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					} icon: {
						BrowserSearchResultIcon(result: result)
							.frame(width: 20, height: 20)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.listRowBackground(Color.primary.opacity(selectedResultID == result.id ? 0.12 : 0))
				.accessibilityLabel("\(result.title), \(result.detail)")
				.accessibilityAddTraits(selectedResultID == result.id ? [.isSelected] : [])
				.accessibilityIdentifier("\(fromNewTab ? "new-tab-result" : "address-suggestion")-\(result.id)")
				.id(result.id)
				.contextMenu {
					if result.kind == .history,
					   let value = result.destination,
					   let url = URL(string: value)
					{
						Button("Remove from History", systemImage: "trash", role: .destructive) {
							browser.removeHistorySuggestion(
								id: result.id,
								url: url,
								query: query,
								generation: generation,
								fromNewTab: fromNewTab
							)
						}
						.accessibilityIdentifier("remove-history-\(result.id)")
					}
				}
			}
		}
	}
}
