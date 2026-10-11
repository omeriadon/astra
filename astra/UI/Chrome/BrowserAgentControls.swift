import SwiftUI

struct BrowserAgentControls: View {
	let browser: Browser
	#if os(macOS)
		@State private var server = BrowserAgentServer.shared
	#endif

	var body: some View {
		#if os(macOS)
			if let tab = browser.selectedTab, server.isEnabled {
				if server.isControlled(tab.id) {
					controlledControls(tabID: tab.id)
				} else if canShare(tab) {
					shareButton(tab: tab)
				}
			}
		#else
			EmptyView()
		#endif
	}

	#if os(macOS)
		private func canShare(_ tab: BrowserTab) -> Bool {
			!browser.isPrivate
				&& !browser.isShowingNewTab
				&& tab.internalPage == nil
				&& tab.currentURL != nil
		}

		private func shareButton(tab: BrowserTab) -> some View {
			Button("Share with Browser Use", systemImage: "rectangle.portrait.and.arrow.forward") {
				server.share(tab: tab, in: browser)
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.bordered)
			.help("Share this page with Browser Use")
			.accessibilityLabel("Share with Browser Use")
			.accessibilityIdentifier("share-with-browser-use")
		}

		private func controlledControls(tabID: UUID) -> some View {
			HStack(spacing: 6) {
				Label("Controlled by Browser Use", systemImage: "person.crop.circle.badge.checkmark")
					.font(.caption)
					.lineLimit(1)
					.accessibilityIdentifier("browser-use-controlled-label")
				Button("Revoke Browser Access", systemImage: "person.crop.circle.badge.xmark") {
					server.revoke(tabID)
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.bordered)
				.help("Revoke Browser Use access to this page")
				.accessibilityLabel("Revoke Browser Access")
				.accessibilityHint("Stops Browser Use from accessing this page")
				.accessibilityIdentifier("revoke-browser-access")
			}
		}
	#endif
}

#if os(macOS)
	struct BrowserAgentControlledPageBorder: View {
		let cornerRadius: CGFloat

		var body: some View {
			let radius = max(0, cornerRadius - 1)
			ZStack {
				RoundedRectangle(cornerRadius: radius)
					.stroke(.white, lineWidth: 2)
				RoundedRectangle(cornerRadius: radius)
					.stroke(.blue, style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
			}
			.allowsHitTesting(false)
			.accessibilityHidden(true)
		}
	}
#endif
