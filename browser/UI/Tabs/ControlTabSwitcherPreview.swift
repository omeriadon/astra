#if os(macOS)
	import SwiftUI

	struct ControlTabSwitcherPreview: View {
		let browser: Browser
		let switcher: ControlTabSwitcher

		private let spacing: CGFloat = 12
		private let padding: CGFloat = 12
		private let horizontalMargin: CGFloat = 20

		private func visibleCandidateIDs(fitting width: CGFloat) -> [UUID] {
			let ids = switcher.candidateIDs
			let availableWidth = max(0, width - horizontalMargin * 2 - padding * 2)
			let visibleCount = min(
				ids.count,
				max(1, Int((availableWidth + spacing) / (ControlTabSwitcherCandidateView.totalWidth + spacing)))
			)
			guard ids.count > visibleCount,
			      let anchorID = switcher.candidateWindowAnchorID,
			      let anchorIndex = ids.firstIndex(of: anchorID)
			else {
				return ids
			}

			let startIndex = min(
				max(0, anchorIndex - visibleCount / 2),
				ids.count - visibleCount
			)
			return Array(ids[startIndex ..< startIndex + visibleCount])
		}

		var body: some View {
			GeometryReader { geometry in
				if switcher.isPreviewVisible {
					HStack(spacing: spacing) {
						ForEach(visibleCandidateIDs(fitting: geometry.size.width), id: \.self) { id in
							if let tab = browser.tabs.first(where: { $0.id == id }) {
								ControlTabSwitcherCandidateView(
									tab: tab,
									isSelected: switcher.highlightedTabID == id,
									onHover: { switcher.highlight(id) },
									action: { switcher.select(id) }
								)
							}
						}
					}
					.padding(padding)
					.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24))
					.accessibilityIdentifier("control-tab-switcher-preview")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
		}
	}
#endif
