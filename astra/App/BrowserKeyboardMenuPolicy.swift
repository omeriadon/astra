#if os(macOS)
	import AppKit
	import Foundation

	enum BrowserKeyboardMenuPolicy {
		static func ownsFocusedTarget(isKeyWindow: Bool, matchesKeyWindow: Bool) -> Bool {
			isKeyWindow && matchesKeyWindow
		}

		static func ownsTabSwitch(
			isFocusedWindow: Bool,
			hasMarkedText: Bool,
			isKeyDown: Bool,
			keyCode: UInt16,
			modifiers: NSEvent.ModifierFlags
		) -> Bool {
			let flags = modifiers.intersection(.deviceIndependentFlagsMask)
			return isFocusedWindow && !hasMarkedText && isKeyDown && (keyCode == 48 || keyCode == 50)
				&& flags.contains(.control) && !flags.contains(.shift) && !flags.contains(.command) && !flags.contains(.option)
		}

		static func canCopyURL(_ url: URL?) -> Bool {
			url != nil
		}

		static func canResetZoom(_ zoom: Double?) -> Bool {
			guard let zoom, zoom.isFinite else { return false }
			return zoom != BrowserZoomPolicy.defaultZoom
		}

		static func canZoomIn(_ zoom: Double?) -> Bool {
			guard let zoom, zoom.isFinite else { return false }
			return zoom < BrowserZoomPolicy.range.upperBound
		}

		static func canZoomOut(_ zoom: Double?) -> Bool {
			guard let zoom, zoom.isFinite else { return false }
			return zoom > BrowserZoomPolicy.range.lowerBound
		}

		static func canReopenLastClosedTab(
			isFocusedBrowser: Bool,
			isMini: Bool,
			isAuthenticationSession: Bool,
			hasClosedTab: Bool
		) -> Bool {
			isFocusedBrowser && !isMini && !isAuthenticationSession && hasClosedTab
		}

		static func canPromptForAddressAction(
			isFocusedBrowser: Bool,
			isSelectedController: Bool,
			isSameSession: Bool,
			isCurrentWebView: Bool,
			isSameNavigation: Bool,
			webViewMatchesOwnerWindow: Bool
		) -> Bool {
			isFocusedBrowser && isSelectedController && isSameSession && isCurrentWebView
				&& isSameNavigation && webViewMatchesOwnerWindow
		}
	}
#endif
