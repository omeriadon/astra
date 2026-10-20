import SwiftUI

struct BrowserNavigationErrorView: View {
	let kind: BrowserNavigationFailure.Kind
	let failedURL: URL?
	let refresh: () -> Void
	@State private var isConnected: Bool?
	@Environment(\.colorScheme) private var colorScheme

	init(kind: BrowserNavigationFailure.Kind, failedURL: URL? = nil, refresh: @escaping () -> Void) {
		self.kind = kind
		self.failedURL = failedURL
		self.refresh = refresh
	}

	var body: some View {
		ContentUnavailableView {
			Label {
				Text(kind.title)
			} icon: {
				Image(systemName: kind.systemImage)
			}
		} description: {
			VStack(spacing: 6) {
				Text(kind.description)
				if let origin = failedURL.flatMap(BrowserSitePermissions.origin(for:)) {
					Text("Failed destination: \(origin)")
						.accessibilityIdentifier("failed-page-origin")
				} else if failedURL?.isFileURL == true {
					Text("Failed destination: Local file")
						.accessibilityIdentifier("failed-page-origin")
				}
			}
		} actions: {
			Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
				.buttonStyle(.glassProminent)
				.accessibilityLabel("Refresh Page")
				.accessibilityIdentifier("retry-failed-page")
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background((colorScheme == .dark ? Color.black : .white).opacity(0.45))
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
