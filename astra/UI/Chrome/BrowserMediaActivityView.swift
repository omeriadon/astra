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
		if controller.isPlayingMedia || controller.hasPausedMedia || controller.isCapturing || controller.pausedFromBrowser || controller.areMediaElementsMuted {
			HStack(spacing: 8) {
				Button(action: openTab) {
					Label {
						VStack(alignment: .leading, spacing: 3) {
							Text(verbatim: controller.mediaTitle ?? title)
								.font(.caption.weight(.semibold))
								.lineLimit(1)
							Text(activityDescription)
								.font(.caption2)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
					} icon: {
						Image(systemName: controller.isCapturing ? "mic.fill" : controller.isPlayingMedia ? "waveform" : "pause.fill")
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
				if controller.hasPausedMedia || controller.pausedFromBrowser {
					Button("Try Resume Audio and Video", systemImage: "play.fill", action: controller.resumeMedia)
						.labelStyle(.iconOnly)
						.buttonStyle(.glass)
						.accessibilityIdentifier("media-resume-\(controller.id)")
				}
				if controller.isPlayingMedia || controller.hasPausedMedia || controller.pausedFromBrowser {
					Button(
						controller.areMediaElementsMuted ? "Unmute Main-Frame Audio and Video" : "Mute Main-Frame Audio and Video",
						systemImage: controller.areMediaElementsMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
						action: controller.toggleMediaElementsMuted
					)
					.labelStyle(.iconOnly)
					.buttonStyle(.glass)
					.accessibilityIdentifier("media-mute-\(controller.id)")
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

	private var activityDescription: String {
		if controller.isCapturing {
			return "Camera or microphone in use"
		}
		if controller.pausedFromBrowser {
			return "Paused by Astra"
		}
		if controller.areMediaElementsMuted {
			return "Main-frame HTML audio/video muted"
		}
		if controller.isPlayingMedia {
			return controller.mediaArtist ?? "Playing media"
		}
		return "Paused media"
	}
}
