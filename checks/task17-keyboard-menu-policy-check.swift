import AppKit
import Foundation

@main
struct Task17KeyboardMenuPolicyCheck {
	static func main() {
		assert(BrowserKeyboardMenuPolicy.ownsFocusedTarget(isKeyWindow: true, matchesKeyWindow: true))
		assert(!BrowserKeyboardMenuPolicy.ownsFocusedTarget(isKeyWindow: false, matchesKeyWindow: true))
		assert(!BrowserKeyboardMenuPolicy.ownsFocusedTarget(isKeyWindow: true, matchesKeyWindow: false))

		assert(BrowserKeyboardMenuPolicy.ownsTabSwitch(
			isFocusedWindow: true,
			hasMarkedText: false,
			isKeyDown: true,
			keyCode: 48,
			modifiers: [.control]
		))
		assert(BrowserKeyboardMenuPolicy.ownsTabSwitch(
			isFocusedWindow: true,
			hasMarkedText: false,
			isKeyDown: true,
			keyCode: 48,
			modifiers: [.control, .shift]
		))
		assert(!BrowserKeyboardMenuPolicy.ownsTabSwitch(
			isFocusedWindow: true,
			hasMarkedText: false,
			isKeyDown: true,
			keyCode: 48,
			modifiers: [.control, .option]
		))
		assert(!BrowserKeyboardMenuPolicy.ownsTabSwitch(
			isFocusedWindow: true,
			hasMarkedText: false,
			isKeyDown: true,
			keyCode: 48,
			modifiers: [.control, .command]
		))
		assert(!BrowserKeyboardMenuPolicy.ownsTabSwitch(
			isFocusedWindow: true,
			hasMarkedText: true,
			isKeyDown: true,
			keyCode: 48,
			modifiers: [.control]
		))
		assert(!BrowserKeyboardMenuPolicy.ownsTabSwitch(
			isFocusedWindow: false,
			hasMarkedText: false,
			isKeyDown: true,
			keyCode: 48,
			modifiers: [.control]
		))

		assert(BrowserKeyboardMenuPolicy.canCopyURL(URL(string: "https://example.com")))
		assert(!BrowserKeyboardMenuPolicy.canCopyURL(nil))
		assert(BrowserKeyboardMenuPolicy.canResetZoom(1.1))
		assert(!BrowserKeyboardMenuPolicy.canResetZoom(1))
		assert(!BrowserKeyboardMenuPolicy.canResetZoom(.infinity))
		assert(BrowserKeyboardMenuPolicy.canZoomIn(1))
		assert(!BrowserKeyboardMenuPolicy.canZoomIn(5))
		assert(BrowserKeyboardMenuPolicy.canZoomOut(1))
		assert(!BrowserKeyboardMenuPolicy.canZoomOut(0.25))

		assert(BrowserKeyboardMenuPolicy.canReopenLastClosedTab(
			isFocusedBrowser: true,
			isMini: false,
			isAuthenticationSession: false,
			hasClosedTab: true
		))
		assert(!BrowserKeyboardMenuPolicy.canReopenLastClosedTab(
			isFocusedBrowser: true,
			isMini: false,
			isAuthenticationSession: false,
			hasClosedTab: false
		))
		assert(!BrowserKeyboardMenuPolicy.canReopenLastClosedTab(
			isFocusedBrowser: true,
			isMini: true,
			isAuthenticationSession: false,
			hasClosedTab: true
		))
		assert(!BrowserKeyboardMenuPolicy.canReopenLastClosedTab(
			isFocusedBrowser: true,
			isMini: true,
			isAuthenticationSession: true,
			hasClosedTab: true
		))

		assert(BrowserKeyboardMenuPolicy.canPromptForAddressAction(
			isFocusedBrowser: true,
			isSelectedController: true,
			isSameSession: true,
			isCurrentWebView: true,
			isSameNavigation: true,
			webViewMatchesOwnerWindow: true
		))
		assert(!BrowserKeyboardMenuPolicy.canPromptForAddressAction(
			isFocusedBrowser: false,
			isSelectedController: true,
			isSameSession: true,
			isCurrentWebView: true,
			isSameNavigation: true,
			webViewMatchesOwnerWindow: true
		))
		assert(!BrowserKeyboardMenuPolicy.canPromptForAddressAction(
			isFocusedBrowser: true,
			isSelectedController: false,
			isSameSession: true,
			isCurrentWebView: true,
			isSameNavigation: true,
			webViewMatchesOwnerWindow: true
		))
		assert(!BrowserKeyboardMenuPolicy.canPromptForAddressAction(
			isFocusedBrowser: true,
			isSelectedController: true,
			isSameSession: false,
			isCurrentWebView: true,
			isSameNavigation: true,
			webViewMatchesOwnerWindow: true
		))
		assert(!BrowserKeyboardMenuPolicy.canPromptForAddressAction(
			isFocusedBrowser: true,
			isSelectedController: true,
			isSameSession: true,
			isCurrentWebView: false,
			isSameNavigation: true,
			webViewMatchesOwnerWindow: true
		))
		assert(!BrowserKeyboardMenuPolicy.canPromptForAddressAction(
			isFocusedBrowser: true,
			isSelectedController: true,
			isSameSession: true,
			isCurrentWebView: true,
			isSameNavigation: false,
			webViewMatchesOwnerWindow: true
		))
		assert(!BrowserKeyboardMenuPolicy.canPromptForAddressAction(
			isFocusedBrowser: true,
			isSelectedController: true,
			isSameSession: true,
			isCurrentWebView: true,
			isSameNavigation: true,
			webViewMatchesOwnerWindow: false
		))

		print("Task 17 keyboard menu policy checks passed")
	}
}
