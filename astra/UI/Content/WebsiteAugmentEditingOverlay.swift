import SwiftUI
import WebKit

#if !ASTRA_WEBSITE_APP_RUNTIME
	/// Raster adaptation of Alessio Rubicini's AIEditingText / AITextRevealRenderer.
	/// A WKWebView cannot be drawn by SwiftUI's TextRenderer. Capture only at the
	/// editing boundaries and shade those pixels; never poll or replace the page.
	/// See WebsiteAugmentEditing-LICENSE.txt for the upstream MIT license.
	struct WebsiteAugmentEditingOverlay: View {
		let browser: Browser
		let tab: BrowserTab
		let cornerRadius: CGFloat
		@Environment(\.accessibilityReduceMotion) private var reduceMotion
		@Environment(\.colorScheme) private var colorScheme
		@Environment(\.scenePhase) private var scenePhase
		@State private var capture: Capture?
		@State private var startedAt = Date.now
		@State private var isRevealing = false

		private struct Capture {
			let controller: BrowserController
			let navigation: Int
			let scroll: BrowserScrollPosition
			let viewport: CGSize
			let surface: CGSize
			let isDark: Bool
			let image: Image

			func isCurrent(tab: BrowserTab, surface: CGSize) -> Bool {
				tab.activeController === controller
					&& controller.navigationIdentifier == navigation
					&& controller.scrollPosition == scroll
					&& controller.webViewIfLoaded?.bounds.size == viewport
					&& self.surface == surface
					&& !controller.isLoading
			}
		}

		private var isEditing: Bool {
			browser.aiChat.isAugmenting && browser.aiChat.augmentingTabID == tab.id
				&& browser.selectedTabID == tab.id
		}

		var body: some View {
			GeometryReader { geometry in
				let valid = capture?.isCurrent(tab: tab, surface: geometry.size) == true
				Group {
					if let capture, valid, !reduceMotion {
						TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active)) { context in
							let elapsed = max(0, context.date.timeIntervalSince(startedAt))
							capture.image
								.resizable()
								.frame(width: geometry.size.width, height: geometry.size.height)
								.colorEffect(ShaderLibrary.astraWebsiteEditing(
									.float2(geometry.size), .float(Float(elapsed)),
									.float(isRevealing ? 1 : 0),
									.float(capture.isDark ? 1 : 0)
								))
						}
					} else if isEditing {
						// Static feedback for Reduce Motion, failed captures, scrolling,
						// resizing, or an opened peek. The underlying page stays interactive.
						browser.theme.progressColor.opacity(0.06)
					}
				}
				.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
				.task(id: isEditing) {
					if isEditing {
						capture = nil
						isRevealing = false
						guard !reduceMotion else { return }
						let result = await snapshot(surface: geometry.size)
						guard !Task.isCancelled else { return }
						capture = result
						startedAt = .now
					} else {
						// An augmentation usually opens a new peek. Never stretch that
						// smaller viewport across the source pane or cover another tab.
						guard let previous = capture, valid, !reduceMotion,
						      browser.selectedTabID == tab.id
						else {
							capture = nil
							return
						}
						let result = await snapshot(surface: geometry.size)
						guard !Task.isCancelled else { return }
						guard result?.controller === previous.controller else {
							capture = nil
							return
						}
						capture = result
						isRevealing = true
						startedAt = .now
						try? await Task.sleep(for: .milliseconds(800))
						guard !Task.isCancelled else { return }
						capture = nil
						isRevealing = false
					}
				}
				.onChange(of: valid) { _, isValid in
					if !isValid {
						capture = nil
					}
				}
				.onChange(of: reduceMotion) { _, _ in capture = nil }
				.onDisappear { capture = nil }
			}
			.allowsHitTesting(false)
			.accessibilityHidden(true)
		}

		@MainActor
		private func snapshot(surface: CGSize) async -> Capture? {
			guard let controller = tab.activeController, !controller.isLoading,
			      controller.readerHTML == nil,
			      let webView = controller.webViewIfLoaded, !webView.bounds.isEmpty else { return nil }
			let navigation = controller.navigationIdentifier
			let scroll = controller.scrollPosition
			let viewport = webView.bounds.size
			// A peek or docked inspector can have a smaller viewport than the page pane.
			guard abs(viewport.width - surface.width) < 2,
			      abs(viewport.height - surface.height) < 2 else { return nil }
			let configuration = WKSnapshotConfiguration()
			configuration.rect = webView.bounds
			// snapshotWidth is in points; account for backing scale to cap pixels.
			#if os(macOS)
				let scale = max(1, unsafe webView.window?.backingScaleFactor ?? 2)
			#else
				let scale = max(1, webView.window?.screen.scale ?? 2)
			#endif
			configuration.snapshotWidth = NSNumber(value: min(viewport.width,
			                                                  min(1600, sqrt(2_000_000 * viewport.width / viewport.height)) / scale))
			guard let image = try? await webView.takeSnapshot(configuration: configuration),
			      !Task.isCancelled, tab.activeController === controller,
			      controller.navigationIdentifier == navigation,
			      controller.scrollPosition == scroll, webView.bounds.size == viewport,
			      browser.selectedTabID == tab.id, !reduceMotion else { return nil }
			#if os(macOS)
				guard let pixels = unsafe image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
			#else
				guard let pixels = image.cgImage else { return nil }
			#endif
			return Capture(controller: controller, navigation: navigation, scroll: scroll,
			               viewport: viewport, surface: surface,
			               isDark: !(controller.themeColorIsLight ?? (colorScheme == .light)), image: Image(decorative: pixels, scale: 1))
		}
	}
#endif
