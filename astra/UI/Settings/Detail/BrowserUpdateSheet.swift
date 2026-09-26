import Sparkle
import SwiftUI

struct BrowserUpdateSheet: View {
	let updates: UpdateManager
	@Environment(\.openURL) private var openURL

	var body: some View {
		List {
			switch updates.status {
				case .checking:
					Section {
						ProgressView("Checking for updates…")
					}

				case .available, .downloading, .preparing, .ready, .installing:
					if let update = updates.update {
						Section("Current Version") {
							LabeledContent("Version", value: Bundle.main.releaseVersionNumber ?? "Unknown")
							LabeledContent("Build", value: Bundle.main.buildNumber ?? "Unknown")
						}

						Section("Available Update") {
							LabeledContent("Version", value: update.version)
							LabeledContent("Build", value: update.build)
						}
					}

					if case .downloading = updates.status {
						Section {
							ProgressView("Downloading update…")
						}
					} else if case .preparing = updates.status {
						Section {
							ProgressView("Preparing update…")
						}
					} else if case .installing = updates.status {
						Section {
							ProgressView("Installing update…")
						}
					}

				case let .message(message):
					Section {
						Text(message)
					}
			}
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
		.safeAreaInset(edge: .bottom) {
			HStack {
				if case .available = updates.status {
					Button("Skip This Version", systemImage: "forward.end") {
						updates.choose(.skip)
					}
					.accessibilityIdentifier("skip-update")

					Button(role: .cancel) {
						updates.dismiss()
					}
					.accessibilityIdentifier("update-later")

					if let update = updates.update {
						if update.isInformationOnly, let infoURL = update.infoURL {
							Button(role: .confirm) {
								openURL(infoURL)
								updates.choose(.dismiss)
							} label: {
								Label("View Update", systemImage: "arrow.up.right.square")
							}
							.buttonStyle(.glassProminent)
							.accessibilityIdentifier("view-update")
						} else if !update.isInformationOnly {
							Button(role: .confirm) {
								updates.choose(.install)
							} label: {
								Label("Install Update", systemImage: "arrow.down.circle")
							}
							.buttonStyle(.glassProminent)
							.accessibilityIdentifier("install-update")
						}
					}
				} else if case .ready = updates.status {
					Button(role: .cancel) {
						updates.dismiss()
					}
					.accessibilityIdentifier("update-later")

					Button(role: .confirm) {
						updates.choose(.install)
					} label: {
						Label("Install and Relaunch", systemImage: "arrow.clockwise")
					}
					.buttonStyle(.glassProminent)
					.accessibilityIdentifier("install-and-relaunch")
				} else if case .installing = updates.status {
					EmptyView()
				} else {
					Button(role: .cancel) {
						updates.dismiss()
					}
					.accessibilityIdentifier("dismiss-update-status")
				}
			}
			.padding()
		}
		.presentationDetents([.fraction(0.6)])
		.interactiveDismissDisabled()
	}
}

#Preview {
	@Previewable @State var updates = UpdateManager()

	BrowserUpdateSheet(updates: updates)
		.task {
			let statuses: [UpdateManager.Status] = [
				.checking,
				.available,
				.downloading,
				.preparing,
				.ready,
				.installing,
				.message("No updates available."),
			]
			var index = 0

			while !Task.isCancelled {
				updates.showPreview(statuses[index])
				try? await Task.sleep(for: .seconds(2))
				index = (index + 1) % statuses.count
			}
		}
}
