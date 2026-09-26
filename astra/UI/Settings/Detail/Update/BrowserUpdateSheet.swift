import Sparkle
import SwiftUI

struct BrowserUpdateSheet: View {
	let updates: UpdateManager

	@Environment(\.openURL) private var openURL

	@State private var pulsing1 = false
	@State private var pulsing2 = false
	@State private var pulsing3 = false
	@State private var pulsing4 = false
	@State private var pulsing5 = false
	@State private var pulsing6 = false

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

						GeometryReader { geo in
							let width = geo.size.width
							let height = geo.size.height

							ZStack {
								// small background

								RoundedStar(
									cornerRadius: 10,
									innerRadius: 0.32
								)
								.fill(.white.opacity(0.5).gradient)
								.frame(
									width: 100,
									height: 100
								)
								.rotationEffect(.degrees(pulsing3 ? -5 : 5))
								.position(
									x: width * 0.3,
									y: height * 0.30
								)

								// purple arc

								VStack {}
									.frame(maxWidth: .infinity, maxHeight: .infinity)
									.glassEffect(.clear.tint(
										Color(red: 0.64, green: 0.69, blue: 0.9)
									).interactive(), in: PurpleHeaderShape())

								// MARK: Large main star

								RoundedStar(
									cornerRadius: 10,
									innerRadius: 0.32
								)
								.fill(.white.gradient)
								.frame(
									width: 150,
									height: 150
								)
								.position(
									x: width * 0.8,
									y: height * 0.30
								)

								// small

								RoundedStar(
									cornerRadius: 10,
									innerRadius: 0.32
								)
								.fill(.white.gradient)
								.frame(
									width: 20,
									height: 20
								)
								.rotationEffect(.degrees(pulsing1 ? -5 : 5))
								.position(
									x: width * 0.1,
									y: height * 0.5
								)
								.opacity(pulsing1 ? 0.7 : 1.0)
								.onAppear {
									withAnimation(
										.easeInOut(duration: 1.5)
											.repeatForever(autoreverses: true)
									) {
										pulsing1 = true
									}
								}

								RoundedStar(
									cornerRadius: 10,
									innerRadius: 0.32
								)
								.fill(.white.gradient)
								.frame(
									width: 10,
									height: 10
								)
								.scaleEffect(pulsing2 ? 1.1 : 1.0)
								.position(
									x: width * 0.5,
									y: height * 0.9
								)
								.opacity(pulsing2 ? 0.5 : 1.0)
								.onAppear {
									withAnimation(
										.easeInOut(duration: 1.6)
											.repeatForever(autoreverses: true)
									) {
										pulsing2 = true
									}
								}

								RoundedStar(
									cornerRadius: 10,
									innerRadius: 0.32
								)
								.fill(.white.gradient)
								.frame(
									width: 15,
									height: 15
								)
								.scaleEffect(pulsing3 ? 1.1 : 1.0)
								.rotationEffect(.degrees(pulsing3 ? -5 : 5))
								.position(
									x: width * 0.9,
									y: height * 0.8
								)
								.opacity(pulsing3 ? 0.5 : 1.0)
								.onAppear {
									withAnimation(
										.easeInOut(duration: 1.2)
											.repeatForever(autoreverses: true)
									) {
										pulsing3 = true
									}
								}

								RoundedStar(
									cornerRadius: 10,
									innerRadius: 0.32
								)
								.fill(.white.gradient)
								.frame(
									width: 30,
									height: 30
								)
								.scaleEffect(pulsing4 ? 1.2 : 1.0)
								.position(
									x: width * 0.6,
									y: height * 0.7
								)
								.opacity(pulsing4 ? 0.3 : 1.0)
								.onAppear {
									withAnimation(
										.easeInOut(duration: 1.4)
											.repeatForever(autoreverses: true)
									) {
										pulsing4 = true
									}
								}

								RoundedStar(
									cornerRadius: 10,
									innerRadius: 0.32
								)
								.fill(.white.gradient)
								.frame(
									width: 20,
									height: 20
								)
								.position(
									x: width * 0.25,
									y: height * 0.8
								)
								.opacity(pulsing5 ? 0.7 : 1.0)
								.onAppear {
									withAnimation(
										.easeInOut(duration: 1.9)
											.repeatForever(autoreverses: true)
									) {
										pulsing5 = true
									}
								}
							}
						}

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
												"\(update.version) \(Text("(\(update.build))").foregroundStyle(.tertiary))"
											)
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
