import Defaults
import SwiftUI
import WebKit

struct ShellDownloadsBarView: View {
	let browser: Browser
	let theme: BrowserTheme
	@Default(.aiFeaturesEnabled) private var allAIFeatures
	let downloads: BrowserDownloadManager
	@Binding var showsDownloads: Bool
	@State private var downloadsHover = false
	@State private var addSpaceHover = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		HStack {
			Button {
				withAnimation(reduceMotion ? .none : .smooth(duration: 0.32)) {
					showsDownloads.toggle()
				}
			} label: {
				HStack(spacing: 9) {
					ZStack {
						Image(systemName: downloads.buttonSymbol)
						if let progress = downloads.activeProgress {
							Circle()
								.trim(from: 0, to: progress)
								.stroke(theme.progressColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
								.rotationEffect(.degrees(-90))
						}
					}
				}
				.frame(width: 25, height: 25)
				.background {
					if downloadsHover {
						RoundedRectangle(cornerRadius: 8)
							.fill(Color.primary.gradient)
							.opacity(0.3)
					}
					if showsDownloads {
						RoundedRectangle(cornerRadius: 8)
							.fill(Color.primary.gradient)
							.opacity(0.4)
					}
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.keyboardShortcut("J", modifiers: .command)
			.accessibilityLabel(showsDownloads ? "Show Tabs" : "Show Downloads")
			.accessibilityValue(downloads.activeProgress.map { "\(Int($0 * 100)) percent" } ?? "No active downloads")
			.accessibilityIdentifier("downloads-button")
			.onHover { i in
				withAnimation(.smooth(duration: 0.1)) {
					downloadsHover = i
				}
			}

			if browser.isPrivate {
				Label("Private", systemImage: "eye.slash")
					.font(.caption)
					.frame(maxWidth: .infinity)
			} else {
				BrowserSpacesBar(browser: browser)
					.frame(maxWidth: .infinity)
			}

			if allAIFeatures, browser.canShowAISidebar, Defaults[.aiSidebar] {
				Button("AI Sidebar", systemImage: "bubble.left.and.text.bubble.right") {
					browser.showsAISidebar.toggle()
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.plain)
				.accessibilityIdentifier("sidebar-ai-toggle")
			}

			if !browser.isPrivate {
				Button {
					browser.createSpace()
				} label: {
					Image(systemName: "plus")
						.frame(width: 25, height: 25)
						.background {
							if addSpaceHover {
								RoundedRectangle(cornerRadius: 8)
									.fill(Color.primary.gradient)
									.opacity(0.3)
							}
						}
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Add Space")
				.accessibilityIdentifier("add-space")
				.onHover { addSpaceHover = $0 }
			}
		}
		.padding([.horizontal, .bottom], 8)
	}
}
