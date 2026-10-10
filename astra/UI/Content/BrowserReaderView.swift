import Defaults
import SwiftUI
import WebKit

struct BrowserReaderView: View {
	let controller: BrowserController
	let html: String
	@Default(.readerAppearance) private var appearance
	@State private var showsAppearance = false
	@Namespace private var transitions

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Label("Reader", systemImage: "doc.text")
					.font(.headline)
				Spacer()
				Button("Reader Appearance", systemImage: "textformat") {
					showsAppearance = true
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.glass)
				.accessibilityLabel("Reader Appearance")
				.accessibilityIdentifier("browser-reader-appearance")
				.matchedTransitionSource(id: "reader-appearance", in: transitions)
				.sheet(isPresented: $showsAppearance) {
					BrowserReaderAppearanceView()
					#if os(iOS)
						.navigationTransition(.zoom(sourceID: "reader-appearance", in: transitions))
					#endif
						.presentationDetents([.fraction(0.65), .large])
				}
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
			BrowserReaderWebView(controller: controller, html: html, appearance: appearance)
				.accessibilityIdentifier("browser-reader-content")
		}
		.background(.background)
		.accessibilityIdentifier("browser-reader")
	}
}
