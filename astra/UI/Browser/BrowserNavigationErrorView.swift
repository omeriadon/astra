import SwiftUI

struct BrowserNavigationErrorView: View {
	let kind: BrowserNavigationFailure.Kind
	let refresh: () -> Void

	var body: some View {
		ContentUnavailableView {
			Label {
				Text(kind.title)
			} icon: {
				Image(systemName: kind.systemImage)
			}
		} description: {
			Text(kind.description)
		} actions: {
			Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
				.buttonStyle(.glassProminent)
				.accessibilityLabel("Refresh Page")
				.accessibilityIdentifier("retry-failed-page")
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
