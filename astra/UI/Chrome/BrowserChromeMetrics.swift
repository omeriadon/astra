import Foundation

enum BrowserChromeMetrics {
	static let topBarRegionHeight: CGFloat = 33
	static let expandedSidebarWidth: CGFloat = 224
	static let sidebarWidthRange: ClosedRange<CGFloat> = 130 ... 330
	static let aiSidebarWidthRange: ClosedRange<CGFloat> = 300 ... 600
	static let minimumContentWidth: CGFloat = 270
	static let settingsSidebarWidth: CGFloat = 230
	static let settingsDetailPadding: CGFloat = 16

	static func minimumPageWidth(isSettings: Bool) -> CGFloat {
		minimumContentWidth + shellEdgePadding * 2
			+ (isSettings ? settingsSidebarWidth + settingsDetailPadding * 2 + 1 : 0)
	}

	static func minimumWindowWidth(
		sidebarShown: Bool,
		aiSidebarShown: Bool,
		minimumContentWidth: CGFloat = minimumContentWidth
	) -> CGFloat {
		minimumContentWidth
			+ (sidebarShown ? sidebarWidthRange.lowerBound : 0)
			+ (aiSidebarShown ? aiSidebarWidthRange.lowerBound : 0)
	}

	static func sidebarFits(
		availableWidth: CGFloat,
		minimumContentWidth: CGFloat,
		limits: ClosedRange<CGFloat>
	) -> Bool {
		availableWidth >= minimumContentWidth + limits.lowerBound
	}

	static func sidebarWidth(
		preferred: CGFloat,
		limits: ClosedRange<CGFloat>,
		availableWidth: CGFloat,
		minimumContentWidth: CGFloat
	) -> CGFloat {
		max(limits.lowerBound, min(preferred, limits.upperBound, availableWidth - minimumContentWidth))
	}

	static let topBarContentHeight: CGFloat = 20

	// macos 27 window radius is 20

	// Includes the space reserved for macOS window controls.
	static let persistentControlsAreaWidth: CGFloat = 160
	static let shellEdgePadding: CGFloat = 4
	static let tabWindowCornerRadiusWithSidebar: CGFloat = 12.5
	static let tabWindowCornerRadiusWithoutSidebar: CGFloat = 16

	static let compactTabWindowCornerRadius: CGFloat = 28

	// Sizes the icon label inside each bordered top-bar button.
	static let topBarButtonLabelWidth: CGFloat = 0
	static let topBarButtonLabelHeight: CGFloat = 11
	static let topBarButtonCornerRadius: CGFloat = 12
}
