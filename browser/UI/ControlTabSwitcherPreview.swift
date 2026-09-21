#if os(macOS)
	import SwiftUI

	struct ControlTabSwitcherPreview: View {
		let browser: Browser
		let switcher: ControlTabSwitcher

		private var visibleCandidateIDs: [UUID] {
			let ids = switcher.candidateIDs
			guard ids.count > 7,
			      let highlightedTabID = switcher.highlightedTabID,
			      let highlightedIndex = ids.firstIndex(of: highlightedTabID)
			else {
				return ids
			}

			let startIndex = min(max(0, highlightedIndex - 3), ids.count - 7)
			return Array(ids[startIndex ..< startIndex + 7])
		}

		var body: some View {
			if switcher.isPreviewVisible {
				HStack(spacing: 12) {
					ForEach(visibleCandidateIDs, id: \.self) { id in
						if let tab = browser.tabs.first(where: { $0.id == id }) {
							ControlTabSwitcherCandidateView(
								tab: tab,
								isSelected: switcher.highlightedTabID == id
							)
						}
					}
				}
				.padding(12)
				.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24))
				.accessibilityIdentifier("control-tab-switcher-preview")
			}
		}
	}
#endif
