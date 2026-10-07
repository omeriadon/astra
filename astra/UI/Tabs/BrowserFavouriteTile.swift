import SwiftUI

struct BrowserFavouriteTile: View {
	let tab: BrowserTab
	let browser: Browser
	var onSelectTab: ((UUID) -> Void)?
	var navigationNamespace: Namespace.ID?
	@Namespace private var tileTransitions
	#if os(macOS)
		@State private var tabDrag = BrowserTabDragCoordinator.shared
	#endif

	var body: some View {
		Button {
			browser.selectTab(tab.id)
			onSelectTab?(tab.id)
		} label: {
			FavouriteIconView(tab: tab)
		}
		.buttonStyle(.plain)
		.matchedTransitionSource(id: tab.id.uuidString, in: navigationNamespace ?? tileTransitions)
		.background {
			RoundedRectangle(cornerRadius: 10)
				.fill(browser.selectedTabID == tab.id ? .white.opacity(0.3) : .white.opacity(0.12))
		}
		.overlay {
			if browser.selectedTabID == tab.id, tab.isDeveloperMode {
				RoundedRectangle(cornerRadius: 10)
					.strokeBorder(Color(red: 0.55, green: 0.4, blue: 0), lineWidth: 2)
					.overlay {
						RoundedRectangle(cornerRadius: 10)
							.strokeBorder(.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
					}
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			}
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
					tabDrag.drop()
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
			if tab.internalPage == nil {
				Button("Add to Reading List", systemImage: "text.badge.plus") {
					browser.addToReadingList(tabID: tab.id)
				}
				.disabled(!browser.canAddToReadingList(tabID: tab.id))
				.accessibilityIdentifier("favourite-add-reading-list-\(tab.id.uuidString)")
				Button("Save Page Offline", systemImage: "arrow.down.circle") {
					browser.saveReadingListSnapshot(tabID: tab.id)
				}
				.disabled(!browser.canSaveReadingListSnapshot(tabID: tab.id))
				.accessibilityIdentifier("favourite-save-offline-\(tab.id.uuidString)")
			}
		}
	}
}

private struct FavouriteIconView: View {
	let tab: BrowserTab

	var body: some View {
		Group {
			if let favicon = tab.session.favicons.image(for: tab.currentURL, in: tab.controller?.webViewIfLoaded) {
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
}

/// Icons refresh via FavouriteIconView's own FaviconStore subscription;
/// skipping unchanged tiles here never blocks new icons.
extension BrowserFavouriteTile: Equatable {
	static func == (lhs: BrowserFavouriteTile, rhs: BrowserFavouriteTile) -> Bool {
		lhs.tab === rhs.tab
			&& lhs.browser === rhs.browser
			&& (lhs.browser.selectedTabID == lhs.tab.id) == (rhs.browser.selectedTabID == rhs.tab.id)
			&& lhs.tab.title == rhs.tab.title
			&& (lhs.onSelectTab == nil) == (rhs.onSelectTab == nil)
			&& lhs.navigationNamespace == rhs.navigationNamespace
	}
}
