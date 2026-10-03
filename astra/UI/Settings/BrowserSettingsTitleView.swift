import SwiftUI

struct BrowserSettingsTitleView: View {
	let page: BrowserSettingsView.Page
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		Text(LocalizedStringKey(page.definition.title))
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
}
