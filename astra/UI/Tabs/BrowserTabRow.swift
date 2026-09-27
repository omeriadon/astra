#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif
import Defaults
import SwiftUI

struct BrowserTabRow: View {
	let tab: BrowserTab
	let browser: Browser
	let isSelected: Bool
	private var theme: BrowserTheme {
		browser.theme
	}

	@State private var isRenaming = false
	@State private var isHovered = false
	@State private var renameText = ""
	@FocusState private var isTitleFocused: Bool
	#if os(macOS)
		@State private var tabDrag = BrowserTabDragCoordinator.shared
	#endif

	private var tabIndex: Int? {
		browser.normalTabs.firstIndex(where: { $0.id == tab.id })
	}

	private var isPinned: Bool {
		browser.selectedSpace.pinnedTabIDs.contains(tab.id)
	}

	private var canCloseAbove: Bool {
		(tabIndex ?? 0) > 0
	}

	private var canCloseBelow: Bool {
		guard let tabIndex else { return false }
		return tabIndex < browser.normalTabs.count - 1
	}

	@State private var hovered = false

	private var closeButton: some View {
		Button {
			browser.closeTab(tab.id)
		} label: {
			Image(systemName: "xmark")
				.frame(width: 22, height: 22)
				.background {
					if hovered {
						Color.primary
							.colorInvert()
							.opacity(0.3)
							.clipShape(RoundedRectangle(cornerRadius: 9))
					}
				}
				.contentShape(RoundedRectangle(cornerRadius: 9))
				.onHover {
					hovered = $0
				}
				.frame(width: 13, height: 16)
		}
		.buttonStyle(.plain)
		.accessibilityLabel(isPinned ? "Hibernate Tab" : "Close Tab")
		.accessibilityIdentifier("close-tab-\(tab.id.uuidString)")
	}

	var body: some View {
		HStack(spacing: 6) {
			Button {
				browser.selectTab(tab.id)
			} label: {
				Label {
					Text("Select Tab")
				} icon: {
					if let page = tab.internalPage {
						Image(systemName: page.symbol)
					} else if let favicon = FaviconStore.shared.image(
						for: tab.currentURL,
						in: tab.controller?.webViewIfLoaded
					) {
						favicon
							.resizable()
							.scaledToFit()
					} else {
						Image(systemName: "globe")
					}
				}
				.labelStyle(.iconOnly)
				.frame(width: 16, height: 16)
			}
			.buttonStyle(.plain)
			.accessibilityIdentifier("select-tab-\(tab.id.uuidString)")

			if isRenaming {
				TextField("Tab Name", text: $renameText)
					.textFieldStyle(.plain)
					.focused($isTitleFocused)
					.onSubmit(commitRenaming)
					.onKeyPress(.escape) {
						cancelRenaming()
						return .handled
					}
					.onChange(of: isTitleFocused) { _, isFocused in
						if !isFocused, isRenaming {
							commitRenaming()
						}
					}
					.accessibilityIdentifier("tab-name-\(tab.id.uuidString)")
			} else {
				Text(verbatim: tab.title)
					.lineLimit(1)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
					.contentShape(Rectangle())
					.onTapGesture {
						browser.selectTab(tab.id)
					}
					.simultaneousGesture(
						TapGesture(count: 2)
							.onEnded { _ in beginRenaming() }
					)
					.accessibilityLabel(Text(verbatim: tab.title))
					.accessibilityAddTraits(.isButton)
					.accessibilityAction(.default) {
						browser.selectTab(tab.id)
					}
					.accessibilityActions {
						if tab.internalPage == nil {
							Button("Rename", systemImage: "pencil") { beginRenaming() }
						}
					}
					.accessibilityIdentifier("tab-title-\(tab.id.uuidString)")
			}

			if isSelected {
				closeButton
					.keyboardShortcut("W", modifiers: .command)
			} else {
				closeButton
					.opacity(isHovered ? 1 : 0)
					.allowsHitTesting(isHovered)
					.accessibilityHidden(!isHovered)
			}
		}
		.padding(.horizontal, 8)
		.frame(height: 28)
		.foregroundStyle(theme.foregroundColor)
		.background {
			if isSelected {
				Color.clear
					.glassEffect(
						.clear,
						in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
					)
			} else if isHovered {
				Color.clear
					.glassEffect(
						.regular,
						in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
					)
			}
		}
		#if os(macOS)
		.background {
			BrowserDropZone(
				browser: browser,
				area: browser.selectedSpace.pinnedTabIDs.contains(tab.id) ? .pinned : .normal,
				spaceID: browser.workspace.selectedSpaceID,
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
		.onHover { isHovered = $0 }
		.contextMenu {
			if tab.internalPage == nil {
				Button("Revert Tab Name", systemImage: "arrow.uturn.backward", action: tab.revertTitle)
					.disabled(!tab.hasCustomTitle)

				Button("Duplicate Tab", systemImage: "plus.square.on.square") {
					browser.duplicateTab(tab.id)
				}

				Button("Hibernate Tab", systemImage: "moon.zzz") {
					browser.hibernateTab(tab.id)
				}
				.disabled(tab.isHibernated)
				.accessibilityIdentifier("hibernate-tab-\(tab.id.uuidString)")

				if isPinned {
					Button("Unpin Tab", systemImage: "pin.slash") {
						browser.moveTab(tab.id, to: .normal)
					}
				} else {
					Button("Pin Tab", systemImage: "pin") {
						browser.moveTab(tab.id, to: .pinned)
					}
				}
				Button("Add to Favourites", systemImage: "star") {
					browser.moveTab(tab.id, to: .favourite)
				}

				Divider()

				Button("Copy URL", systemImage: "doc.on.doc", action: copyURL)
					.disabled(tab.currentURL == nil)

				Divider()
			}

			Button("Close Tabs Above", systemImage: "arrow.up.to.line") {
				browser.closeTabsAbove(tab.id)
			}
			.disabled(!canCloseAbove)

			Button("Close Tabs Below", systemImage: "arrow.down.to.line") {
				browser.closeTabsBelow(tab.id)
			}
			.disabled(!canCloseBelow)

			Button("Close Other Tabs", systemImage: "xmark.circle") {
				browser.closeOtherTabs(tab.id)
			}
			.disabled(browser.normalTabs.count < 2)

			Button(role: isPinned ? nil : .destructive) {
				browser.closeTab(tab.id)
			} label: {
				Label(isPinned ? "Hibernate Tab" : "Close Tab", systemImage: isPinned ? "moon.zzz" : "xmark")
			}
		}
		.onChange(of: isSelected) { _, selected in
			if !selected, isRenaming {
				commitRenaming()
			}
		}
	}

	private func beginRenaming() {
		guard tab.internalPage == nil else { return }
		browser.selectTab(tab.id)
		renameText = tab.title
		isRenaming = true
		isTitleFocused = true
	}

	private func commitRenaming() {
		tab.rename(to: renameText)
		isRenaming = false
		isTitleFocused = false
	}

	private func cancelRenaming() {
		isRenaming = false
		isTitleFocused = false
	}

	private func copyURL() {
		guard let url = tab.currentURL else { return }
		#if os(macOS)
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(url.absoluteString, forType: .string)
		#elseif os(iOS)
			UIPasteboard.general.url = url
		#endif
	}
}
