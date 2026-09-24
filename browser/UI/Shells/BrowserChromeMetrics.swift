import SwiftUI

enum BrowserChromeMetrics {
	static let topBarRegionHeight: CGFloat = 33
	static let expandedSidebarWidth: CGFloat = 224

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
	static let windowDragStripHeight: CGFloat = 3
}
