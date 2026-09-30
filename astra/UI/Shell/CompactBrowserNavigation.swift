nonisolated struct CompactBrowserNavigation {
	var showsPage = false
	private(set) var sourceID = "sidebar"

	mutating func open(from sourceID: String) {
		// Keep the return transition attached to the original sidebar source.
		guard !showsPage else { return }
		self.sourceID = sourceID
		showsPage = true
	}
}
