import SwiftUI

struct BrowserAddressField: View {
	let browser: Browser
	@AppStorage("addressDisplayStyle") private var addressDisplayStyle = AddressDisplayStyle.simple.rawValue
	@State private var addressText = ""
	@FocusState private var isFocused: Bool

	private var displayStyle: AddressDisplayStyle {
		AddressDisplayStyle(rawValue: addressDisplayStyle) ?? .simple
	}

	private var isDimmed: Bool {
		displayStyle == .dimmed && !isFocused
	}

	var body: some View {
		addressInput
			.onChange(of: browser.selectedTabID) { _, _ in
				updateForSelectedTab()
			}
			.onChange(of: browser.selectedTab?.controller.url) { _, url in
				guard !isFocused else { return }
				addressText = BrowserAddress.displayString(for: url, style: displayStyle, isEditing: false)
			}
			.onChange(of: addressDisplayStyle) { _, _ in
				updateAddressFromURL()
			}
			.onChange(of: isFocused) { _, focused in
				addressText = BrowserAddress.displayString(
					for: browser.selectedTab?.controller.url,
					style: displayStyle,
					isEditing: focused
				)
			}
			.onAppear {
				updateForSelectedTab()
			}
	}

	private var addressInput: some View {
		TextField("", text: $addressText)
			.textFieldStyle(.plain)
			.fontDesign(.monospaced)
			.lineLimit(1)
			.foregroundStyle(isDimmed ? .clear : .primary)
			.focused($isFocused)
			.submitLabel(.go)
			.onSubmit(submitAddress)
			.onKeyPress(.escape) {
				isFocused = false
				return .handled
			}
			.overlay(alignment: .leading) {
				if isDimmed {
					Text(dimmedAddressText)
						.fontDesign(.monospaced)
						.lineLimit(1)
						.allowsHitTesting(false)
						.accessibilityHidden(true)
				}
			}
			.accessibilityLabel("Address")
			.accessibilityIdentifier("browser-address")
	}

	private var dimmedAddressText: AttributedString {
		var text = AttributedString(addressText)
		text.foregroundColor = Color.primary.opacity(0.2)
		guard let url = browser.selectedTab?.controller.url else {
			text.foregroundColor = .primary
			return text
		}
		for range in BrowserAddress.primaryTextRanges(for: url) {
			guard let attributedRange = Range(range, in: text) else { continue }
			text[attributedRange].foregroundColor = .primary
		}
		return text
	}

	private func updateForSelectedTab() {
		updateAddressFromURL()
		if browser.selectedTab?.controller.url == nil {
			isFocused = true
		}
	}

	private func updateAddressFromURL() {
		addressText = BrowserAddress.displayString(
			for: browser.selectedTab?.controller.url,
			style: displayStyle,
			isEditing: isFocused
		)
	}

	private func submitAddress() {
		guard let destination = BrowserAddress.destination(for: addressText) else { return }
		browser.selectedTab?.controller.load(destination)
		addressText = BrowserAddress.displayString(for: destination, style: displayStyle, isEditing: false)
		isFocused = false
	}
}
