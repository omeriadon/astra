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

private struct AboutArtworkStar: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var pulsing = false

	let index: Int

	private var mode: Int {
		index % 3
	}

	var body: some View {
		Image(systemName: "sparkle")
			.resizable()
			.scaledToFit()
			.frame(width: CGFloat(5 + index % 4), height: CGFloat(5 + index % 4))
			.foregroundStyle(.white)
			.scaleEffect(
				mode == 0 && !reduceMotion
					? (pulsing ? 1.03 + Double(index) * 0.003 : 0.97 - Double(index) * 0.003)
					: 1
			)
			.rotationEffect(.degrees(
				mode == 1 && !reduceMotion
					? (pulsing ? 2 + Double(index) * 0.1 : -2 - Double(index) * 0.1)
					: 0
			))
			.opacity(pulsing ? 0.15 + Double(index) * 0.01 : 1)
			.animation(
				.easeInOut(duration: 0.5 + Double(index) * 0.05)
					.repeatForever(autoreverses: true),
				value: pulsing
			)
			.onAppear { pulsing = true }
			.accessibilityHidden(true)
	}
}

struct BrowserUpdateArtwork: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var localPointerLocation: CGPoint?

	private static let aboutStarPositions: [CGPoint] = [
		CGPoint(x: 0.04811, y: 0.23125),
		CGPoint(x: 0.29108, y: 0.29160),
		CGPoint(x: 0.63807, y: 0.30881),
		CGPoint(x: 0.92434, y: 0.34032),
		CGPoint(x: 0.17264, y: 0.45175),
		CGPoint(x: 0.12788, y: 0.49734),
		CGPoint(x: 0.81504, y: 0.51504),
		CGPoint(x: 0.11306, y: 0.52566),
		CGPoint(x: 0.55054, y: 0.56143),
		CGPoint(x: 0.88465, y: 0.57126),
		CGPoint(x: 0.29132, y: 0.60582),
		CGPoint(x: 0.06516, y: 0.64614),
		CGPoint(x: 0.07939, y: 0.66038),
		CGPoint(x: 0.09379, y: 0.66314),
		CGPoint(x: 0.06864, y: 0.66976),
		CGPoint(x: 0.76171, y: 0.71165),
		CGPoint(x: 0.45004, y: 0.79148),
		CGPoint(x: 0.81778, y: 0.80506),
		CGPoint(x: 0.91097, y: 0.81499),
		CGPoint(x: 0.11148, y: 0.86830),
		CGPoint(x: 0.50869, y: 0.88530),
		CGPoint(x: 0.11321, y: 0.88710),
		CGPoint(x: 0.24414, y: 0.90008),
		CGPoint(x: 0.12530, y: 0.90051),
		CGPoint(x: 0.76720, y: 0.90439),
		CGPoint(x: 0.68711, y: 0.91164),
		CGPoint(x: 0.50378, y: 0.91325),
		CGPoint(x: 0.77971, y: 0.91724),
		CGPoint(x: 0.12641, y: 0.92202),
		CGPoint(x: 0.36032, y: 0.93989),
	]

	@State private var pulsing1 = false
	@State private var pulsing2 = false
	@State private var pulsing3 = false
	@State private var pulsing4 = false
	@State private var pulsing5 = false

	let isAboutView: Bool
	let aboutPointerLocation: CGPoint?

	init(isAboutView: Bool = false, pointerLocation: CGPoint? = nil) {
		self.isAboutView = isAboutView
		aboutPointerLocation = pointerLocation
	}

	private func parallaxOffset(for starSize: CGFloat, in bounds: CGSize) -> CGSize {
		guard !reduceMotion,
		      let pointerLocation = isAboutView ? aboutPointerLocation : localPointerLocation,
		      bounds.width > 0,
		      bounds.height > 0
		else {
			return .zero
		}

		let maximumOffset = 2 + 50 / starSize
		let horizontal = min(max(pointerLocation.x / bounds.width * 2 - 1, -1), 1)
		let vertical = min(max(pointerLocation.y / bounds.height * 2 - 1, -1), 1)

		return CGSize(
			width: horizontal * maximumOffset,
			height: vertical * maximumOffset
		)
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
					y: height * (isAboutView ? 0.17 : 0.3)
				)
				.offset(parallaxOffset(for: 100, in: geo.size))

				// purple arc

				VStack {
					VStack {}
						.frame(height: isAboutView ? geo.size.height * 0.7 : geo.size.height)
						.frame(maxWidth: .infinity)
						.glassEffect(.clear.tint(
							Color(
								red: 253.2 / 255,
								green: 253.25 / 255,
								blue: 254.35 / 255
							)

						), in: PurpleHeaderShape())

					if isAboutView {
						Spacer()
					}
				}

				if isAboutView {
					ForEach(Self.aboutStarPositions.indices, id: \.self) { index in
						let point = Self.aboutStarPositions[index]

						AboutArtworkStar(index: index)
							.position(x: width * point.x, y: height * point.y)
							.offset(parallaxOffset(for: CGFloat(5 + index % 4), in: geo.size))
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
				.offset(parallaxOffset(for: 180, in: geo.size))

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
				.offset(parallaxOffset(for: 20, in: geo.size))
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
				.offset(parallaxOffset(for: 10, in: geo.size))
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
				.offset(parallaxOffset(for: 15, in: geo.size))
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
				.offset(parallaxOffset(for: 30, in: geo.size))
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
				.offset(parallaxOffset(for: 20, in: geo.size))
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
			.frame(width: width, height: height)
			.animation(
				.smooth(duration: 1),
				value: isAboutView ? aboutPointerLocation : localPointerLocation
			)
			.contentShape(Rectangle())
			.onContinuousHover { phase in
				guard !isAboutView else { return }

				switch phase {
					case let .active(location):
						localPointerLocation = location
					case .ended:
						localPointerLocation = nil
				}
			}
		}
	}
}

#Preview {
	AboutView()
}
