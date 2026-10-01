import SwiftUI
import WebKit

struct BrowserMediaActivityView: View {
	let browser: Browser

	var body: some View {
		VStack(spacing: 6) {
			ForEach(browser.tabs) { tab in
				if let controller = tab.controller {
					BrowserMediaActivityCard(controller: controller, title: tab.title) {
						browser.selectTab(tab.id)
					}
				}
				ForEach(tab.peeks) { peek in
					BrowserMediaActivityCard(
						controller: peek.controller,
						title: peek.controller.webViewIfLoaded?.title ?? tab.title
					) {
						browser.selectTab(tab.id)
					}
				}
			}
		}
	}
}

private struct BrowserMediaActivityCard: View {
	let controller: BrowserController
	let title: String
	let openTab: () -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		if controller.isPlayingMedia || controller.isCapturing || controller.pausedFromBrowser {
			HStack(spacing: 8) {
				Button(action: openTab) {
					Label {
						VStack(alignment: .leading, spacing: 3) {
							Text(verbatim: controller.mediaTitle ?? title)
								.font(.caption.weight(.semibold))
								.lineLimit(1)
							Text(controller.isCapturing ? "Camera or microphone in use" : controller.pausedFromBrowser ? "Paused — open the page to resume" : controller.mediaArtist ?? "Playing media")
								.font(.caption2)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
					} icon: {
						Image(systemName: controller.isCapturing ? "mic.fill" : "waveform")
							.symbolEffect(.variableColor, isActive: controller.isPlayingMedia && !reduceMotion)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Open \(title)")
				.accessibilityIdentifier("media-open-tab-\(controller.id)")
				if controller.isPlayingMedia {
					Button("Pause", systemImage: "pause.fill", action: controller.pauseMedia)
						.labelStyle(.iconOnly)
						.buttonStyle(.glass)
						.accessibilityIdentifier("media-pause-\(controller.id)")
				}
				if controller.isCapturing {
					Button("Stop Camera and Microphone", systemImage: "mic.slash", action: { controller.stopCapture() })
						.labelStyle(.iconOnly)
						.buttonStyle(.glass)
						.accessibilityIdentifier("media-stop-capture-\(controller.id)")
				}
			}
			.padding(10)
			.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
			.accessibilityIdentifier("media-activity-\(controller.id)")
		}
	}
}
