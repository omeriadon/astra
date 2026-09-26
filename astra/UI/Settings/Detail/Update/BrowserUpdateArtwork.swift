#if os(iOS)
	import UIKit
#elseif os(macOS)
	import AppKit
#endif

import SwiftUI

private struct GlassStarContent: View {
	let tintColor: Color
	let interactive: Bool

	var body: some View {
		VStack {}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.glassEffect(
				interactive ? .clear.tint(tintColor).interactive() : .clear.tint(tintColor),
				in: Rectangle()
			)
			.mask {
				Image(systemName: "sparkle")
					.resizable()
					.scaledToFit()
			}
			.accessibilityHidden(true)
	}
}

#if os(iOS)
	private struct GlassStar: UIViewRepresentable {
		let tintColor: Color
		var interactive = true

		func makeUIView(context _: Context) -> GlassStarHostingView {
			GlassStarHostingView(
				rootView: GlassStarContent(
					tintColor: tintColor,
					interactive: interactive
				)
			)
		}

		func updateUIView(_ uiView: GlassStarHostingView, context _: Context) {
			uiView.rootView = GlassStarContent(
				tintColor: tintColor,
				interactive: interactive
			)
		}
	}

	private final class GlassStarHostingView: UIView {
		private let hostingController: UIHostingController<GlassStarContent>

		var rootView: GlassStarContent {
			get { hostingController.rootView }
			set { hostingController.rootView = newValue }
		}

		init(rootView: GlassStarContent) {
			hostingController = UIHostingController(rootView: rootView)
			super.init(frame: .zero)

			backgroundColor = .clear
			hostingController.view.backgroundColor = .clear
			hostingController.view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(hostingController.view)

			NSLayoutConstraint.activate([
				hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
				hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
				hostingController.view.topAnchor.constraint(equalTo: topAnchor),
				hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
			])
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}
	}
#elseif os(macOS)
	private struct GlassStar: NSViewRepresentable {
		let tintColor: Color
		var interactive = true

		func makeNSView(context _: Context) -> NSHostingView<GlassStarContent> {
			NSHostingView(
				rootView: GlassStarContent(
					tintColor: tintColor,
					interactive: interactive
				)
			)
		}

		func updateNSView(_ nsView: NSHostingView<GlassStarContent>, context _: Context) {
			nsView.rootView = GlassStarContent(
				tintColor: tintColor,
				interactive: interactive
			)
		}
	}
#endif

struct BrowserUpdateArtwork: View {
	@State private var pulsing1 = false
	@State private var pulsing2 = false
	@State private var pulsing3 = false
	@State private var pulsing4 = false
	@State private var pulsing5 = false

	let isAboutView: Bool

	init(isAboutView: Bool = false) {
		self.isAboutView = isAboutView
	}

	var body: some View {
		GeometryReader { geo in
			let width = geo.size.width

			let height = geo.size.height

			ZStack {
				// small background

				GlassStar(
					tintColor: .white.opacity(0.5)
				)
				.frame(
					width: 100,
					height: 100
				)
				.rotationEffect(.degrees(pulsing3 ? -5 : 5))
				.position(
					x: width * (isAboutView ? 0.2 : 0.3),
					y: height * (isAboutView ? 0.2 : 0.3)
				)

				// purple arc

				VStack {
					VStack {}
						.frame(height: isAboutView ? geo.size.height * 0.7 : geo.size.height)
						.frame(maxWidth: .infinity)
						.glassEffect(.clear.tint(
							Color(red: 0.64, green: 0.69, blue: 0.9)

						).interactive(), in: PurpleHeaderShape())

					if isAboutView {
						Spacer()
					}
				}

				// MARK: Large main star

				GlassStar(
					tintColor: .white
				)
				.frame(
					width: 180,
					height: 180
				)
				.position(
					x: width * 0.8,
					y: height * (isAboutView ? 0.15 : 0.33)
				)

				// small

				GlassStar(
					tintColor: .white
				)
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

				GlassStar(
					tintColor: .white
				)
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

				GlassStar(
					tintColor: .white
				)
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

				GlassStar(
					tintColor: .white
				)
				.frame(
					width: 30,
					height: 30
				)
				.scaleEffect(pulsing4 ? 1.2 : 1.0)
				.position(
					x: width * (isAboutView ? 0.8 : 0.6),
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

				GlassStar(
					tintColor: .white
				)
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
	}
}

#Preview {
	AboutView()
}
