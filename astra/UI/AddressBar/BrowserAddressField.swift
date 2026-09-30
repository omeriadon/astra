import Defaults
import SwiftUI

struct BrowserAddressField: View {
	let browser: Browser
	@Default(.addressDisplayStyle) private var addressDisplayStyle
	@State private var addressText = ""
	@FocusState private var isFocused: Bool

	private var isDimmed: Bool {
		addressDisplayStyle == .dimmed && !isFocused && !addressText.isEmpty
	}

	private var isGoogleSearch: Bool {
		BrowserAddress.isGoogleSearchURL(browser.selectedTab?.activeController?.url)
	}

	var body: some View {
		AddressTextField(
			addressText: $addressText,
			isFocused: $isFocused,
			isDimmed: isDimmed,
			isGoogleSearch: isGoogleSearch,
			dimmedAddressText: dimmedAddressText,
			onSubmitAddress: submitAddress,
			onEscape: {
				browser.newTabSearchSelection = nil
				isFocused = false
			},
			onMoveSelection: { offset in
				guard browser.isShowingNewTab else { return false }
				browser.moveNewTabSearchSelection(by: offset)
				return true
			}
		)
		.onChange(of: addressText) { _, text in
			if browser.isShowingNewTab {
				browser.newTabSearchText = text
			}
		}
		.onChange(of: browser.newTabSearchText) { _, text in
			if browser.isShowingNewTab, addressText != text {
				addressText = text
			}
		}
		.onChange(of: browser.selectedTabID) { _, _ in
			updateForSelectedTab()
		}
		.onChange(of: browser.addressFocusRequest) { _, _ in
			isFocused = true
		}
		.onChange(of: browser.selectedTab?.peeks.last?.id) { _, _ in
			isFocused = false
			updateAddressFromURL()
		}
		.onChange(of: browser.selectedTab?.activeController?.url) { _, url in
			guard !isFocused else { return }
			let next = BrowserAddress.displayString(for: url, style: addressDisplayStyle, isEditing: false)
			guard next != addressText else { return }
			addressText = next
		}
		.onChange(of: addressDisplayStyle) { _, _ in
			updateAddressFromURL()
		}
		.onChange(of: isFocused) { _, focused in
			if browser.isShowingNewTab {
				addressText = browser.newTabSearchText
				return
			}
			addressText = BrowserAddress.displayString(
				for: browser.selectedTab?.activeController?.url,
				style: addressDisplayStyle,
				isEditing: focused
			)
		}
		.onAppear {
			updateForSelectedTab()
		}
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
		if browser.isShowingNewTab {
			addressText = browser.newTabSearchText
			return
		}
		let next = BrowserAddress.displayString(
			for: browser.selectedTab?.activeController?.url,
			style: addressDisplayStyle,
			isEditing: isFocused
		)
		guard next != addressText else { return }
		addressText = next
	}

	private func submitAddress() {
		if browser.isShowingNewTab {
			browser.newTabSearchText = addressText
			browser.submitNewTabSearch()
			isFocused = false
			updateAddressFromURL()
			return
		}
		guard let destination = BrowserAddress.destination(for: addressText) else { return }
		browser.selectedTab?.activeController?.load(destination)
		addressText = BrowserAddress.displayString(for: destination, style: addressDisplayStyle, isEditing: false)
		isFocused = false
	}
}

private struct AddressTextField: View {
	@Binding var addressText: String
	var isFocused: FocusState<Bool>.Binding
	var isDimmed: Bool
	var isGoogleSearch: Bool
	var dimmedAddressText: AttributedString
	var onSubmitAddress: () -> Void
	var onEscape: () -> Void
	var onMoveSelection: (Int) -> Bool

	var body: some View {
		TextField("Search or type a URL", text: $addressText)
			.textFieldStyle(.plain)
			.fontDesign(.monospaced)
			.lineLimit(1)
			.foregroundStyle(isDimmed ? .clear : .primary)
			.padding(.leading, isGoogleSearch ? 20 : 0)
			.focused(isFocused)
			.submitLabel(.go)
			.onSubmit(onSubmitAddress)
			.onKeyPress(.downArrow) {
				onMoveSelection(1) ? .handled : .ignored
			}
			.onKeyPress(.upArrow) {
				onMoveSelection(-1) ? .handled : .ignored
			}
			.onKeyPress(.escape) {
				onEscape()
				return .handled
			}
			.overlay(alignment: .leading) {
				DimmedAddressOverlay(
					isGoogleSearch: isGoogleSearch,
					isDimmed: isDimmed,
					dimmedAddressText: dimmedAddressText
				)
			}
			.accessibilityLabel("Address")
			.accessibilityIdentifier("browser-address")
	}
}

private struct DimmedAddressOverlay: View {
	var isGoogleSearch: Bool
	var isDimmed: Bool
	var dimmedAddressText: AttributedString

	var body: some View {
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
}
