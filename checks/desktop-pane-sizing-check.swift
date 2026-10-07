// Run: swiftc astra/UI/Chrome/BrowserChromeMetrics.swift checks/desktop-pane-sizing-check.swift -o /tmp/astra-desktop-pane-sizing-check && /tmp/astra-desktop-pane-sizing-check
import Foundation

@main
struct DesktopPaneSizingCheck {
	static func main() {
		for leftShown in [false, true] {
			for rightShown in [false, true] {
				let expectedMinimum: CGFloat = 270 + (leftShown ? 130 : 0) + (rightShown ? 300 : 0)
				let minimum = BrowserChromeMetrics.minimumWindowWidth(sidebarShown: leftShown, aiSidebarShown: rightShown)
				precondition(minimum == expectedMinimum)
				for width in stride(from: minimum, through: 3000, by: 1) {
					for preferred in [CGFloat(-100), 130, 224, 300, 330, 600, 1000] {
						let left = leftShown ? BrowserChromeMetrics.sidebarWidth(
							preferred: preferred,
							limits: BrowserChromeMetrics.sidebarWidthRange,
							availableWidth: width,
							minimumContentWidth: 270 + (rightShown ? 300 : 0)
						) : 0
						let right = rightShown ? BrowserChromeMetrics.sidebarWidth(
							preferred: preferred,
							limits: BrowserChromeMetrics.aiSidebarWidthRange,
							availableWidth: width - left,
							minimumContentWidth: BrowserChromeMetrics.minimumContentWidth
						) : 0
						precondition(!leftShown || (130 ... 330).contains(left))
						precondition(!rightShown || (300 ... 600).contains(right))
						precondition(width - left - right >= 270)
					}
				}
			}
		}
		precondition(BrowserChromeMetrics.sidebarWidth(preferred: 1000, limits: 130 ... 330, availableWidth: 2000, minimumContentWidth: 270) == 330)
		precondition(BrowserChromeMetrics.sidebarWidth(preferred: 1000, limits: 300 ... 600, availableWidth: 2000, minimumContentWidth: 270) == 600)
		precondition(BrowserChromeMetrics.sidebarWidthRange == 130 ... 330)
		precondition(BrowserChromeMetrics.aiSidebarWidthRange == 300 ... 600)
		for isSettings in [false, true] {
			let pageMinimum = BrowserChromeMetrics.minimumPageWidth(isSettings: isSettings)
			if isSettings {
				let detailWidth = pageMinimum - BrowserChromeMetrics.shellEdgePadding * 2
					- BrowserChromeMetrics.settingsSidebarWidth - BrowserChromeMetrics.settingsDetailPadding * 2 - 1
				precondition(detailWidth == BrowserChromeMetrics.minimumContentWidth)
			}
			for width: CGFloat in stride(from: 0, through: 1600, by: 7) {
				for leftProgress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
					for rightProgress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
						for preferred: CGFloat in [130, 224, 330, 600, 1000] {
							let leftMinimum = pageMinimum + BrowserChromeMetrics.aiSidebarWidthRange.lowerBound * rightProgress
							let left = reservedWidth(
								available: width,
								minimum: leftMinimum,
								limits: BrowserChromeMetrics.sidebarWidthRange,
								preferred: preferred,
								progress: leftProgress
							)
							let right = reservedWidth(
								available: width - left,
								minimum: pageMinimum,
								limits: BrowserChromeMetrics.aiSidebarWidthRange,
								preferred: preferred,
								progress: rightProgress
							)
							precondition(width - left - right >= min(width, pageMinimum))
							precondition(left >= 0 && right >= 0)
						}
					}
				}
			}
		}
		print("Desktop pane sizing checks passed")
	}

	private static func reservedWidth(
		available: CGFloat,
		minimum: CGFloat,
		limits: ClosedRange<CGFloat>,
		preferred: CGFloat,
		progress: CGFloat
	) -> CGFloat {
		guard BrowserChromeMetrics.sidebarFits(
			availableWidth: available,
			minimumContentWidth: minimum,
			limits: limits
		) else { return 0 }
		return BrowserChromeMetrics.sidebarWidth(
			preferred: preferred,
			limits: limits,
			availableWidth: available,
			minimumContentWidth: minimum
		) * progress
	}
}
