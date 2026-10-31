#if os(macOS)
	import SwiftUI

	struct BrowserTabMirrorView: View {
		let controller: BrowserController

		var body: some View {
			Group {
				if let image = controller.windowMirrorSnapshot ?? controller.previewSnapshot {
					Image(nsImage: image)
						.resizable()
						.scaledToFit()
				} else {
					Color.clear
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.allowsHitTesting(false)
			.accessibilityHidden(true)
			.accessibilityIdentifier("inactive-tab-mirror")
			.task(id: controller.id) {
				while !Task.isCancelled {
					await controller.refreshWindowMirrorSnapshot()
					do {
						// A duplicate-window mirror does not need video-rate updates.
						// One frame per second keeps it visibly live without turning
						// WKWebView snapshots into a steady CPU/GPU tax.
						try await Task.sleep(for: .seconds(1))
					} catch {
						return
					}
				}
			}
		}
	}
#endif
