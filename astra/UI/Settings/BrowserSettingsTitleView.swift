import SwiftUI

struct BrowserSettingsTitleView: View {
	let page: BrowserSettingsView.Page

	var body: some View {
		Text(LocalizedStringKey(page.definition.title))
			.monospaced()
			.font(.title2.bold())
			.lineLimit(1)
			.minimumScaleFactor(0.7)
			.contentTransition(.numericText())
			.geometryGroup()
			.environment(\.contentTransitionAddsDrawingGroup, true)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 12)
			.padding(.top, 14)
			.padding(.bottom, 14)
	}
}
