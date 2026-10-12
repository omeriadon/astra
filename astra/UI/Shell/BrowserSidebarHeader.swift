import SwiftUI

struct BrowserSidebarHeader: View {
	let browser: Browser
	let theme: BrowserTheme
	let isFullScreen: Bool

	private var controller: BrowserController? {
		browser.selectedTab?.activeController
	}

	var body: some View {
		VStack(spacing: 2) {
			ViewThatFits(in: .horizontal) {
				regularHeader
				compactHeader
			}
			BrowserAddressField(browser: browser, usesGlassBackground: true)
		}
		.padding(.horizontal, 5)
		.padding(.top, 0)
		.padding(.bottom, 2)
		.frame(maxWidth: .infinity)
		.foregroundStyle(theme.foregroundColor)
		.environment(\.colorScheme, theme.foregroundColor == .black ? .light : .dark)
	}

	private var regularHeader: some View {
		HStack(spacing: 6) {
			windowControlsReservation
			navigationControls
		}
		.frame(height: 24, alignment: .top)
	}

	private var compactHeader: some View {
		VStack(spacing: 2) {
			HStack(spacing: 6) {
				windowControlsReservation
				Spacer(minLength: 0)
			}
			.frame(height: 24)
			navigationControls
				.frame(height: 24)
		}
	}

	@ViewBuilder
	private var navigationControls: some View {
		if let controller {
			BrowserHistoryNavigationControls(
				controller: controller,
				browser: browser,
				separatesReload: true
			)
		}
	}

	private var windowControlsReservation: some View {
		Color.clear
			.frame(width: isFullScreen ? 0 : BrowserChromeMetrics.windowControlsAreaWidth)
			.accessibilityHidden(true)
	}
}
