import Defaults
import SwiftUI
#if os(macOS)
	import AppKit
#endif

struct BrowserFavouriteTile: View {
	let tab: BrowserTab
	let browser: Browser
	var isSelected = false
	var splitSide: Browser.SplitSide?
	var onSelectTab: ((UUID) -> Void)?
	var navigationNamespace: Namespace.ID?
	@Default(.developerModeEnabled) private var developerModeEnabled
	@Namespace private var tileTransitions
	#if os(macOS)
		@State private var hoverFrame = CGRect.zero
		@State private var hoverPreviewStarted = false
		@State private var isHovered = false
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
			.onDrag {
				let data = tab.id.uuidString.data(using: .utf8) ?? Data()
				let provider = NSItemProvider()
				provider.registerDataRepresentation(forTypeIdentifier: "com.omeriadon.astra.tab", visibility: .ownProcess) { completion in
					completion(data, nil)
					return nil
				}
				return provider
			}
		#endif
			.matchedTransitionSource(id: tab.id.uuidString, in: navigationNamespace ?? tileTransitions)
			.background {
				if isSelected {
					RoundedRectangle(cornerRadius: 10)
						.fill(.regularMaterial)
				} else {
					RoundedRectangle(cornerRadius: 10)
						.fill(.white.opacity(0.12))
				}
			}
			.overlay(alignment: .bottomTrailing) {
				if let side = splitSide {
					Image(systemName: side == .left ? "rectangle.lefthalf.filled" : "rectangle.righthalf.filled")
						.font(.system(size: 10))
						.padding(3)
						.background(.regularMaterial, in: Capsule())
						.allowsHitTesting(false)
				}
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
				if tab.canAppearInEaselSplit, !browser.isPrivate, !browser.isMini {
					Menu("Split View", systemImage: "rectangle.split.2x1") {
						if let selected = browser.selectedTab, selected.id != tab.id, selected.canAppearInEaselSplit {
							Button("Open to Left of Current Tab", systemImage: "rectangle.lefthalf.filled") {
								browser.openSplit(tab.id, beside: selected.id, onLeft: true)
							}
							Button("Open to Right of Current Tab", systemImage: "rectangle.righthalf.filled") {
								browser.openSplit(tab.id, beside: selected.id, onLeft: false)
							}
							Divider()
						}
						ForEach(browser.visibleTabs.filter { $0.id != tab.id && $0.canAppearInEaselSplit }) { other in
							Button("Place Left of \(other.title)", systemImage: "rectangle.lefthalf.filled") {
								browser.openSplit(tab.id, beside: other.id, onLeft: true)
							}
							Button("Place Right of \(other.title)", systemImage: "rectangle.righthalf.filled") {
								browser.openSplit(tab.id, beside: other.id, onLeft: false)
							}
						}
					}
					if splitSide != nil {
						Button("Close Split View", systemImage: "rectangle.split.2x1.slash") {
							browser.closeEaselSplit()
						}
					}
				}
				Button("Move to Pinned Tabs", systemImage: "pin") {
					browser.moveTab(tab.id, to: .pinned)
				}
				if tab.internalPage != .easel {
					Button("Move to Normal Tabs", systemImage: "rectangle") {
						browser.moveTab(tab.id, to: .normal)
					}
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
						hoverFrame = .zero
					}
				}
				.background {
					if previewEnabled, isHovered {
						GeometryReader { proxy in
							Color.clear
								.onAppear { recordHoverFrame(proxy.frame(in: .global)) }
								.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
									recordHoverFrame(frame)
								}
						}
						.allowsHitTesting(false)
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

		private func recordHoverFrame(_ frame: CGRect) {
			guard previewEnabled, isHovered else { return }
			guard frame != hoverFrame || !hoverPreviewStarted else { return }
			hoverFrame = frame
			if hoverPreviewStarted {
				BrowserTabHoverPreviewCoordinator.shared.updateFrame(for: tabID, windowID: windowID, frame: frame)
			} else {
				hoverPreviewStarted = true
				BrowserTabHoverPreviewCoordinator.shared.hoverBegan(tabID: tabID, windowID: windowID, sourceFrame: frame)
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
			&& lhs.splitSide == rhs.splitSide
			&& lhs.tab.title == rhs.tab.title
			&& (lhs.onSelectTab == nil) == (rhs.onSelectTab == nil)
			&& lhs.navigationNamespace == rhs.navigationNamespace
	}
}
