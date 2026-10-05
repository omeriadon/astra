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
						try await Task.sleep(for: .milliseconds(500))
					} catch {
						return
					}
				}
			}
		}
	}
#endif
