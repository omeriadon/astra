@main
struct PictureInPicturePolicyCheck {
	static func main() {
		assert(!BrowserPictureInPicturePolicy.preventsDestructiveTeardown(
			isActive: false,
			isEntering: false,
			isPlayingMedia: false,
			hasPausedMedia: false
		))
		assert(BrowserPictureInPicturePolicy.preventsDestructiveTeardown(
			isActive: true,
			isEntering: false,
			isPlayingMedia: false,
			hasPausedMedia: false
		))
		assert(BrowserPictureInPicturePolicy.preventsDestructiveTeardown(
			isActive: false,
			isEntering: true,
			isPlayingMedia: false,
			hasPausedMedia: false
		))
		assert(BrowserPictureInPicturePolicy.preventsDestructiveTeardown(
			isActive: false,
			isEntering: false,
			isPlayingMedia: true,
			hasPausedMedia: false
		))
		assert(BrowserPictureInPicturePolicy.preventsDestructiveTeardown(
			isActive: false,
			isEntering: false,
			isPlayingMedia: false,
			hasPausedMedia: true
		))
		print("picture-in-picture protection checks passed")
	}
}
