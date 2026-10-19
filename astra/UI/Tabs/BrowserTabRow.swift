#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif
import Defaults
import Foundation
import Observation
import SwiftUI
#if os(macOS)
	import UniformTypeIdentifiers
#endif

struct BrowserTabRow: View {
	let tab: BrowserTab
	let browser: Browser
	let isSelected: Bool
	/// Precomputed by the parent sidebar (avoids O(n²) normalTabs scans per row).
	var tabIndex: Int?
	var normalCount: Int?
	var pinned: Bool?
	var rowSpaceID: UUID?
	var rowTheme: BrowserTheme?
	var splitSide: Browser.SplitSide?
	var compactSplitStyle = false
	var isOpenElsewhere: Bool?
	var onSelectTab: ((UUID) -> Void)?
	var navigationNamespace: Namespace.ID?
	var sidebarSelection: BrowserSidebarTabSelection?
	var selectionOrder: [UUID] = []
	@Namespace private var rowTransitions
	private var theme: BrowserTheme {
		rowTheme ?? browser.theme
	}

	@State private var isRenaming = false
	@State private var isHovered = false
	@State private var showsMonitorDetails = false
	#if os(macOS)
		@State private var hoverFrame = CGRect.zero
		@State private var hoverPreviewStarted = false
		@State private var splitDropSide: Browser.SplitSide?
		@State private var splitDropWidth: CGFloat = 1
	#endif
	@State private var renameText = ""
	@Default(.developerModeEnabled) private var developerModeEnabled
	@FocusState private var isTitleFocused: Bool
	private var isMultiSelected: Bool {
		sidebarSelection?.contains(tab.id, area: isPinned ? .pinned : .normal, spaceID: rowSpaceID ?? browser.workspace.selectedSpaceID) == true
	}

	private func activateTab() {
		#if os(macOS)
			if let sidebarSelection, onSelectTab == nil {
				let activate = sidebarSelection.click(tab.id, area: isPinned ? .pinned : .normal,
				                                      spaceID: rowSpaceID ?? browser.workspace.selectedSpaceID,
				                                      orderedIDs: selectionOrder, currentID: browser.selectedTabID,
				                                      modifiers: NSEvent.modifierFlags)
				guard activate else { return }
			}
		#endif
		browser.selectTab(tab.id)
		onSelectTab?(tab.id)
	}

	private var resolvedTabIndex: Int? {
		tabIndex ?? browser.normalTabs.firstIndex(where: { $0.id == tab.id })
	}

	private var resolvedNormalCount: Int {
		normalCount ?? browser.normalTabs.count
	}

	private var isPinned: Bool {
		pinned ?? browser.selectedSpace.pinnedTabIDs.contains(tab.id)
	}

	private var canCloseAbove: Bool {
		(resolvedTabIndex ?? 0) > 0
	}

	private var canCloseBelow: Bool {
		guard let resolvedTabIndex else { return false }
		return resolvedTabIndex < resolvedNormalCount - 1
	}

	var body: some View {
		let isOpenElsewhere = isOpenElsewhere ?? BrowserWindowRegistry.shared.isOpenInAnotherWindow(tab.id, than: browser)
		return HStack(spacing: 6) {
			TabIconView(tab: tab, browser: browser, theme: theme, onSelectTab: onSelectTab, onActivate: activateTab)
			if let match = tab.monitorMatch {
				Button("Monitored condition met", systemImage: "bell.badge.fill") { browser.selectTab(tab.id) }
					.labelStyle(.iconOnly)
					.buttonStyle(.glassProminent)
					.tint(.yellow)
					.onHover { showsMonitorDetails = $0 }
					.accessibilityIdentifier("monitor-match-\(match.id.uuidString)")
					.popover(isPresented: $showsMonitorDetails) {
						VStack(alignment: .leading, spacing: 8) {
							Label("Condition fulfilled", systemImage: "bell.badge.fill").font(.headline)
							Text(match.criterion).font(.caption).foregroundStyle(.secondary)
							Text(match.message).textSelection(.enabled)
						}
						.padding(16)
						.frame(width: 300)
					}
			}

			if let side = splitSide, !compactSplitStyle {
				Image(systemName: side == .left ? "rectangle.lefthalf.filled" : "rectangle.righthalf.filled")
					.font(.system(size: 11))
					.foregroundStyle(theme.foregroundColor.opacity(0.75))
					.help(side == .left ? "Left split pane" : "Right split pane")
					.accessibilityIdentifier("split-tab-\(tab.id.uuidString)")
			}
			TabTitleView(
				tab: tab,
				browser: browser,
				isRenaming: isRenaming,
				isHovered: isHovered,
				showsCloseButton: isHovered,
				closeFadeWidth: onSelectTab != nil ? 64 : (isSelected || isHovered ? 36 : 8),
				renameText: $renameText,
				isTitleFocused: $isTitleFocused,
				onBeginRenaming: beginRenaming,
				onCommitRenaming: commitRenaming,
				onCancelRenaming: cancelRenaming,
				onSelectTab: onSelectTab,
				onActivate: activateTab,
				titleColor: Color.primary.mix(with: theme.tabColor, by: 0.15)
			)
			.foregroundStyle(Color.primary.mix(with: theme.tabColor, by: 0.15))
			.overlay(alignment: .trailing) {
				if isHovered {
					#if os(macOS)
						TabCloseButton(tab: tab, browser: browser, isPinned: isPinned, isCompact: onSelectTab != nil, color: theme.foregroundColor)
							.keyboardShortcut(BrowserShortcutRegistry.shared.menuKeyboardShortcut("Close Tab", section: "File"))
					#else
						TabCloseButton(tab: tab, browser: browser, isPinned: isPinned, isCompact: onSelectTab != nil, color: theme.foregroundColor)
							.keyboardShortcut("W", modifiers: .command)
					#endif
				}
			}
		}
		.opacity(isOpenElsewhere ? 0.35 : 1)
		.allowsHitTesting(!isOpenElsewhere)
		.padding(.horizontal, 8)
		.frame(maxWidth: .infinity, alignment: .leading)
		.frame(height: 30)
		.matchedTransitionSource(id: tab.id.uuidString, in: navigationNamespace ?? rowTransitions)
		.foregroundStyle(theme.foregroundColor)
		.background {
			if !compactSplitStyle, isSelected || splitSide != nil {
				Color.clear
					.glassEffect(
						.clear,
						in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabCornerRadius)
					)
			} else if !compactSplitStyle, isMultiSelected {
				ZStack {
					Color.clear
						.glassEffect(
							.regular,
							in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabCornerRadius)
						)
					if isSelected {
						Color.white.opacity(0.2)
					}
				}
			} else if !compactSplitStyle, isHovered {
				RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabCornerRadius)
					.fill(.primary.opacity(0.2))
			}
		}
		.overlay {
			if isSelected, tab.internalPage == nil, developerModeEnabled || tab.isDeveloperMode {
				RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
					.strokeBorder(Color(red: 0.55, green: 0.4, blue: 0), lineWidth: 2)
					.overlay {
						RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar)
							.strokeBorder(.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
					}
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			}
		}
		.onHover { hovering in
			isHovered = hovering
			#if os(macOS)
				guard onSelectTab == nil else { return }
				if hovering, NSEvent.pressedMouseButtons == 0 {
					// Hover-only geometry observation below supplies the initial frame;
					// subsequent movements keep the preview anchored during scrolling.
					if hoverPreviewStarted {
						BrowserTabHoverPreviewCoordinator.shared.updateFrame(
							for: tab.id,
							windowID: browser.windowID,
							frame: hoverFrame
						)
					} else if hoverFrame != .zero {
						hoverPreviewStarted = true
						BrowserTabHoverPreviewCoordinator.shared.hoverBegan(
							tabID: tab.id,
							windowID: browser.windowID,
							sourceFrame: hoverFrame
						)
					}
				} else {
					if hoverPreviewStarted {
						BrowserTabHoverPreviewCoordinator.shared.hoverEnded(
							tabID: tab.id,
							windowID: browser.windowID
						)
					}
					hoverPreviewStarted = false
					hoverFrame = .zero
				}
			#endif
		}
		#if os(macOS)
		.background {
			// Do not install a geometry observer for every non-hovered tab.
			if isHovered, onSelectTab == nil {
				BrowserWindowFrameReader { updateHoveredFrame($0) }
					.allowsHitTesting(false)
			}
		}
		.onChange(of: tab.id) { oldID, _ in
			if hoverPreviewStarted {
				BrowserTabHoverPreviewCoordinator.shared.hoverEnded(
					tabID: oldID,
					windowID: browser.windowID
				)
			}
			hoverPreviewStarted = false
		}
		.onDisappear {
			if hoverPreviewStarted {
				BrowserTabHoverPreviewCoordinator.shared.hoverEnded(
					tabID: tab.id,
					windowID: browser.windowID
				)
			}
			hoverPreviewStarted = false
		}
		#endif
		#if os(macOS)
		// Drag the whole tab, not merely its title or icon. Tab and page drop
		// zones consume the same in-process tab identity.
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { splitDropWidth = $0 }
		.onDrag {
			BrowserTabHoverPreviewCoordinator.shared.dismiss(for: browser.windowID)
			let data = tab.id.uuidString.data(using: .utf8) ?? Data()
			let provider = NSItemProvider()
			provider.registerDataRepresentation(forTypeIdentifier: "com.omeriadon.astra.tab", visibility: .ownProcess) { completion in
				completion(data, nil)
				return nil
			}
			return provider
		} preview: {
			HStack(spacing: 8) {
				Image(systemName: tab.internalPage?.symbol ?? "globe")
				Text(verbatim: tab.title).lineLimit(1)
				Spacer(minLength: 0)
			}
			.padding(.horizontal, 10)
			.frame(width: max(splitDropWidth, 140), height: 28)
			.glassEffect(.regular, in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar))
		}
		.onDrop(of: [UTType(exportedAs: "com.omeriadon.astra.tab", conformingTo: .data)],
		        delegate: BrowserTabRowSplitDropDelegate(
		        	browser: browser, anchorID: tab.id, width: splitDropWidth, side: $splitDropSide
		        ))
		.overlay {
			if let splitDropSide {
				HStack(spacing: 0) {
					splitDropSide == .left ? Color.accentColor.opacity(0.19) : Color.clear
					(splitDropSide == .right ? Color.accentColor.opacity(0.19) : Color.clear)
				}
				.clipShape(RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar))
				.allowsHitTesting(false)
			}
		}
		#endif
		.contextMenu {
			if let sidebarSelection, isMultiSelected, sidebarSelection.tabIDs.count > 1 {
				SidebarSelectedTabsContextMenu(
					browser: browser, selection: sidebarSelection,
					ids: sidebarSelection.orderedIDs(in: selectionOrder, area: isPinned ? .pinned : .normal,
					                                 spaceID: rowSpaceID ?? browser.workspace.selectedSpaceID),
					spaceID: rowSpaceID ?? browser.workspace.selectedSpaceID,
					isPinned: isPinned
				)
			} else {
				TabRowContextMenu(
					tab: tab,
					browser: browser,
					isPinned: isPinned,
					canCloseAbove: canCloseAbove,
					canCloseBelow: canCloseBelow,
					normalCount: resolvedNormalCount,
					spaceID: rowSpaceID,
					onCopyURL: copyURL,
					onBeginRenaming: beginRenaming,
					onSelectTab: onSelectTab
				)
			}
		}
		.onChange(of: isSelected) { _, selected in
			if !selected, isRenaming {
				commitRenaming()
			}
		}
	}

	#if os(macOS)
		private func updateHoveredFrame(_ frame: CGRect) {
			guard isHovered && onSelectTab == nil && NSEvent.pressedMouseButtons == 0, frame != hoverFrame || !hoverPreviewStarted else { return }
			hoverFrame = frame
			if hoverPreviewStarted {
				BrowserTabHoverPreviewCoordinator.shared.updateFrame(
					for: tab.id, windowID: browser.windowID, frame: frame
				)
			} else {
				hoverPreviewStarted = true
				BrowserTabHoverPreviewCoordinator.shared.hoverBegan(
					tabID: tab.id, windowID: browser.windowID, sourceFrame: frame
				)
			}
		}
	#endif

	private func beginRenaming() {
		guard tab.internalPage == nil || tab.internalPage == .easel else { return }
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
		browser.copyURL(for: tab)
	}
}

/// Favicons arrive via browser.session.favicons.image inside TabIconView, which stays
/// independently subscribed: skipping unchanged rows here never blocks new icons.
extension BrowserTabRow: Equatable {
	static func == (lhs: BrowserTabRow, rhs: BrowserTabRow) -> Bool {
		lhs.tab === rhs.tab
			&& lhs.browser === rhs.browser
			&& lhs.theme == rhs.theme
			&& lhs.isSelected == rhs.isSelected
			&& lhs.tabIndex == rhs.tabIndex
			&& lhs.normalCount == rhs.normalCount
			&& lhs.pinned == rhs.pinned
			&& lhs.rowSpaceID == rhs.rowSpaceID
			&& lhs.rowTheme == rhs.rowTheme
			&& lhs.isOpenElsewhere == rhs.isOpenElsewhere
			&& lhs.splitSide == rhs.splitSide
			&& lhs.compactSplitStyle == rhs.compactSplitStyle
			&& (lhs.onSelectTab == nil) == (rhs.onSelectTab == nil)
			&& lhs.navigationNamespace == rhs.navigationNamespace
			&& lhs.sidebarSelection === rhs.sidebarSelection
			&& lhs.selectionOrder == rhs.selectionOrder
	}
}

// The row's outer SwiftUI modifiers still own glass, matched transitions,
// shared drag/drop, hover previews and context menus. The frequently updated
// icon, title/editor and close affordance are real platform controls, never
// per-row NSHostingView/UIHostingController instances.
private struct TabIconView: View {
	let tab: BrowserTab
	let browser: Browser
	let theme: BrowserTheme
	var onSelectTab: ((UUID) -> Void)?
	var onActivate: (() -> Void)?

	var body: some View {
		let symbol = tab.internalPage?.symbol
		let favicon = symbol == nil ? browser.session.favicons.nativeImage(for: tab.currentURL) : nil
		NativeTabIconControl(
			symbol: symbol,
			favicon: favicon,
			color: theme.foregroundColor,
			identifier: "select-tab-\(tab.id.uuidString)",
			onActivate: {
				if let onActivate { onActivate() }
				else {
					browser.selectTab(tab.id)
					onSelectTab?(tab.id)
				}
			}
		)
		.frame(width: onSelectTab == nil ? 16 : 22, height: onSelectTab == nil ? 16 : 22)
	}
}

private struct TabTitleView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let tab: BrowserTab
	let browser: Browser
	let isRenaming: Bool
	let isHovered: Bool
	let showsCloseButton: Bool
	let closeFadeWidth: CGFloat
	@Binding var renameText: String
	var isTitleFocused: FocusState<Bool>.Binding
	let onBeginRenaming: () -> Void
	let onCommitRenaming: () -> Void
	let onCancelRenaming: () -> Void
	var onSelectTab: ((UUID) -> Void)?
	var onActivate: (() -> Void)?
	var titleColor: Color = .primary

	var body: some View {
		NativeTabTitleControl(
			title: tab.title,
			color: titleColor,
			isRenaming: isRenaming,
			isHovered: isHovered,
			closeFadeWidth: closeFadeWidth,
			hoverClearWidth: onSelectTab == nil ? 20 : 44,
			renameText: $renameText,
			focusRequested: isTitleFocused.wrappedValue,
			reduceMotion: reduceMotion,
			tabID: tab.id,
			canRename: tab.internalPage == nil || tab.internalPage == .easel,
			onActivate: {
				if let onActivate { onActivate() }
				else {
					browser.selectTab(tab.id)
					onSelectTab?(tab.id)
				}
			},
			onBeginRenaming: onBeginRenaming,
			onCommitRenaming: onCommitRenaming,
			onCancelRenaming: onCancelRenaming
		)
		.frame(maxWidth: .infinity, minHeight: 22)
	}
}

private struct TabCloseButton: View {
	let tab: BrowserTab
	let browser: Browser
	let isPinned: Bool
	var isCompact = false
	var color: Color = .primary

	var body: some View {
		ZStack {
			NativeTabCloseControl(
				identifier: "close-tab-\(tab.id.uuidString)",
				accessibilityTitle: tab.internalPage == .easel ? "Close Easel" : isPinned ? "Hibernate Tab" : "Close Tab",
				color: color,
				onClose: { browser.closeTab(tab.id) }
			)
			.frame(width: isCompact ? 44 : 13, height: isCompact ? 44 : 16)

			// Native controls don't consume SwiftUI's keyboardShortcut modifier.
			// Keep the existing per-row shortcut on a zero-size SwiftUI action
			// so Cmd-W remains available while the close affordance is shown.
			#if os(macOS)
				Button("Close Tab") { browser.closeTab(tab.id) }
					.keyboardShortcut(BrowserShortcutRegistry.shared.menuKeyboardShortcut("Close Tab", section: "File"))
					.frame(width: 0, height: 0)
					.opacity(0.001)
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			#else
				Button("Close Tab") { browser.closeTab(tab.id) }
					.keyboardShortcut("W", modifiers: .command)
					.frame(width: 0, height: 0)
					.opacity(0.001)
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			#endif
		}
	}
}

#if os(macOS)
	// These adapters deliberately do not retain Browser or BrowserTab. Reused
	// AppKit views receive current values/actions on each SwiftUI update.
	private struct NativeTabIconControl: NSViewRepresentable {
		let symbol: String?
		let favicon: NSImage?
		let color: Color
		let identifier: String
		let onActivate: () -> Void

		func makeNSView(context _: Context) -> NativeTabIconButton { NativeTabIconButton(frame: .zero) }

		func updateNSView(_ view: NativeTabIconButton, context _: Context) {
			view.activation = onActivate
			view.setAccessibilityIdentifier(identifier)
			if let symbol {
				view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
				view.contentTintColor = NSColor(color)
			} else if let favicon {
				view.image = favicon
				view.contentTintColor = nil
			} else {
				view.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
				view.contentTintColor = NSColor(color)
			}
		}
	}

	@MainActor
	private final class NativeTabIconButton: NSButton {
		var activation: (() -> Void)?
		override init(frame: NSRect) {
			super.init(frame: .zero)
			isBordered = false
			imagePosition = .imageOnly
			imageScaling = .scaleProportionallyDown
			focusRingType = .none
			target = self
			action = #selector(activateTab)
			setAccessibilityLabel("Select Tab")
		}
		required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
		@objc private func activateTab() { activation?() }
	}

	private struct NativeTabTitleControl: NSViewRepresentable {
		let title: String
		let color: Color
		let isRenaming: Bool
		let isHovered: Bool
		let closeFadeWidth: CGFloat
		let hoverClearWidth: CGFloat
		@Binding var renameText: String
		let focusRequested: Bool
		let reduceMotion: Bool
		let tabID: UUID
		let canRename: Bool
		let onActivate: () -> Void
		let onBeginRenaming: () -> Void
		let onCommitRenaming: () -> Void
		let onCancelRenaming: () -> Void

		func makeNSView(context _: Context) -> NativeTabTitleView { NativeTabTitleView(frame: .zero) }

		func updateNSView(_ view: NativeTabTitleView, context _: Context) {
			view.activate = onActivate
			view.beginRename = onBeginRenaming
			view.commitRename = onCommitRenaming
			view.cancelRename = onCancelRenaming
			view.onEdit = { renameText = $0 }
			view.apply(
				title: title, textColor: NSColor(color),
				isRenaming: isRenaming, renameText: renameText,
				isHovered: isHovered, closeFadeWidth: closeFadeWidth,
				hoverClearWidth: hoverClearWidth, focused: focusRequested,
				reduceMotion: reduceMotion,
				tabID: tabID, canRename: canRename
			)
		}
	}

	@MainActor
	private final class NativeTabTitleView: NSView, NSTextFieldDelegate {
		private let titleLabel = NSTextField(labelWithString: "")
		private let editField = NSTextField()
		private let fade = CAGradientLayer()
		var activate: (() -> Void)?
		var beginRename: (() -> Void)?
		var commitRename: (() -> Void)?
		var cancelRename: (() -> Void)?
		var onEdit: ((String) -> Void)?
		private var isRenaming = false
		private var isHovered = false
		private var fadeWidth: CGFloat = 8
		private var clearWidth: CGFloat = 20
		private var focusRequested = false
		private var editingIdentity: UUID?
		private var finishing = false

		override init(frame: NSRect) {
			super.init(frame: frame)
			wantsLayer = true
			titleLabel.wantsLayer = true
			titleLabel.isSelectable = false
			titleLabel.isEditable = false
			titleLabel.isBordered = false
			titleLabel.drawsBackground = false
			titleLabel.lineBreakMode = .byClipping
			titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
			addSubview(titleLabel)
			editField.isBordered = false
			editField.drawsBackground = false
			editField.focusRingType = .none
			editField.font = titleLabel.font
			editField.delegate = self
			editField.isHidden = true
			addSubview(editField)
			fade.colors = [NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor, NSColor.clear.cgColor]
			fade.startPoint = CGPoint(x: 0, y: 0.5)
			fade.endPoint = CGPoint(x: 1, y: 0.5)
			setAccessibilityRole(.button)
		}
		required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
		override var isFlipped: Bool { true }
		override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 22) }

		func apply(
			title: String, textColor: NSColor, isRenaming: Bool, renameText: String,
			isHovered: Bool, closeFadeWidth: CGFloat, hoverClearWidth: CGFloat,
			focused: Bool, reduceMotion: Bool, tabID: UUID, canRename: Bool
		) {
			if titleLabel.stringValue != title {
				if !reduceMotion, !titleLabel.stringValue.isEmpty {
					let transition = CATransition()
					transition.type = .fade
					transition.duration = 0.2
					transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
					titleLabel.layer?.add(transition, forKey: "title")
				}
				titleLabel.stringValue = title
			}
			titleLabel.textColor = textColor
			editField.textColor = textColor
			self.isHovered = isHovered
			fadeWidth = closeFadeWidth
			clearWidth = hoverClearWidth
			focusRequested = focused
			if editingIdentity != tabID { editingIdentity = tabID; finishing = false }
			if self.isRenaming != isRenaming { finishing = false }
			self.isRenaming = isRenaming
			titleLabel.isHidden = isRenaming
			editField.isHidden = !isRenaming
			setAccessibilityIdentifier("tab-title-\(tabID.uuidString)")
			setAccessibilityLabel(title)
			if isRenaming {
				editField.setAccessibilityIdentifier("tab-name-\(tabID.uuidString)")
				if editField.stringValue != renameText && window?.firstResponder !== editField.currentEditor() {
					editField.stringValue = renameText
				}
				if focused, let window, window.firstResponder !== editField.currentEditor() {
					window.makeFirstResponder(editField)
					editField.selectText(nil)
				}
			}
			setAccessibilityHelp(canRename ? "Double-click to rename" : nil)
			needsLayout = true
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			if isRenaming && focusRequested {
				window?.makeFirstResponder(editField)
				editField.selectText(nil)
			}
		}
		override func hitTest(_ point: NSPoint) -> NSView? {
			isRenaming ? super.hitTest(point) : bounds.contains(convert(point, from: superview)) ? self : nil
		}
		override func mouseUp(with event: NSEvent) {
			if isRenaming { return }
			if event.clickCount >= 2 { beginRename?() }
			else { activate?() }
		}
		override func layout() {
			super.layout()
			let naturalWidth = titleLabel.intrinsicContentSize.width
			titleLabel.frame = CGRect(x: 0, y: 0, width: max(bounds.width, naturalWidth), height: bounds.height)
			editField.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - (isHovered ? fadeWidth : 0)), height: bounds.height)
			if isRenaming {
				layer?.mask = nil
			} else {
				let width = max(bounds.width, 1)
				let gradientWidth = isHovered ? max(0, fadeWidth + 28 - clearWidth) : fadeWidth
				let clear = isHovered ? clearWidth : 0
				let start = max(0, min(1, (width - gradientWidth - clear) / width))
				let end = max(start, min(1, (width - clear) / width))
				fade.frame = bounds
				fade.locations = [0, NSNumber(value: Double(start)), NSNumber(value: Double(end)), 1]
				layer?.mask = fade
			}
		}
		func controlTextDidChange(_ notification: Notification) { onEdit?(editField.stringValue) }
		func controlTextDidEndEditing(_ notification: Notification) {
			if isRenaming && !finishing { finishing = true; commitRename?() }
		}
		func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
			if selector == #selector(NSResponder.cancelOperation(_:)) {
				finishing = true
				cancelRename?()
				return true
			}
			if selector == #selector(NSResponder.insertNewline(_:)) {
				finishing = true
				commitRename?()
				return true
			}
			return false
		}
	}

	private struct NativeTabCloseControl: NSViewRepresentable {
		let identifier: String
		let accessibilityTitle: String
		let color: Color
		let onClose: () -> Void
		func makeNSView(context _: Context) -> NativeTabCloseButton { NativeTabCloseButton(frame: .zero) }
		func updateNSView(_ view: NativeTabCloseButton, context _: Context) {
			view.onClose = onClose
			view.setAccessibilityIdentifier(identifier)
			view.setAccessibilityLabel(accessibilityTitle)
			view.contentTintColor = NSColor(color)
		}
	}

	@MainActor
	private final class NativeTabCloseButton: NSButton {
		var onClose: (() -> Void)?
		private var tracking: NSTrackingArea?
		override init(frame: NSRect) {
			super.init(frame: .zero)
			isBordered = false
			image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
			imagePosition = .imageOnly
			imageScaling = .scaleProportionallyDown
			focusRingType = .none
			wantsLayer = true
			layer?.cornerRadius = 12
			target = self
			action = #selector(close)
		}
		required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
		@objc private func close() { onClose?() }
		override func updateTrackingAreas() {
			if let tracking { removeTrackingArea(tracking) }
			let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
			addTrackingArea(next)
			tracking = next
			super.updateTrackingAreas()
		}
		override func mouseEntered(with event: NSEvent) {
			layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.3).cgColor
		}
		override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
	}
#elseif os(iOS)
	private struct NativeTabIconControl: UIViewRepresentable {
		let symbol: String?
		let favicon: UIImage?
		let color: Color
		let identifier: String
		let onActivate: () -> Void
		func makeUIView(context _: Context) -> NativeTabIconButton { NativeTabIconButton(frame: .zero) }
		func updateUIView(_ view: NativeTabIconButton, context _: Context) {
			view.activation = onActivate
			view.accessibilityIdentifier = identifier
			view.accessibilityLabel = "Select Tab"
			view.tintColor = UIColor(color)
			let icon = symbol.flatMap { UIImage(systemName: $0) }
				?? favicon
				?? UIImage(systemName: "globe")
			view.setImage(icon, for: .normal)
			view.imageView?.contentMode = .scaleAspectFit
		}
	}

	@MainActor
	private final class NativeTabIconButton: UIButton {
		var activation: (() -> Void)?
		override init(frame: CGRect) {
			super.init(frame: .zero)
			addTarget(self, action: #selector(selectTab), for: .touchUpInside)
		}
		required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
		@objc private func selectTab() { activation?() }
	}

	private struct NativeTabTitleControl: UIViewRepresentable {
		let title: String
		let color: Color
		let isRenaming: Bool
		let isHovered: Bool
		let closeFadeWidth: CGFloat
		let hoverClearWidth: CGFloat
		@Binding var renameText: String
		let focusRequested: Bool
		let reduceMotion: Bool
		let tabID: UUID
		let canRename: Bool
		let onActivate: () -> Void
		let onBeginRenaming: () -> Void
		let onCommitRenaming: () -> Void
		let onCancelRenaming: () -> Void
		func makeUIView(context _: Context) -> NativeTabTitleView { NativeTabTitleView(frame: .zero) }
		func updateUIView(_ view: NativeTabTitleView, context _: Context) {
			view.activate = onActivate
			view.beginRename = onBeginRenaming
			view.commitRename = onCommitRenaming
			view.cancelRename = onCancelRenaming
			view.onEdit = { renameText = $0 }
			view.apply(
				title: title, color: UIColor(color), isRenaming: isRenaming,
				renameText: renameText, isHovered: isHovered,
				closeFadeWidth: closeFadeWidth, hoverClearWidth: hoverClearWidth,
				focused: focusRequested, reduceMotion: reduceMotion,
				tabID: tabID, canRename: canRename
			)
		}
	}

	@MainActor
	private final class NativeTabTitleView: UIView, UITextFieldDelegate {
		private let titleLabel = UILabel()
		private let editField = UITextField()
		private let fade = CAGradientLayer()
		var activate: (() -> Void)?
		var beginRename: (() -> Void)?
		var commitRename: (() -> Void)?
		var cancelRename: (() -> Void)?
		var onEdit: ((String) -> Void)?
		private var isRenaming = false
		private var isHovered = false
		private var fadeWidth: CGFloat = 8
		private var clearWidth: CGFloat = 44
		private var focusRequested = false

		override init(frame: CGRect) {
			super.init(frame: frame)
			titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
			titleLabel.lineBreakMode = .byClipping
			titleLabel.numberOfLines = 1
			titleLabel.isUserInteractionEnabled = false
			addSubview(titleLabel)
			editField.font = titleLabel.font
			editField.borderStyle = .none
			editField.returnKeyType = .done
			editField.delegate = self
			editField.addTarget(self, action: #selector(editChanged), for: .editingChanged)
			addSubview(editField)
			let single = UITapGestureRecognizer(target: self, action: #selector(select))
			addGestureRecognizer(single)
			let double = UITapGestureRecognizer(target: self, action: #selector(rename))
			double.numberOfTapsRequired = 2
			addGestureRecognizer(double)
			// Like the former simultaneous SwiftUI gestures, selecting is not
			// delayed while waiting to distinguish a double tap.
			fade.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor, UIColor.clear.cgColor]
			fade.startPoint = CGPoint(x: 0, y: 0.5)
			fade.endPoint = CGPoint(x: 1, y: 0.5)
			isAccessibilityElement = true
			accessibilityTraits = .button
		}
		required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
		@objc private func select() { if !isRenaming { activate?() } }
		@objc private func rename() { if !isRenaming { beginRename?() } }
		@objc private func editChanged() { onEdit?(editField.text ?? "") }

		func apply(
			title: String, color: UIColor, isRenaming: Bool, renameText: String,
			isHovered: Bool, closeFadeWidth: CGFloat, hoverClearWidth: CGFloat,
			focused: Bool, reduceMotion: Bool, tabID: UUID, canRename: Bool
		) {
			if titleLabel.text != title {
				if !reduceMotion && titleLabel.text != nil {
					let transition = CATransition()
					transition.type = .fade
					transition.duration = 0.2
					transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
					titleLabel.layer.add(transition, forKey: "title")
				}
				titleLabel.text = title
			}
			titleLabel.textColor = color
			editField.textColor = color
			self.isRenaming = isRenaming
			self.isHovered = isHovered
			fadeWidth = closeFadeWidth
			clearWidth = hoverClearWidth
			focusRequested = focused
			titleLabel.isHidden = isRenaming
			editField.isHidden = !isRenaming
			accessibilityIdentifier = "tab-title-\(tabID.uuidString)"
			accessibilityLabel = title
			accessibilityCustomActions = canRename
				? [UIAccessibilityCustomAction(name: "Rename", target: self, selector: #selector(accessibilityRename))]
				: nil
			editField.accessibilityIdentifier = "tab-name-\(tabID.uuidString)"
			if isRenaming {
				if !editField.isFirstResponder { editField.text = renameText }
				if focused && window != nil && !editField.isFirstResponder { editField.becomeFirstResponder() }
			}
			setNeedsLayout()
		}
		@objc private func accessibilityRename() -> Bool { beginRename?(); return true }
		override func didMoveToWindow() {
			super.didMoveToWindow()
			if isRenaming && focusRequested { editField.becomeFirstResponder() }
		}
		override func layoutSubviews() {
			super.layoutSubviews()
			titleLabel.frame = CGRect(x: 0, y: 0, width: max(bounds.width, titleLabel.intrinsicContentSize.width), height: bounds.height)
			editField.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - (isHovered ? fadeWidth : 0)), height: bounds.height)
			if isRenaming { layer.mask = nil }
			else {
				let width = max(bounds.width, 1)
				let gradientWidth = isHovered ? max(0, fadeWidth + 28 - clearWidth) : fadeWidth
				let clear = isHovered ? clearWidth : 0
				let start = max(0, min(1, (width - gradientWidth - clear) / width))
				let end = max(start, min(1, (width - clear) / width))
				fade.frame = bounds
				fade.locations = [0, NSNumber(value: Double(start)), NSNumber(value: Double(end)), 1]
				layer.mask = fade
			}
		}
		func textFieldShouldReturn(_ textField: UITextField) -> Bool { commitRename?(); return false }
		func textFieldDidEndEditing(_ textField: UITextField) { if isRenaming { commitRename?() } }
	}

	private struct NativeTabCloseControl: UIViewRepresentable {
		let identifier: String
		let accessibilityTitle: String
		let color: Color
		let onClose: () -> Void
		func makeUIView(context _: Context) -> NativeTabCloseButton { NativeTabCloseButton(frame: .zero) }
		func updateUIView(_ view: NativeTabCloseButton, context _: Context) {
			view.onClose = onClose
			view.accessibilityIdentifier = identifier
			view.accessibilityLabel = accessibilityTitle
			view.tintColor = UIColor(color)
		}
	}
	@MainActor
	private final class NativeTabCloseButton: UIButton {
		var onClose: (() -> Void)?
		override init(frame: CGRect) {
			super.init(frame: .zero)
			setImage(UIImage(systemName: "xmark"), for: .normal)
			imageView?.contentMode = .scaleAspectFit
			layer.cornerRadius = 12
			addTarget(self, action: #selector(closeTab), for: .touchUpInside)
			let hover = UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:)))
			addGestureRecognizer(hover)
		}
		required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
		@objc private func closeTab() { onClose?() }
		@objc private func hoverChanged(_ gesture: UIHoverGestureRecognizer) {
			backgroundColor = gesture.state == .began || gesture.state == .changed
				? UIColor.systemBackground.withAlphaComponent(0.3) : .clear
		}
	}
#endif

private struct TabRowContextMenu: View {
	let tab: BrowserTab
	let browser: Browser
	let isPinned: Bool
	let canCloseAbove: Bool
	let canCloseBelow: Bool
	let normalCount: Int
	var spaceID: UUID?
	let onCopyURL: () -> Void
	let onBeginRenaming: () -> Void
	var onSelectTab: ((UUID) -> Void)?

	var body: some View {
		if tab.canAppearInEaselSplit, !browser.isPrivate, !browser.isMini {
			if let selected = browser.selectedTab, selected.id != tab.id, selected.canAppearInEaselSplit {
				Button("Add to Current Tab on Left", systemImage: "rectangle.lefthalf.filled") {
					browser.openSplit(tab.id, beside: selected.id, onLeft: true)
				}
				Button("Add to Current Tab on Right", systemImage: "rectangle.righthalf.filled") {
					browser.openSplit(tab.id, beside: selected.id, onLeft: false)
				}
			}
			if browser.splitSide(for: tab.id) != nil {
				Button("Close Split View", systemImage: "rectangle.split.2x1.slash") {
					browser.closeEaselSplit()
				}
			}
			Divider()
		}
		if tab.internalPage == .easel {
			Button("Rename Easel", systemImage: "pencil", action: onBeginRenaming)
			Button("Revert Easel Name", systemImage: "arrow.uturn.backward", action: tab.revertTitle)
				.disabled(!tab.hasCustomTitle)
			Menu("Move to Space", systemImage: "rectangle.3.group") {
				ForEach(browser.workspace.spaces) { space in
					Button(space.name, systemImage: space.symbol) {
						browser.moveTab(tab.id, to: .pinned, in: space.id)
					}
				}
			}
			Button("Add to Favourites", systemImage: "star") {
				browser.moveTab(tab.id, to: .favourite)
			}
		}
		Button("New Folder with Tab", systemImage: "folder.badge.plus") {
			browser.createPinnedFolder(with: [tab.id], in: spaceID)
		}
		if tab.internalPage == nil {
			Button("Rename Tab", systemImage: "pencil", action: onBeginRenaming)
			Button("Revert Tab Name", systemImage: "arrow.uturn.backward", action: tab.revertTitle)
				.disabled(!tab.hasCustomTitle)

			Button("Duplicate Tab", systemImage: "plus.square.on.square") {
				if browser.duplicateTab(tab.id) != nil {
					onSelectTab?(tab.id)
				}
			}

			Button("Hibernate Tab", systemImage: "moon.zzz") {
				browser.hibernateTab(tab.id)
			}
			.disabled(tab.isHibernated || !tab.canHibernate)
			.accessibilityIdentifier("hibernate-tab-\(tab.id.uuidString)")

			if isPinned {
				Button("Unpin Tab", systemImage: "pin.slash") {
					browser.moveTab(tab.id, to: .normal)
				}
				if !browser.selectedSpace.pinnedFolders.isEmpty {
					Menu("Move to Folder", systemImage: "folder") {
						Button("No Folder", systemImage: "tray") {
							browser.movePinnedTab(tab.id, toFolder: nil)
						}
						ForEach(browser.selectedSpace.pinnedFolders) { folder in
							Button(folder.name, systemImage: "folder") {
								browser.movePinnedTab(tab.id, toFolder: folder.id)
							}
						}
					}
				}
			} else {
				Button("Pin Tab", systemImage: "pin") {
					browser.moveTab(tab.id, to: .pinned)
				}
			}
			Menu("Move to Space", systemImage: "rectangle.3.group") {
				ForEach(browser.workspace.spaces) { space in
					Button(space.name, systemImage: space.symbol) {
						browser.moveTab(tab.id, to: isPinned ? .pinned : .normal, in: space.id)
					}
				}
			}
			.accessibilityIdentifier("move-tab-space-\(tab.id.uuidString)")
			Button("Add to Favourites", systemImage: "star") {
				browser.moveTab(tab.id, to: .favourite)
			}

			Divider()

			Button("Copy URL", systemImage: "doc.on.doc", action: onCopyURL)
				.disabled(tab.copyableURL == nil)
				.accessibilityIdentifier("copy-tab-url-\(tab.id.uuidString)")
			Button("Bookmark Tab", systemImage: "bookmark") {
				browser.bookmarkTabs([tab.id])
			}
			Button("Add to Reading List", systemImage: "text.badge.plus") {
				browser.addToReadingList(tabID: tab.id)
			}
			.disabled(!browser.canAddToReadingList(tabID: tab.id))
			.accessibilityIdentifier("tab-add-reading-list-\(tab.id.uuidString)")
			Button("Save Page Offline", systemImage: "arrow.down.circle") {
				browser.saveReadingListSnapshot(tabID: tab.id)
			}
			.disabled(!browser.canSaveReadingListSnapshot(tabID: tab.id))
			.accessibilityIdentifier("tab-save-offline-\(tab.id.uuidString)")

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
		.disabled(normalCount < 2)

		Button(role: isPinned ? nil : .destructive) {
			browser.closeTab(tab.id)
		} label: {
			Label(tab.internalPage == .easel ? "Close Easel" : isPinned ? "Hibernate Tab" : "Close Tab", systemImage: isPinned && tab.internalPage != .easel ? "moon.zzz" : "xmark")
		}
	}
}

private struct SidebarSelectedTabsContextMenu: View {
	let browser: Browser
	let selection: BrowserSidebarTabSelection
	let ids: [UUID]
	let spaceID: UUID
	let isPinned: Bool

	var body: some View {
		Button("New Folder from \(ids.count) Tabs", systemImage: "folder.badge.plus") {
			browser.createPinnedFolder(with: ids, in: spaceID)
			selection.clear()
		}
		Button(isPinned ? "Unpin Selected Tabs" : "Pin Selected Tabs", systemImage: isPinned ? "pin.slash" : "pin") {
			browser.moveTabs(ids, to: isPinned ? .normal : .pinned, in: spaceID)
			selection.clear()
		}
		Button("Add to Favourites", systemImage: "star") {
			browser.moveTabs(ids, to: .favourite)
			selection.clear()
		}
		Divider()
		Button("Bookmark \(ids.count) Tabs", systemImage: "bookmark") {
			browser.bookmarkTabs(ids)
			selection.clear()
		}
		Button("Add to Reading List", systemImage: "text.badge.plus") {
			for id in ids {
				browser.addToReadingList(tabID: id)
			}
			selection.clear()
		}
		Divider()
		Button(isPinned ? "Hibernate Selected Tabs" : "Close Selected Tabs", systemImage: isPinned ? "moon.zzz" : "xmark", role: .destructive) {
			for id in ids {
				browser.closeTab(id)
			}
			selection.clear()
		}
	}
}

#if os(macOS)
	struct BrowserTabHoverPreviewOverlay: View {
		let browser: Browser
		@State private var coordinator = BrowserTabHoverPreviewCoordinator.shared
		@Environment(\.accessibilityReduceMotion) private var reduceMotion

		private let cardWidth: CGFloat = 320
		private let cardHeight: CGFloat = 306
		private let margin: CGFloat = 12

		var body: some View {
			GeometryReader { geometry in
				let globalFrame = geometry.frame(in: .global)
				if coordinator.isVisible,
				   coordinator.windowID == browser.windowID,
				   let tabID = coordinator.presentedTabID,
				   let tab = browser.tabsByID[tabID]
				{
					let desiredX = coordinator.sourceFrame.maxX - globalFrame.minX + margin + cardWidth / 2
					let desiredY = coordinator.sourceFrame.midY - globalFrame.minY
					let x = min(
						max(cardWidth / 2 + margin, desiredX),
						max(cardWidth / 2 + margin, geometry.size.width - cardWidth / 2 - margin)
					)
					let y = min(
						max(cardHeight / 2 + margin, desiredY),
						max(cardHeight / 2 + margin, geometry.size.height - cardHeight / 2 - margin)
					)

					ZStack {
						BrowserTabHoverPreviewCard(tab: tab, browser: browser)
							.id(tab.id)
							.transition(.opacity)
					}
					.animation(.easeInOut(duration: 0.075), value: tab.id)
					.frame(width: cardWidth, height: cardHeight)
					.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
					.position(x: x, y: y)
					.animation(reduceMotion ? nil : .easeInOut(duration: 0.075), value: y)
				}
			}
			.animation(.linear(duration: 0.1), value: coordinator.isVisible)
			.allowsHitTesting(false)
			.accessibilityHidden(true)
		}
	}

	private struct BrowserTabHoverPreviewCard: View {
		let tab: BrowserTab
		let browser: Browser
		@State private var memorySnapshot: BrowserTabProcessMemorySnapshot?
		@State private var hasSampledMemory = false

		private var host: String {
			if tab.internalPage != nil {
				return "Internal Page"
			}
			return tab.currentURL?.host ?? "New Tab"
		}

		private var unavailableMemoryLabel: String {
			if tab.isHibernated {
				return "Hibernated"
			}
			return hasSampledMemory ? "Not measurable" : "Measuring…"
		}

		var body: some View {
			VStack(alignment: .leading, spacing: 10) {
				HStack(spacing: 9) {
					if let favicon = tab.session.favicons.image(for: tab.currentURL, in: tab.controller?.webViewIfLoaded) {
						favicon
							.resizable()
							.scaledToFit()
							.frame(width: 18, height: 18)
					} else {
						Image(systemName: tab.internalPage?.symbol ?? "globe")
							.frame(width: 18, height: 18)
					}

					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: tab.title)
							.font(.headline)
							.lineLimit(1)
						Text(verbatim: host)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}

				Group {
					if let page = tab.internalPage {
						Image(systemName: page.symbol)
							.font(.system(size: 42))
							.frame(maxWidth: .infinity, maxHeight: .infinity)
					} else if let controller = tab.controller,
					          controller.hasCurrentPreviewSnapshot,
					          let snapshot = controller.previewSnapshot
					{
						Image(nsImage: snapshot)
							.resizable()
							.aspectRatio(contentMode: .fill)
					} else {
						ZStack {
							ThemeSurface(theme: browser.theme)
								.background(.quaternary)
							Image(systemName: tab.isHibernated ? "moon.zzz" : "rectangle.dashed")
								.font(.system(size: 28))
								.foregroundStyle(.secondary)
						}
					}
				}
				.frame(width: 296, height: 166)
				.clipped()
				.clipShape(RoundedRectangle(cornerRadius: 10))

				HStack {
					Text("Process memory")
						.font(.subheadline.weight(.semibold))
					Spacer()
					Text(memorySnapshot?.knownProcessBytes.map(Self.formatBytes) ?? unavailableMemoryLabel)
						.font(.subheadline.monospacedDigit())
						.foregroundStyle(.secondary)
				}
				if let snapshot = memorySnapshot {
					HStack(spacing: 12) {
						if let bytes = snapshot.webContentBytes {
							Text("Web: \(Self.formatBytes(bytes))")
						}
						if let bytes = snapshot.graphicsBytes {
							Text("GPU*: \(Self.formatBytes(bytes))")
						}
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.tertiary)
					.help("WebKit may share processes between tabs; GPU memory is not exclusive to this tab.")
				}
			}
			.padding(12)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.task(id: tab.id) {
				memorySnapshot = nil
				hasSampledMemory = false
				guard let controller = tab.controller else {
					hasSampledMemory = true
					return
				}

				if !controller.hasCurrentPreviewSnapshot {
					await controller.refreshPreviewSnapshot()
				}
				memorySnapshot = await sampleTabMemory(for: controller)
				hasSampledMemory = true
				while !Task.isCancelled {
					do {
						try await Task.sleep(for: .seconds(2))
					} catch {
						return
					}
					memorySnapshot = await sampleTabMemory(for: controller)
					hasSampledMemory = true
					if !controller.hasCurrentPreviewSnapshot {
						await controller.refreshPreviewSnapshot()
					}
				}
			}
		}

		private func sampleTabMemory(for controller: BrowserController) async -> BrowserTabProcessMemorySnapshot? {
			let snapshots = await BrowserController.tabProcessMemorySnapshots(for: [controller])
			return snapshots[controller.id]
		}

		private nonisolated static func formatBytes(_ bytes: UInt64) -> String {
			ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
		}
	}
#endif

#if os(macOS)
	private struct BrowserTabRowSplitDropDelegate: DropDelegate {
		let browser: Browser
		let anchorID: UUID
		let width: CGFloat
		@Binding var side: Browser.SplitSide?

		private func locationSide(_ info: DropInfo) -> Browser.SplitSide {
			info.location.x < width / 2 ? .left : .right
		}

		func validateDrop(info: DropInfo) -> Bool {
			!browser.isPrivate && !browser.isMini
				&& browser.tab(withID: anchorID)?.canAppearInEaselSplit == true
				&& info.hasItemsConforming(to: ["com.omeriadon.astra.tab"])
		}

		func dropEntered(info: DropInfo) {
			guard validateDrop(info: info) else { return }
			side = locationSide(info)
			BrowserTabHoverPreviewCoordinator.shared.dismiss(for: browser.windowID)
		}

		func dropUpdated(info: DropInfo) -> DropProposal? {
			guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
			side = locationSide(info)
			return DropProposal(operation: .move)
		}

		func dropExited(info _: DropInfo) {
			side = nil
		}

		func performDrop(info: DropInfo) -> Bool {
			defer { side = nil }
			guard validateDrop(info: info),
			      let provider = info.itemProviders(for: ["com.omeriadon.astra.tab"]).first
			else { return false }
			let onLeft = locationSide(info) == .left
			_ = provider.loadDataRepresentation(forTypeIdentifier: "com.omeriadon.astra.tab") { data, _ in
				guard let data, let raw = String(data: data, encoding: .utf8),
				      let id = UUID(uuidString: raw), id != anchorID else { return }
				Task { @MainActor in
					browser.openSplit(id, beside: anchorID, onLeft: onLeft)
				}
			}
			return true
		}
	}
#endif
