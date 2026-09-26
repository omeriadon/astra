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
						LinearGradient(colors: [
							.black.mix(with: .white, by: 0.25),
							.black,
						], startPoint: .top, endPoint: .bottom)

						BrowserUpdateArtwork()

						Text("Update Available")
							.padding()
							.bold()
							.font(.title)
							.frame(
								maxWidth: .infinity,

								maxHeight: .infinity,

								alignment: .topLeading
							)

						VStack {
							Spacer()

							ZStack {
								if let update = updates.update {
									if

										let version = Bundle.main.releaseVersionNumber,

										let build = Bundle.main.buildNumber

									{
										HStack(spacing: 20) {
											Text(
												"\(version) \(Text("(\(build))").foregroundStyle(.tertiary))"
											)
											.foregroundStyle(.secondary)

											Image(systemName: "arrow.right")

											Text(
												"\(update.version) \(Text("(\(update.build))").foregroundStyle(.secondary))"
											)
											.bold()
										}
										.font(.title)

									} else {
										Text(
											"\(update.version) \(Text("(\(update.build))").foregroundStyle(.tertiary))"
										)
									}
								}
							}
							.padding(.top, 60)

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

							Spacer()

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
									.keyboardShortcut(.escape)
									.buttonStyle(.glass)
									.accessibilityIdentifier("update-later")

									if let update = updates.update {
										if update.isInformationOnly,

										   let infoURL = update.infoURL

										{
											Button(role: .confirm) {
												openURL(infoURL)

												updates.choose(.dismiss)

											} label: {
												Label(
													"View Update",

													systemImage: "arrow.up.right.square"
												)
											}
											.buttonStyle(.glassProminent)
											.accessibilityIdentifier("view-update")

										} else if !update.isInformationOnly {
											Button(role: .confirm) {
												updates.choose(.install)

											} label: {
												Label(
													"Install Update",

													systemImage: "arrow.down.circle"
												)
											}
											.keyboardShortcut(.return)
											.buttonStyle(.glassProminent)
											.accessibilityIdentifier("install-update")
										}
									}

								} else if case .ready = updates.status {
									Button(role: .cancel) {
										updates.dismiss()
									}
									.keyboardShortcut(.escape)
									.accessibilityIdentifier("update-later")

									Button(role: .confirm) {
										updates.choose(.install)

									} label: {
										Label(
											"Install and Relaunch",

											systemImage: "arrow.clockwise"
										)
									}
									.buttonStyle(.glassProminent)
									.accessibilityIdentifier("install-and-relaunch")

								} else if case .installing = updates.status {
									EmptyView()

								} else {
									Button(role: .cancel) {
										updates.dismiss()
									}
									.keyboardShortcut(.escape)
									.buttonStyle(.glass)
									.accessibilityIdentifier("dismiss-update-status")
								}
							}
							.padding()
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
		.ignoresSafeArea()
		.frame(width: 669, height: 415)
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
				.available,
			]

			var index = 0

			while !Task.isCancelled {
				updates.showPreview(statuses[index])

				try? await Task.sleep(for: .seconds(2))

				index = (index + 1) % statuses.count
			}
		}
}
