import SwiftUI

struct BrowserPageView: View {
	let browser: Browser
	let cornerRadius: CGFloat
	var insets = BrowserViewportInsets()
	var tabID: UUID?
	var showsPeeks = true
	@State private var presentedSpaceID: UUID
	@State private var presentedTabID: UUID
	@State private var contentOpacity = 1.0
	@State private var transitionGeneration = 0

	init(browser: Browser, cornerRadius: CGFloat, insets: BrowserViewportInsets = BrowserViewportInsets()) {
		self.init(browser: browser, cornerRadius: cornerRadius, insets: insets, tabID: nil, showsPeeks: true)
	}

	init(browser: Browser, cornerRadius: CGFloat, insets: BrowserViewportInsets = BrowserViewportInsets(), tabID: UUID?, showsPeeks: Bool = true) {
		self.browser = browser
		self.cornerRadius = cornerRadius
		self.insets = insets
		self.tabID = tabID
		self.showsPeeks = showsPeeks
		_presentedSpaceID = State(initialValue: browser.selectedSpace.id)
		_presentedTabID = State(initialValue: browser.selectedTabID)
	}

	private var displayedTab: BrowserTab? {
		if let tabID {
			return browser.tab(withID: tabID)
		}
		if presentedSpaceID != browser.selectedSpace.id {
			return browser.tab(withID: presentedTabID) ?? browser.selectedTab
		}
		return browser.selectedTab
	}

	private var toastManager: ToastManager {
		browser.session.toastManager
	}

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	#if os(macOS)
		@State private var browserAgentServer = BrowserAgentServer.shared
	#endif
	private var hasDockedWebInspector: Bool {
		#if os(macOS)
			browser.selectedTab?.activeController?.hasDockedWebInspector == true
		#else
			false
		#endif
	}

	var body: some View {
		let hasActiveDuplicate = BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser)
		let selectedTab = displayedTab
		return ZStack(alignment: .top) {
			BrowserContentView(browser: browser, insets: insets, displayedTabID: selectedTab?.id)
			#if os(macOS)
				.blur(radius: hasActiveDuplicate ? 10 : 0)
				.allowsHitTesting(!hasActiveDuplicate)
				.accessibilityHidden(hasActiveDuplicate)
			#endif

			if let tab = selectedTab,
			   showsPeeks, !hasActiveDuplicate,
			   !tab.peeks.isEmpty,
			   tab.activeController !== tab.controller
			{
				PeekStackView(tab: tab, browser: browser)
					.id(tab.id)
			}
		}
		.accessibilityHidden(selectedTab?.activeController?.readerHTML != nil)
		.overlay {
			if let controller = selectedTab?.activeController,
			   let html = controller.readerHTML,
			   !hasActiveDuplicate
			{
				BrowserReaderView(controller: controller, html: html)
					.id(controller.id)
					.padding(.top, insets.obscured.top)
					.padding(.bottom, insets.obscured.bottom)
			}
		}
		.animation(nil, value: hasActiveDuplicate)
		.allowsHitTesting(!hasActiveDuplicate)
		#if os(macOS)
			.overlay {
				if let controller = selectedTab?.activeController,
				   controller.readerHTML == nil,
				   !hasActiveDuplicate
				{
					BrowserAIHoverPreview(browser: browser, controller: controller)
						.id(controller.id)
				}
			}
		#endif

			.overlay(alignment: .topTrailing) {
				if let controller = selectedTab?.activeController, controller.showsFind {
					BrowserFindBar(controller: controller)
						.id(controller.id)
				}
			}
			.overlay(alignment: .topTrailing) {
				if let toast = toastManager.toast {
					BrowserToastView(toast: toast)
						.padding(.top, 12)
						.padding(.trailing, 14)
						.transition(unsafe reduceMotion ? .opacity : .move(edge: .trailing))
				}
			}
			.animation(.easeOut(duration: 0.1), value: toastManager.toast != nil)
			.allowsHitTesting(!hasActiveDuplicate)
			.animation(nil, value: hasDockedWebInspector)
			.clipShape(
				RoundedRectangle(cornerRadius: cornerRadius)
			)
		#if os(macOS)
			.overlay {
				if let tab = selectedTab,
				   !hasActiveDuplicate,
				   browserAgentServer.isControlled(tab.id)
				{
					BrowserAgentControlledPageBorder(cornerRadius: cornerRadius)
				}
			}
		#endif
			// Keep outgoing page content stable until the fade-out completes.
			.opacity(contentOpacity)
			.allowsHitTesting(presentedSpaceID == browser.selectedSpace.id)
			.onChange(of: browser.selectedTabID) { _, id in
				if presentedSpaceID == browser.selectedSpace.id {
					presentedTabID = id
				}
			}
			.onChange(of: browser.selectedSpace.id) { _, newID in
				transitionGeneration += 1
				let generation = transitionGeneration
				guard !reduceMotion, presentedSpaceID != newID,
				      browser.tab(withID: presentedTabID) != nil
				else {
					presentedSpaceID = newID
					presentedTabID = browser.selectedTabID
					contentOpacity = 1
					return
				}

				withAnimation(.easeInOut(duration: 0.1)) {
					contentOpacity = 0
				}
				Task { @MainActor in
					try? await Task.sleep(for: .milliseconds(105))
					guard generation == transitionGeneration else { return }
					presentedSpaceID = browser.selectedSpace.id
					presentedTabID = browser.selectedTabID
					withAnimation(.easeInOut(duration: 0.1)) {
						contentOpacity = 1
					}
				}
			}
	}
}

/// The animated split views update their child values each frame.
/// Page overlays only need a parent-driven refresh when their actual
/// geometry changes; Browser's @Observable properties still invalidate
/// the body independently for tab selection, reader, find and peeks.
extension BrowserPageView: Equatable {
	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.browser === rhs.browser
			&& lhs.cornerRadius == rhs.cornerRadius
			&& lhs.tabID == rhs.tabID
			&& lhs.showsPeeks == rhs.showsPeeks
			&& lhs.hasDockedWebInspector == rhs.hasDockedWebInspector
			&& sameEdges(lhs.insets.obscured, rhs.insets.obscured)
			&& sameEdges(lhs.insets.minimum, rhs.insets.minimum)
			&& sameEdges(lhs.insets.maximum, rhs.insets.maximum)
	}

	private static func sameEdges(_ lhs: EdgeInsets, _ rhs: EdgeInsets) -> Bool {
		lhs.top == rhs.top && lhs.bottom == rhs.bottom
			&& lhs.leading == rhs.leading && lhs.trailing == rhs.trailing
	}
}
