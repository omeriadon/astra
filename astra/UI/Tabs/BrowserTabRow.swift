#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif
import Defaults
import Foundation
import Observation
import SwiftUI

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
	var isOpenElsewhere: Bool?
	var onSelectTab: ((UUID) -> Void)?
	var navigationNamespace: Namespace.ID?
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
	#endif
	@State private var renameText = ""
	@Default(.developerModeEnabled) private var developerModeEnabled
	@FocusState private var isTitleFocused: Bool
	#if os(macOS)
		@State private var tabDrag = BrowserTabDragCoordinator.shared
	#endif

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
			TabIconView(tab: tab, browser: browser, onSelectTab: onSelectTab)
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

			TabTitleView(
				tab: tab,
				browser: browser,
				isRenaming: isRenaming,
				isHovered: isHovered,
				showsCloseButton: isSelected || onSelectTab != nil || isHovered,
				closeFadeWidth: onSelectTab != nil ? 64 : (isSelected || isHovered ? 36 : 12),
				renameText: $renameText,
				isTitleFocused: $isTitleFocused,
				onBeginRenaming: beginRenaming,
				onCommitRenaming: commitRenaming,
				onCancelRenaming: cancelRenaming,
				onSelectTab: onSelectTab
			)
			.overlay(alignment: .trailing) {
				if isSelected || onSelectTab != nil {
					TabCloseButton(tab: tab, browser: browser, isPinned: isPinned, isCompact: onSelectTab != nil)
						.keyboardShortcut("W", modifiers: .command)
				} else if isHovered {
					TabCloseButton(tab: tab, browser: browser, isPinned: isPinned, isCompact: onSelectTab != nil)
				}
			}
		}
		.opacity(isOpenElsewhere ? 0.35 : 1)
		.allowsHitTesting(!isOpenElsewhere)
		.padding(.horizontal, 8)
		.frame(height: onSelectTab == nil ? 28 : 44)
		.matchedTransitionSource(id: tab.id.uuidString, in: navigationNamespace ?? rowTransitions)
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
		#if os(macOS)
		.background {
			if tabDrag.activeTabID != nil {
				BrowserDropZone(
					browser: browser,
					area: isPinned ? .pinned : .normal,
					spaceID: rowSpaceID ?? browser.workspace.selectedSpaceID,
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
		.onHover { hovering in
			isHovered = hovering
			#if os(macOS)
				guard onSelectTab == nil else { return }
				if !hovering {
					if hoverPreviewStarted {
						BrowserTabHoverPreviewCoordinator.shared.hoverEnded(
							tabID: tab.id,
							windowID: browser.windowID
						)
					}
					hoverPreviewStarted = false
				}
			#endif
		}
		#if os(macOS)
		.modifier(
			TabHoverGeometryModifier(enabled: isHovered && onSelectTab == nil) { frame in
				hoverFrame = frame
				if hoverPreviewStarted {
					BrowserTabHoverPreviewCoordinator.shared.updateFrame(
						for: tab.id,
						windowID: browser.windowID,
						frame: frame
					)
				} else {
					hoverPreviewStarted = true
					BrowserTabHoverPreviewCoordinator.shared.hoverBegan(
						tabID: tab.id,
						windowID: browser.windowID,
						sourceFrame: frame
					)
				}
			}
		)
		#endif
		.contextMenu {
			TabRowContextMenu(
				tab: tab,
				browser: browser,
				isPinned: isPinned,
				canCloseAbove: canCloseAbove,
				canCloseBelow: canCloseBelow,
				normalCount: resolvedNormalCount,
				onCopyURL: copyURL,
				onBeginRenaming: beginRenaming,
				onSelectTab: onSelectTab
			)
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
			&& (lhs.onSelectTab == nil) == (rhs.onSelectTab == nil)
			&& lhs.navigationNamespace == rhs.navigationNamespace
	}
}

private struct TabIconView: View {
	let tab: BrowserTab
	let browser: Browser
	var onSelectTab: ((UUID) -> Void)?
	#if os(macOS)
		@State private var isMouseDown = false
	#endif

	var body: some View {
		Button {
			browser.selectTab(tab.id)
			onSelectTab?(tab.id)
		} label: {
			Label {
				Text("Select Tab")
			} icon: {
				if let page = tab.internalPage {
					Image(systemName: page.symbol)
				} else if let favicon = browser.session.favicons.image(
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
			.frame(width: onSelectTab == nil ? 16 : 22, height: onSelectTab == nil ? 16 : 22)
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
			.accessibilityIdentifier("select-tab-\(tab.id.uuidString)")
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
	#if os(macOS)
		@State private var isMouseDown = false
	#endif

	var body: some View {
		if isRenaming {
			TextField("Tab Name", text: $renameText)
				.textFieldStyle(.plain)
				.padding(.trailing, showsCloseButton ? closeFadeWidth : 0)
				.focused(isTitleFocused)
				.onSubmit(onCommitRenaming)
				.onKeyPress(.escape) {
					onCancelRenaming()
					return .handled
				}
				.onChange(of: isTitleFocused.wrappedValue) { _, isFocused in
					if !isFocused, isRenaming {
						onCommitRenaming()
					}
				}
				.accessibilityIdentifier("tab-name-\(tab.id.uuidString)")
		} else {
			Button {
				browser.selectTab(tab.id)
				onSelectTab?(tab.id)
			} label: {
				GeometryReader { proxy in
					Text(verbatim: tab.title)
						.contentTransition(.opacity)
						.animation(reduceMotion ? nil : .smooth(duration: 0.2), value: tab.title)
						.lineLimit(1)
						.fixedSize(horizontal: true, vertical: false)
						.frame(width: proxy.size.width, alignment: .leading)
						.mask(titleFadeMask(width: proxy.size.width))
						.frame(height: proxy.size.height, alignment: .leading)
						.clipped()
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
				.contentShape(Rectangle())
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
				.simultaneousGesture(
					TapGesture(count: 2)
						.onEnded { _ in onBeginRenaming() }
				)
				.accessibilityLabel(Text(verbatim: tab.title))
				.accessibilityActions {
					if tab.internalPage == nil {
						Button("Rename", systemImage: "pencil") { onBeginRenaming() }
					}
				}
				.accessibilityIdentifier("tab-title-\(tab.id.uuidString)")
		}
	}

	private func titleFadeMask(width: CGFloat) -> some View {
		let fadeWidth = isHovered ? closeFadeWidth + 28 : closeFadeWidth
		let fadeStart = max(0, 1 - fadeWidth / max(width, 1))
		let fadeEnd = isHovered ? max(0, 1 - (onSelectTab == nil ? 20 : 44) / max(width, 1)) : 1
		return LinearGradient(
			stops: [
				.init(color: .white, location: 0),
				.init(color: .white, location: fadeStart),
				.init(color: .clear, location: fadeEnd),
				.init(color: .clear, location: 1),
			],
			startPoint: .leading,
			endPoint: .trailing
		)
	}
}

private struct TabCloseButton: View {
	let tab: BrowserTab
	let browser: Browser
	let isPinned: Bool
	var isCompact = false
	@State private var hovered = false

	var body: some View {
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
				.frame(width: isCompact ? 44 : 13, height: isCompact ? 44 : 16)
		}
		.buttonStyle(.plain)
		.accessibilityLabel(isPinned ? "Hibernate Tab" : "Close Tab")
		.accessibilityIdentifier("close-tab-\(tab.id.uuidString)")
	}
}

private struct TabRowContextMenu: View {
	let tab: BrowserTab
	let browser: Browser
	let isPinned: Bool
	let canCloseAbove: Bool
	let canCloseBelow: Bool
	let normalCount: Int
	let onCopyURL: () -> Void
	let onBeginRenaming: () -> Void
	var onSelectTab: ((UUID) -> Void)?

	var body: some View {
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
			Label(isPinned ? "Hibernate Tab" : "Close Tab", systemImage: isPinned ? "moon.zzz" : "xmark")
		}
	}
}

#if os(macOS)
	private struct TabHoverGeometryModifier: ViewModifier {
		let enabled: Bool
		let onFrame: (CGRect) -> Void

		func body(content: Content) -> some View {
			if enabled {
				content.onGeometryChange(for: CGRect.self) { proxy in
					proxy.frame(in: .global)
				} action: { frame in
					onFrame(frame)
				}
			} else {
				content
			}
		}
	}

	@MainActor
	@Observable
	final class BrowserTabHoverPreviewCoordinator {
		static let shared = BrowserTabHoverPreviewCoordinator()

		private(set) var presentedTabID: UUID?
		private(set) var windowID: UUID?
		private(set) var sourceFrame = CGRect.zero
		private(set) var isVisible = false

		@ObservationIgnored private var hoveredTabID: UUID?
		@ObservationIgnored private var activationTask: Task<Void, Never>?
		@ObservationIgnored private var dismissalTask: Task<Void, Never>?
		@ObservationIgnored private var warmSession = false

		private init() {}

		func hoverBegan(tabID: UUID, windowID: UUID, sourceFrame: CGRect) {
			dismissalTask?.cancel()
			dismissalTask = nil
			hoveredTabID = tabID
			self.windowID = windowID
			self.sourceFrame = sourceFrame

			if warmSession {
				activationTask?.cancel()
				activationTask = nil
				presentedTabID = tabID
				isVisible = true
				return
			}

			activationTask?.cancel()
			activationTask = Task { @MainActor [weak self] in
				do {
					try await Task.sleep(for: .seconds(2))
				} catch {
					return
				}
				guard let self,
				      hoveredTabID == tabID,
				      self.windowID == windowID
				else { return }
				warmSession = true
				presentedTabID = tabID
				isVisible = true
			}
		}

		func updateFrame(for tabID: UUID, windowID: UUID, frame: CGRect) {
			guard hoveredTabID == tabID, self.windowID == windowID else { return }
			sourceFrame = frame
		}

		func hoverEnded(tabID: UUID, windowID: UUID) {
			guard hoveredTabID == tabID, self.windowID == windowID else { return }
			hoveredTabID = nil
			activationTask?.cancel()
			activationTask = nil

			dismissalTask?.cancel()
			dismissalTask = Task { @MainActor [weak self] in
				do {
					try await Task.sleep(for: .milliseconds(160))
				} catch {
					return
				}
				guard let self, hoveredTabID == nil else { return }
				isVisible = false
				presentedTabID = nil

				do {
					try await Task.sleep(for: .milliseconds(340))
				} catch {
					return
				}
				guard hoveredTabID == nil else { return }
				warmSession = false
				self.windowID = nil
			}
		}

		func dismiss(for windowID: UUID) {
			guard self.windowID == windowID else { return }
			activationTask?.cancel()
			dismissalTask?.cancel()
			activationTask = nil
			dismissalTask = nil
			hoveredTabID = nil
			presentedTabID = nil
			isVisible = false
			warmSession = false
			self.windowID = nil
		}
	}

	struct BrowserTabHoverPreviewOverlay: View {
		let browser: Browser
		@State private var coordinator = BrowserTabHoverPreviewCoordinator.shared

		private let cardWidth: CGFloat = 320
		private let cardHeight: CGFloat = 340
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

					BrowserTabHoverPreviewCard(tab: tab)
						.frame(width: cardWidth, height: cardHeight)
						.position(x: x, y: y)
						.id(tab.id)
						.transition(.opacity)
				}
			}
			.animation(.linear(duration: 0.1), value: coordinator.isVisible)
			.animation(.linear(duration: 0.1), value: coordinator.presentedTabID)
			.allowsHitTesting(false)
			.accessibilityHidden(true)
		}
	}

	private struct BrowserTabHoverPreviewCard: View {
		let tab: BrowserTab
		@State private var memory: BrowserTabProcessMemorySnapshot?
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
			return hasSampledMemory ? "Unavailable" : "Measuring…"
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
					} else if let snapshot = tab.controller?.previewSnapshot {
						Image(nsImage: snapshot)
							.resizable()
							.aspectRatio(contentMode: .fill)
					} else {
						ZStack {
							Color.white.opacity(0.06)
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
					Text("Memory")
						.font(.subheadline.weight(.semibold))
					Spacer()
					Text(memory?.relatedProcessBytes.map(Self.formatBytes) ?? unavailableMemoryLabel)
						.font(.subheadline.monospacedDigit())
						.foregroundStyle(.secondary)
				}

				HStack(alignment: .top, spacing: 8) {
					memoryMetric("Web + JS", bytes: memory?.webContentBytes)
					memoryMetric("Graphics*", bytes: memory?.graphicsBytes)
					memoryMetric("Network*", bytes: memory?.networkBytes)
					if memory?.modelBytes != nil {
						memoryMetric("Model*", bytes: memory?.modelBytes)
					}
				}

				Text("* Shared WebKit process; shown for context rather than attributed entirely to this tab.")
					.font(.system(size: 9))
					.foregroundStyle(.tertiary)
					.lineLimit(2)
			}
			.padding(12)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
			.task(id: tab.id) {
				memory = nil
				hasSampledMemory = false
				guard let controller = tab.controller else {
					hasSampledMemory = true
					return
				}

				await controller.refreshPreviewSnapshot()
				while !Task.isCancelled {
					memory = controller.tabProcessMemorySnapshot()
					hasSampledMemory = true
					do {
						try await Task.sleep(for: .seconds(1))
					} catch {
						return
					}
				}
			}
		}

		private func memoryMetric(_ label: String, bytes: UInt64?) -> some View {
			VStack(alignment: .leading, spacing: 2) {
				Text(label)
					.font(.system(size: 9))
					.foregroundStyle(.tertiary)
				Text(bytes.map(Self.formatBytes) ?? "—")
					.font(.caption2.monospacedDigit())
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}

		private nonisolated static func formatBytes(_ bytes: UInt64) -> String {
			ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
		}
	}
#endif
