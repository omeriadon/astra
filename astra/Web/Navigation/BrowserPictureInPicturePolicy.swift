struct BrowserPictureInPicturePolicy {
	static func preventsDestructiveTeardown(
		isActive: Bool,
		isEntering: Bool,
		isPlayingMedia: Bool,
		hasPausedMedia: Bool
	) -> Bool {
		isActive || isEntering || isPlayingMedia || hasPausedMedia
	}
}
