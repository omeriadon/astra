import SwiftUI

struct BrowserFavouriteTile: View {
	let tab: BrowserTab
	let browser: Browser
	#if os(macOS)
		@Environment(\.openWindow) private var openWindow
		@State private var tabDrag = BrowserTabDragCoordinator.shared
	#endif

	var body: some View {
		Button {
			browser.selectTab(tab.id)
		} label: {
			Group {
				if let favicon = FaviconStore.shared.image(for: tab.currentURL, in: tab.controller?.webViewIfLoaded) {
					favicon.resizable().scaledToFit()
				} else {
					Image(systemName: tab.internalPage?.symbol ?? "globe")
				}
			}
			.frame(width: 20, height: 20)
			.frame(maxWidth: .infinity)
			.frame(height: 42)
			.contentShape(RoundedRectangle(cornerRadius: 10))
		}
		.buttonStyle(.plain)
		.background {
			RoundedRectangle(cornerRadius: 10)
				.fill(browser.selectedTabID == tab.id ? .white.opacity(0.3) : .white.opacity(0.12))
		}
		#if os(macOS)
		.background {
			BrowserDropZone(
				browser: browser,
				area: .favourite,
				spaceID: nil,
				beforeTabID: tab.id
			)
		}
		.highPriorityGesture(
			DragGesture(minimumDistance: 8)
				.onChanged { _ in
					if tabDrag.activeTabID != tab.id {
						browser.flushPersistence()
						tabDrag.begin(tab.id, from: browser)
					}
					tabDrag.update()
				}
				.onEnded { _ in
					tabDrag.drop(openWindow: openWindow)
				}
		)
		#endif
		.accessibilityLabel(tab.title)
		.accessibilityAddTraits(browser.selectedTabID == tab.id ? .isSelected : [])
		.accessibilityIdentifier("favourite-tab-\(tab.id.uuidString)")
		.contextMenu {
			Button("Move to Pinned Tabs", systemImage: "pin") {
				browser.moveTab(tab.id, to: .pinned)
			}
			Button("Move to Normal Tabs", systemImage: "rectangle") {
				browser.moveTab(tab.id, to: .normal)
			}
		}
	}
}
