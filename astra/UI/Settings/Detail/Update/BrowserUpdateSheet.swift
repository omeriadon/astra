import Sparkle
import SwiftUI

struct BrowserUpdateSheet: View {
	let updates: UpdateManager
	@Environment(\.openURL) private var openURL

	var body: some View {
		VStack {
			switch updates.status {
				case .checking:
					Section {
						ProgressView("Checking for updates…")
					}

				case .available, .downloading, .preparing, .ready, .installing:
					ZStack {
						GeometryReader { geo in
							// Small stars
							SparkleShape()
								.fill(.white.opacity(0.85))
								.frame(width: 22, height: 22)
								.rotationEffect(.degrees(8))
								.position(
									x: geo.size.width * 0.23,
									y: geo.size.height * 0.40
								)

							SparkleShape()
								.fill(.white.opacity(0.85))
								.frame(width: 14, height: 14)
								.rotationEffect(.degrees(-12))
								.position(
									x: geo.size.width * 0.31,
									y: geo.size.height * 0.43
								)

							SparkleShape()
								.fill(.white.opacity(0.85))
								.frame(width: 16, height: 16)
								.position(
									x: geo.size.width * 0.44,
									y: geo.size.height * 0.42
								)

							SparkleShape()
								.fill(.white.opacity(0.72))
								.frame(width: 18, height: 18)
								.scaleEffect(x: 0.85, y: 1.15)
								.position(
									x: geo.size.width * 0.18,
									y: geo.size.height * 0.35
								)

							PurpleHeaderShape()
								.fill(
									LinearGradient(
										colors: [
											Color(red: 0.39, green: 0.43, blue: 0.86),
											Color(red: 0.29, green: 0.31, blue: 0.66),
										],
										startPoint: .top,
										endPoint: .bottom
									)
								)
								.frame(maxWidth: .infinity)
								.frame(height: geo.size.height * 0.5)

							// Big star
							SparkleShape()
								.fill(.white.opacity(0.9))
								.frame(width: 46, height: 46)
								.position(
									x: geo.size.width * 0.50,
									y: geo.size.height * 0.20
								)
						}

						Text("Update Available")
							.padding()
							.font(.title)
							.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

						VStack {
							if let update = updates.update {
								if let version = Bundle.main.releaseVersionNumber,
								   let build = Bundle.main.buildNumber
								{
									HStack(spacing: 20) {
										Text("\(version) \(Text("(\(build))").foregroundStyle(.tertiary))")
											.foregroundStyle(.secondary)

										Image(systemName: "arrow.right")

										Text("\(update.version) \(Text("(\(update.build))").foregroundStyle(.tertiary))")
									}
									.font(.title)
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
					.buttonStyle(.glass)
					.accessibilityIdentifier("skip-update")

					Spacer()

					Button(role: .cancel) {
						updates.dismiss()
					}
					.buttonStyle(.glass)
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
					.buttonStyle(.glass)
					.accessibilityIdentifier("dismiss-update-status")
				}
			}
			.padding()
		}
		.ignoresSafeArea()
		.presentationSizing(.fitted)
		.interactiveDismissDisabled()
		.monospaced()
	}
}

#Preview {
	@Previewable @State var updates = UpdateManager()

	BrowserUpdateSheet(updates: updates)
		.task {
			let statuses: [UpdateManager.Status] = [
				//				.checking,
				.available,
//				.downloading,
//				.preparing,
//				.ready,
//				.installing,
//				.message("No updates available."),
			]
			var index = 0

			while !Task.isCancelled {
				updates.showPreview(statuses[index])
				try? await Task.sleep(for: .seconds(2))
				index = (index + 1) % statuses.count
			}
		}
}
