import SwiftUI

struct BrowserSidebarHeader: View {
	let browser: Browser
	let theme: BrowserTheme
	let isFullScreen: Bool
	let acceptsFocusRequests: Bool

	private var controller: BrowserController? {
		browser.chromeTab?.activeController
	}

	var body: some View {
		VStack(spacing: 2) {
			ViewThatFits(in: .horizontal) {
				regularHeader
				compactHeader
			}
			BrowserAddressField(
				browser: browser,
				usesGlassBackground: true,
				acceptsFocusRequests: acceptsFocusRequests
			)
		}
		.padding(.leading, 5)
		.padding(.trailing, 6)
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
		.frame(height: BrowserChromeMetrics.topBarRegionHeight)
		.padding(.top, 3)
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
			.frame(width: isFullScreen ? 0 : BrowserChromeMetrics.windowControlsAreaWidth - 16)
			.accessibilityHidden(true)
	}
}
