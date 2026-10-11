import SwiftUI

struct BrowserSidebarHeader: View {
	let browser: Browser
	let theme: BrowserTheme
	let isFullScreen: Bool

	private var controller: BrowserController? {
		browser.selectedTab?.activeController
	}

	var body: some View {
		VStack(spacing: 4) {
			ViewThatFits(in: .horizontal) {
				regularHeader
				compactHeader
			}
			BrowserAddressField(browser: browser, usesGlassBackground: true)
		}
		.padding(.horizontal, 6)
		.padding(.vertical, 4)
		.frame(maxWidth: .infinity)
		.foregroundStyle(theme.foregroundColor)
		.environment(\.colorScheme, theme.foregroundColor == .black ? .light : .dark)
	}

	private var regularHeader: some View {
		HStack(spacing: 6) {
			windowControlsReservation
			navigationControls
		}
		.frame(height: BrowserChromeMetrics.topBarRegionHeight)
	}

	private var compactHeader: some View {
		VStack(spacing: 2) {
			HStack(spacing: 6) {
				windowControlsReservation
				Spacer(minLength: 0)
			}
			.frame(height: BrowserChromeMetrics.topBarRegionHeight)
			navigationControls
				.frame(height: BrowserChromeMetrics.topBarRegionHeight)
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
