import Foundation

// Run: swiftc browser/Models/BrowserTheme.swift Checks/BrowserThemePointIndependenceCheck.swift -o /tmp/browser-theme-point-check && /tmp/browser-theme-point-check
@main
struct BrowserThemePointIndependenceCheck {
	static func main() {
		var theme = BrowserTheme()
		let first = theme.meshColorPoints[0]
		_ = theme.addMeshColorPoint()
		_ = theme.addMeshColorPoint()
		_ = theme.addMeshColorPoint()
		precondition(theme.meshColorPoints.count == 4)
		precondition(theme.addMeshColorPoint() == nil)
		precondition(theme.meshColorPoints[0] == first)

		let others = Array(theme.meshColorPoints.dropFirst())
		theme.moveMeshColorPoint(id: first.id, to: CGPoint(x: 0.1, y: 0.9))
		precondition(Array(theme.meshColorPoints.dropFirst()) == others)
		precondition(theme.meshColorPoints[0].x == 0.1)

		theme.removeMeshColorPoint(id: others[0].id)
		precondition(theme.meshColorPoints.count == 3)
		precondition(theme.meshColorPoints[0].x == 0.1)
		precondition(theme.meshColorPoints[1] == others[1])
		for point in theme.meshColorPoints {
			theme.removeMeshColorPoint(id: point.id)
		}
		precondition(theme.meshColorPoints.isEmpty)
		print("PASS: 0–4 points can be added, moved, and removed independently")
	}
}
