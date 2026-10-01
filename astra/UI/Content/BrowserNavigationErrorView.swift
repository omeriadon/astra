import SwiftUI

struct BrowserNavigationErrorView: View {
	let kind: BrowserNavigationFailure.Kind
	let refresh: () -> Void
	@State private var isConnected: Bool?

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
		.overlay(alignment: .bottom) {
			if kind == .offline, let isConnected {
				Text(isConnected ? "Internet connection is available." : "Waiting for an internet connection.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.accessibilityIdentifier("network-recovery-status")
					.padding(.bottom, 16)
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: BrowserNavigationConnectivity.didChangeNotification)) { notification in
			isConnected = notification.object as? Bool
		}
	}
}
