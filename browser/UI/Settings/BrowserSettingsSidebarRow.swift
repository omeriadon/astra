import Defaults
import SwiftUI

struct BrowserSettingsSidebarRow: View {
	let title: String
	let symbol: String
	let isSelected: Bool
	let identifier: String
	let action: () -> Void
	@Default(.browserTheme) private var theme
	@State private var isHovered = false

	var body: some View {
		Button(action: action) {
			Label(title, systemImage: symbol)
				.frame(maxWidth: .infinity, alignment: .leading)
				.contentShape(Rectangle())
				.frame(height: 28)
		}
		.buttonStyle(.plain)
		.padding(.horizontal, 8)
		.foregroundStyle(theme.foregroundColor)
		.background {
			if isSelected {
				Color.clear
					.glassEffect(
						.clear,
						in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
					)
			}
		}
		.onHover { isHovered = $0 }
		.padding(.horizontal, BrowserChromeMetrics.shellEdgePadding)
		.accessibilityIdentifier(identifier)
		.accessibilityAddTraits(isSelected ? [.isSelected] : [])
	}
}
