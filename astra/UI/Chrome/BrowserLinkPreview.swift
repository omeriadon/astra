#if os(macOS)
	import Defaults
	import SwiftUI

	struct BrowserLinkPreview: View {
		let url: URL
		var isPrivate = false
		@Default(.addressDisplayStyle) private var displayStyle
		@Default(.browserSearchConfiguration) private var searchConfigurationValue

		private var addressText: AttributedString {
			let configuration = BrowserSearchConfiguration.decode(searchConfigurationValue)
			let value = BrowserAddress.displayString(for: url, style: displayStyle, isEditing: false, configuration: configuration, isPrivate: isPrivate)
			var text = AttributedString(value)
			if displayStyle == .dimmed {
				text.foregroundColor = Color.primary.opacity(0.65)
				for range in BrowserAddress.primaryTextRanges(for: url, displayedText: value, configuration: configuration, isPrivate: isPrivate) {
					if let attributedRange = Range(range, in: text) {
						text[attributedRange].foregroundColor = .primary
					}
				}
			}
			return text
		}

		var body: some View {
			Text(addressText)
				.font(.caption.monospaced())
				.lineLimit(1)
				.truncationMode(.middle)
				.padding(.horizontal, 8)
				.padding(.vertical, 5)
				.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
				.accessibilityLabel("Link destination: \(url.absoluteString)")
				.accessibilityIdentifier("hovered-link-destination")
		}
	}
#endif
