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

	var body: some View {
		// Do not pin idle tabs here solely because WebKit has a paused player,
		// a muted element or a video eligible for Picture in Picture.
		if controller.isPlayingMedia || controller.isCapturing || controller.pausedFromBrowser || controller.isPictureInPictureActive || controller.isEnteringPictureInPicture {
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
						if controller.isCapturing {
							Image(systemName: "mic.fill")
						} else if controller.isPlayingMedia {
							PlayingMediaWaveform()
						} else {
							Image(systemName: "pause.fill")
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Open \(title)")
				.accessibilityIdentifier("media-open-tab-\(controller.id)")
				if controller.canEnterPictureInPicture && !controller.isPictureInPictureActive && !controller.isEnteringPictureInPicture {
					Button("Enter Picture in Picture", systemImage: "pip", action: controller.enterPictureInPicture)
						.labelStyle(.iconOnly)
						.buttonStyle(.glass)
						.accessibilityHint("Attempts browser entry. WebKit may require a gesture in the page or provider support.")
						.accessibilityIdentifier("media-picture-in-picture-\(controller.id)")
				}
				if controller.isPictureInPictureActive || controller.isEnteringPictureInPicture {
					Button("Show Picture in Picture Tab", systemImage: "arrow.uturn.backward", action: controller.returnToPictureInPictureSource)
						.labelStyle(.iconOnly)
						.buttonStyle(.glass)
						.accessibilityIdentifier("media-return-picture-in-picture-\(controller.id)")
				}
				if controller.isPlayingMedia {
					Button("Pause", systemImage: "pause.fill", action: controller.pauseMedia)
						.labelStyle(.iconOnly)
						.buttonStyle(.glass)
						.accessibilityIdentifier("media-pause-\(controller.id)")
				}
				if controller.hasPausedMedia || controller.pausedFromBrowser {
					Button("Resume players", systemImage: "play.fill", action: controller.resumeMedia)
						.labelStyle(.iconOnly)
						.buttonStyle(.glass)
						.accessibilityHint("Attempts to resume embedded players. Other page audio may continue or require interaction in the page.")
						.accessibilityIdentifier("media-resume-\(controller.id)")
				}
				if controller.isPlayingMedia || controller.hasPausedMedia || controller.pausedFromBrowser || controller.areMediaElementsMuted {
					Button(
						controller.areMediaElementsMuted ? "Unmute players" : "Mute players",
						systemImage: controller.areMediaElementsMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
						action: controller.toggleMediaElementsMuted
					)
					.labelStyle(.iconOnly)
					.buttonStyle(.glass)
					.accessibilityHint("Mutes embedded audio and video players. Other page audio may continue.")
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
		if controller.pictureInPictureControlUnavailable {
			return "Use the video's own Picture in Picture control"
		}
		if controller.isPictureInPictureActive || controller.isEnteringPictureInPicture {
			return "Picture in Picture"
		}
		if controller.isCapturing {
			return "Camera or microphone in use"
		}
		if controller.pausedFromBrowser {
			return "Paused by Astra"
		}
		if controller.areMediaElementsMuted {
			return "Players muted"
		}
		if controller.isPlayingMedia {
			return controller.mediaArtist ?? "Playing media"
		}
		return controller.hasPausedMedia ? "Paused media" : "Picture in Picture available"
	}
}

/// This is a decorative playback indicator, not a meter of actual audio levels.
/// It is inserted only while media is playing, stopping the loop on pause.
private struct PlayingMediaWaveform: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var drawingHeight = false

	private let height: CGFloat = 16
	private let animation = Animation.linear(duration: 0.5).repeatForever(autoreverses: true)

	var body: some View {
		HStack(alignment: .bottom, spacing: 2) {
			bar(low: 0.4, speed: 1.5)
			bar(low: 0.3, speed: 1.2)
			bar(low: 0.5, speed: 1.0)
			bar(low: 0.3, speed: 1.7)
			bar(low: 0.5, speed: 1.0)
		}
		.frame(width: 18, height: height)
		.onAppear { drawingHeight = !reduceMotion }
		.onChange(of: reduceMotion) { _, reduced in
			drawingHeight = !reduced
		}
		.accessibilityHidden(true)
	}

	private func bar(low: CGFloat, speed: Double) -> some View {
		RoundedRectangle(cornerRadius: 1)
			.fill(.tint)
			.frame(width: 2, height: (drawingHeight ? 1 : low) * height)
			.frame(height: height, alignment: .bottom)
			.animation(reduceMotion ? nil : animation.speed(speed), value: drawingHeight)
	}
}
