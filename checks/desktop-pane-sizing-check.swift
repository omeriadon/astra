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
					let left = leftShown ? BrowserChromeMetrics.sidebarWidth(
						preferred: BrowserChromeMetrics.expandedSidebarWidth,
						limits: BrowserChromeMetrics.sidebarWidthRange,
						availableWidth: width,
						minimumContentWidth: 270 + (rightShown ? 300 : 0)
					) : 0
					let right = rightShown ? BrowserChromeMetrics.sidebarWidth(
						preferred: min(360, width * 0.45) + BrowserChromeMetrics.shellEdgePadding,
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
		precondition(BrowserChromeMetrics.sidebarWidth(preferred: 1000, limits: 130 ... 330, availableWidth: 2000, minimumContentWidth: 270) == 330)
		precondition(BrowserChromeMetrics.sidebarWidth(preferred: 1000, limits: 300 ... 600, availableWidth: 2000, minimumContentWidth: 270) == 600)
		print("Desktop pane sizing checks passed")
	}
}
