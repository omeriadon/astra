import Defaults
import SwiftUI

struct BrowserAddressField: View {
	let browser: Browser
	@Default(.addressDisplayStyle) private var addressDisplayStyle
	@State private var addressText = ""
	@FocusState private var isFocused: Bool

	private var isDimmed: Bool {
		addressDisplayStyle == .dimmed && !isFocused
	}

	private var isGoogleSearch: Bool {
		BrowserAddress.isGoogleSearchURL(browser.selectedTab?.activeController?.url)
	}

	var body: some View {
		addressInput
			.onChange(of: browser.selectedTabID) { _, _ in
				updateForSelectedTab()
			}
			.onChange(of: browser.selectedTab?.peeks.last?.id) { _, _ in
				isFocused = false
				updateAddressFromURL()
			}
			.onChange(of: browser.selectedTab?.activeController?.url) { _, url in
				guard !isFocused else { return }
				addressText = BrowserAddress.displayString(for: url, style: addressDisplayStyle, isEditing: false)
			}
			.onChange(of: addressDisplayStyle) { _, _ in
				updateAddressFromURL()
			}
			.onChange(of: isFocused) { _, focused in
				addressText = BrowserAddress.displayString(
					for: browser.selectedTab?.activeController?.url,
					style: addressDisplayStyle,
					isEditing: focused
				)
			}
			.onAppear {
				updateAddressFromURL()
			}
	}

	private var addressInput: some View {
		TextField("", text: $addressText)
			.textFieldStyle(.plain)
			.fontDesign(.monospaced)
			.lineLimit(1)
			.foregroundStyle(isDimmed ? .clear : .primary)
			.padding(.leading, isGoogleSearch ? 20 : 0)
			.focused($isFocused)
			.submitLabel(.go)
			.onSubmit(submitAddress)
			.onKeyPress(.escape) {
				isFocused = false
				return .handled
			}
			.overlay(alignment: .leading) {
				HStack(spacing: 6) {
					if isGoogleSearch {
						Image(systemName: "magnifyingglass")
							.accessibilityHidden(true)
					}
					if isDimmed {
						Text(dimmedAddressText)
							.fontDesign(.monospaced)
							.lineLimit(1)
							.frame(maxWidth: .infinity, alignment: .leading)
					}
				}
				.allowsHitTesting(false)
				.accessibilityHidden(true)
			}
			.accessibilityLabel("Address")
			.accessibilityIdentifier("browser-address")
	}

	private var dimmedAddressText: AttributedString {
		var text = AttributedString(addressText)
		text.foregroundColor = Color.primary.opacity(0.2)
		guard let url = browser.selectedTab?.activeController?.url else {
			text.foregroundColor = .primary
			return text
		}
		for range in BrowserAddress.primaryTextRanges(for: url, displayedText: addressText) {
			guard let attributedRange = Range(range, in: text) else { continue }
			text[attributedRange].foregroundColor = .primary
		}
		return text
	}

	private func updateForSelectedTab() {
		updateAddressFromURL()
		if browser.selectedTab?.activeController?.url == nil {
			isFocused = true
		}
	}

	private func updateAddressFromURL() {
		addressText = BrowserAddress.displayString(
			for: browser.selectedTab?.activeController?.url,
			style: addressDisplayStyle,
			isEditing: isFocused
		)
	}

	private func submitAddress() {
		guard let destination = BrowserAddress.destination(for: addressText) else { return }
		browser.selectedTab?.activeController?.load(destination)
		addressText = BrowserAddress.displayString(for: destination, style: addressDisplayStyle, isEditing: false)
		isFocused = false
	}
}
