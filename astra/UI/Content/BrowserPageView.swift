import SwiftUI

struct BrowserPageView: View {
	let browser: Browser
	let cornerRadius: CGFloat
	var insets = BrowserViewportInsets()
	private var toastManager: ToastManager {
		browser.session.toastManager
	}

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	private var hasDockedWebInspector: Bool {
		#if os(macOS)
			browser.selectedTab?.activeController?.hasDockedWebInspector == true
		#else
			false
		#endif
	}

	var body: some View {
		let hasActiveDuplicate = BrowserWindowRegistry.shared.hasActiveDuplicate(of: browser)
		let selectedTab = browser.selectedTab
		return ZStack(alignment: .top) {
			BrowserContentView(browser: browser, insets: insets)
			#if os(macOS)
				.blur(radius: hasActiveDuplicate ? 10 : 0)
				.allowsHitTesting(!hasActiveDuplicate)
				.accessibilityHidden(hasActiveDuplicate)
			#endif

			if let tab = selectedTab,
			   !hasActiveDuplicate,
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
				if let controller = browser.selectedTab?.activeController,
				   controller.readerHTML == nil,
				   !hasActiveDuplicate
				{
					BrowserAIHoverPreview(browser: browser, controller: controller)
						.id(controller.id)
				}
			}
		#endif

			.overlay(alignment: .topTrailing) {
				if let controller = browser.selectedTab?.activeController, controller.showsFind {
					BrowserFindBar(controller: controller)
						.id(controller.id)
				}
			}
			.overlay(alignment: .topTrailing) {
				if let toast = toastManager.toast {
					BrowserToastView(toast: toast)
						.padding(.top, 12)
						.padding(.trailing, 14)
						.transition(reduceMotion ? .opacity : .move(edge: .trailing))
				}
			}
			.animation(.easeOut(duration: 0.1), value: toastManager.toast != nil)
			.allowsHitTesting(!hasActiveDuplicate)
			.animation(nil, value: hasDockedWebInspector)
			.clipShape(
				UnevenRoundedRectangle(
					cornerRadii: RectangleCornerRadii(
						topLeading: cornerRadius,
						bottomLeading: cornerRadius,
						bottomTrailing: cornerRadius,
						topTrailing: hasDockedWebInspector ? 7 : cornerRadius
					)
				)
			)
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
