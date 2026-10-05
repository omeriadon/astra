#if os(macOS)
	import SwiftUI

	struct BrowserLinkPreview: View {
		let url: URL

		var body: some View {
			Text(verbatim: url.absoluteString)
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
