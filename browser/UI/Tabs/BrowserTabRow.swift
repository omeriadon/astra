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
	@Default(.browserTheme) private var theme
	@State private var isRenaming = false
	@State private var isHovered = false
	@State private var renameText = ""
	@FocusState private var isTitleFocused: Bool

	private var tabIndex: Int? {
		browser.tabs.firstIndex(where: { $0.id == tab.id })
	}

	private var canCloseAbove: Bool {
		(tabIndex ?? 0) > 0
	}

	private var canCloseBelow: Bool {
		guard let tabIndex else { return false }
		return tabIndex < browser.tabs.count - 1
	}

	private var closeButton: some View {
		Button("Close Tab", systemImage: "xmark") {
			browser.closeTab(tab.id)
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.plain)
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
						in: tab.controller?.webView
					) {
						favicon
							.resizable()
							.scaledToFit()
							.saturation(tab.isHibernated ? 0 : 1)
							.scaleEffect(tab.isHibernated ? 0.8 : 1)
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
					.animation(.smooth(duration: 0.1), value: isHovered)
			}
		}
		.padding(.horizontal, 8)
		.frame(height: 28)
		.foregroundStyle(theme.foregroundColor)
		.background {
			ZStack {
				if isSelected {
					RoundedRectangle(cornerRadius: attachedBrowserCornerRadius)
						.glassEffect(.regular.tint(theme.tabColor).interactive(), in: RoundedRectangle(cornerRadius: attachedBrowserCornerRadius))
						.glassEffectTransition(.materialize)
				} else if isHovered {
					RoundedRectangle(cornerRadius: attachedBrowserCornerRadius)
						.glassEffect(.regular, in: RoundedRectangle(cornerRadius: attachedBrowserCornerRadius))
						.glassEffectTransition(.materialize)
				}
			}
			.animation(.smooth(duration: 0.02), value: isSelected)
		}
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

				Button("Pin Tab", systemImage: "pin") {}
					.disabled(true)

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
			.disabled(browser.tabs.count < 2)

			Button(role: .destructive) {
				browser.closeTab(tab.id)
			} label: {
				Label("Close Tab", systemImage: "xmark")
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
