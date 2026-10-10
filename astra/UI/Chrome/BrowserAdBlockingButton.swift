import Defaults
import SwiftUI

struct BrowserAdBlockingButton: View {
	let controller: BrowserController
	@Default(.adBlockingEnabled) private var adBlockingEnabled

	private var origin: String? {
		guard let url = controller.committedURL ?? controller.url,
		      let scheme = url.scheme?.lowercased(),
		      scheme == "http" || scheme == "https"
		else { return nil }
		return BrowserSitePermissions.origin(for: url)
	}

	private var isBlocked: Bool {
		guard let origin else { return false }
		return adBlockingEnabled
			&& controller.session.contentBlocking.isActive
			&& !controller.session.sitePreferences.disablesNativeContentBlocking(for: origin)
	}

	var body: some View {
		Button(
			isBlocked ? "Turn Off Ad Blocking for This Site" : "Turn On Ad Blocking for This Site",
			systemImage: isBlocked ? "shield.checkered" : "shield.slash"
		) {
			guard let origin else { return }
			controller.session.sitePreferences.setNativeContentBlockingDisabled(isBlocked, for: origin)
			controller.reload()
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.glass)
		.tint(isBlocked ? nil : .orange)
		.disabled(
			origin == nil
				|| !adBlockingEnabled
				|| !controller.hasCurrentPageDocument
				|| controller.session.sitePreferences.isLocalDataReadOnly
		)
		.accessibilityLabel(isBlocked ? "Turn off ad blocking for this site" : "Turn on ad blocking for this site")
		.accessibilityValue(adBlockingEnabled ? (isBlocked ? "On" : "Off") : "Global ad blocking off")
		.accessibilityIdentifier("browser-ad-blocking-toggle")
		.help(isBlocked ? "Turn off ad blocking for this site" : "Turn on ad blocking for this site")
	}
}
