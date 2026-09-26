import SwiftUI

struct BrowserSettingsTitleView: View {
	let page: BrowserSettingsView.Page
	@State private var displayedPage: BrowserSettingsView.Page
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	init(page: BrowserSettingsView.Page) {
		self.page = page
		_displayedPage = State(initialValue: page)
	}

	private var title: LocalizedStringKey {
		switch displayedPage {
			case .ui: "UI"
			case .account: "Account & Sync"
			case .about: "About astra"
			#if DEBUG
				case .failedWebsiteStates: "Failed Website States"
			#endif
		}
	}

	var body: some View {
		Text(title)
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
