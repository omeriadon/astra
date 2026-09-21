#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif
import SwiftUI

struct BrowserTabRow: View {
	let tab: BrowserTab
	let browser: Browser
	let isSelected: Bool
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
			Button("Select Tab", systemImage: "globe") {
				browser.selectTab(tab.id)
			}
			.labelStyle(.iconOnly)
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
					.accessibilityAction(named: "Rename") {
						beginRenaming()
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
		.background {
			Rectangle()
				.fill(.clear)
				.glassEffect(
					isSelected ? .clear.interactive() : isHovered ? .regular : .identity,
					in: RoundedRectangle(cornerRadius: 13)
				)
				.animation(.smooth(duration: 0.1), value: isHovered)
		}
		.onHover { isHovered = $0 }
		.contextMenu {
			Button("Revert Tab Name", systemImage: "arrow.uturn.backward", action: tab.revertTitle)
				.disabled(!tab.hasCustomTitle)

			Button("Duplicate Tab", systemImage: "plus.square.on.square") {
				browser.duplicateTab(tab.id)
			}

			Button("Pin Tab", systemImage: "pin") {}
				.disabled(true)

			Divider()

			Button("Reload", systemImage: "arrow.clockwise", action: tab.controller.reload)

			Button("Copy URL", systemImage: "doc.on.doc", action: copyURL)
				.disabled(tab.controller.url == nil)

			Divider()

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
		guard let url = tab.controller.url else { return }
		#if os(macOS)
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(url.absoluteString, forType: .string)
		#elseif os(iOS)
			UIPasteboard.general.url = url
		#endif
	}
}
