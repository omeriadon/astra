import SwiftUI
import WebKit

struct BrowserReaderView: View {
	let controller: BrowserController
	let html: String

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Label("Reader", systemImage: "doc.text")
					.font(.headline)
				Spacer()
				Button("Hide Reader", systemImage: "xmark") {
					controller.toggleReader()
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.glass)
				.accessibilityLabel("Hide Reader")
				.accessibilityIdentifier("browser-reader-close")
			}
			.padding(12)
			Divider()
			BrowserReaderWebView(controller: controller, html: html)
				.accessibilityIdentifier("browser-reader-content")
		}
		.background(.background)
		.accessibilityIdentifier("browser-reader")
	}
}
