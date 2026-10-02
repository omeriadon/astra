@main
enum Task16ChromeFindZoomCheck {
	static func main() {
		assert(BrowserZoomPolicy.clamp(0.25) == 0.25)
		assert(BrowserZoomPolicy.clamp(5) == 5)
		assert(BrowserZoomPolicy.clamp(0.1) == 0.25)
		assert(BrowserZoomPolicy.clamp(8) == 5)
		assert(BrowserZoomPolicy.clamp(.infinity) == BrowserZoomPolicy.defaultZoom)
		assert(BrowserZoomPolicy.clamp(.nan) == BrowserZoomPolicy.defaultZoom)

		var findGeneration = BrowserFindGeneration()
		let firstRequest = findGeneration.advance()
		assert(findGeneration.accepts(firstRequest))
		let replacementRequest = findGeneration.advance()
		assert(findGeneration.accepts(replacementRequest))
		assert(!findGeneration.accepts(firstRequest))

		print("Task 16 chrome/find/zoom checks passed")
	}
}
