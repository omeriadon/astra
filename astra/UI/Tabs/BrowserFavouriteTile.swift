import Defaults
import SwiftUI

struct BrowserFavouriteTile: View {
	let tab: BrowserTab
	let browser: Browser
	var isSelected = false
	var onSelectTab: ((UUID) -> Void)?
	var navigationNamespace: Namespace.ID?
	@Default(.developerModeEnabled) private var developerModeEnabled
	@Namespace private var tileTransitions
	#if os(macOS)
		@State private var tabDrag = BrowserTabDragCoordinator.shared
		@State private var hoverFrame = CGRect.zero
		@State private var hoverPreviewStarted = false
		@State private var isHovered = false
		@State private var isMouseDown = false
	#endif

	var body: some View {
		Button {
			browser.selectTab(tab.id)
			onSelectTab?(tab.id)
		} label: {
			FavouriteIconView(tab: tab)
		}
		.buttonStyle(.plain)
		#if os(macOS)
			.simultaneousGesture(
				DragGesture(minimumDistance: 0)
					.onChanged { _ in
						guard onSelectTab == nil, !isMouseDown else { return }
						isMouseDown = true
						browser.selectTab(tab.id)
					}
					.onEnded { _ in
						isMouseDown = false
					}
			)
		#endif
			.matchedTransitionSource(id: tab.id.uuidString, in: navigationNamespace ?? tileTransitions)
			.background {
				RoundedRectangle(cornerRadius: 10)
					.fill(isSelected ? .white.opacity(0.3) : .white.opacity(0.12))
			}
			.overlay {
				if isSelected, tab.internalPage == nil, developerModeEnabled || tab.isDeveloperMode {
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
				if tabDrag.activeTabID != nil {
					BrowserDropZone(
						browser: browser,
						area: .favourite,
						spaceID: nil,
						beforeTabID: tab.id
					)
				}
			}
			.highPriorityGesture(
				DragGesture(minimumDistance: 8)
					.onChanged { _ in
						if tabDrag.activeTabID != tab.id {
							tabDrag.begin(tab.id, from: browser)
						}
						tabDrag.update()
					}
					.onEnded { _ in
						tabDrag.drop()
					}
			)
		#endif
		#if os(macOS)
			.modifier(
			FavouriteHoverPreviewModifier(
				tabID: tab.id,
				windowID: browser.windowID,
				previewEnabled: onSelectTab == nil,
				isHovered: $isHovered,
				hoverFrame: $hoverFrame,
				hoverPreviewStarted: $hoverPreviewStarted
			)
		)
		#endif
		.accessibilityLabel(tab.title)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
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

#if os(macOS)
	private struct FavouriteHoverPreviewModifier: ViewModifier {
		let tabID: UUID
		let windowID: UUID
		let previewEnabled: Bool
		@Binding var isHovered: Bool
		@Binding var hoverFrame: CGRect
		@Binding var hoverPreviewStarted: Bool

		func body(content: Content) -> some View {
			content
				.onHover { hovering in
					guard previewEnabled else { return }
					isHovered = hovering
					if hovering {
						if hoverPreviewStarted {
							BrowserTabHoverPreviewCoordinator.shared.updateFrame(
								for: tabID,
								windowID: windowID,
								frame: hoverFrame
							)
						} else if hoverFrame != .zero {
							hoverPreviewStarted = true
							BrowserTabHoverPreviewCoordinator.shared.hoverBegan(
								tabID: tabID,
								windowID: windowID,
								sourceFrame: hoverFrame
							)
						}
					} else {
						if hoverPreviewStarted {
							BrowserTabHoverPreviewCoordinator.shared.hoverEnded(tabID: tabID, windowID: windowID)
						}
						hoverPreviewStarted = false
					}
				}
				.onGeometryChange(for: CGRect.self) { proxy in
					proxy.frame(in: .global)
				} action: { frame in
					hoverFrame = frame
					guard previewEnabled, isHovered else { return }
					if hoverPreviewStarted {
						BrowserTabHoverPreviewCoordinator.shared.updateFrame(for: tabID, windowID: windowID, frame: frame)
					} else {
						hoverPreviewStarted = true
						BrowserTabHoverPreviewCoordinator.shared.hoverBegan(tabID: tabID, windowID: windowID, sourceFrame: frame)
					}
				}
				.onChange(of: tabID) { oldID, _ in
					if hoverPreviewStarted {
						BrowserTabHoverPreviewCoordinator.shared.hoverEnded(tabID: oldID, windowID: windowID)
					}
					hoverPreviewStarted = false
				}
				.onDisappear {
					if hoverPreviewStarted {
						BrowserTabHoverPreviewCoordinator.shared.hoverEnded(tabID: tabID, windowID: windowID)
					}
					hoverPreviewStarted = false
				}
		}
	}
#endif

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
			&& lhs.isSelected == rhs.isSelected
			&& lhs.tab.title == rhs.tab.title
			&& (lhs.onSelectTab == nil) == (rhs.onSelectTab == nil)
			&& lhs.navigationNamespace == rhs.navigationNamespace
	}
}
