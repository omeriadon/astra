import Defaults
import SwiftUI
import WebKit

struct PeekOverlayView: View {
	let request: PeekRequest
	let availableSize: CGSize
	let onDismiss: () -> Void
	let onNewWindow: (URL, CGPoint, Int) -> Void

	@State private var controller: BrowserController
	@State private var isPresented = false

	init(
		request: PeekRequest,
		availableSize: CGSize,
		onDismiss: @escaping () -> Void,
		onNewWindow: @escaping (URL, CGPoint, Int) -> Void
	) {
		self.request = request
		self.availableSize = availableSize
		self.onDismiss = onDismiss
		self.onNewWindow = onNewWindow
		_controller = State(initialValue: BrowserController(initialURL: request.url))
	}

	private var size: CGSize {
		let ratio: CGFloat = request.depth == 1 ? 0.78 : 0.68
		return CGSize(
			width: min(920, availableSize.width * ratio),
			height: min(720, availableSize.height * ratio)
		)
	}

	private var sourcePoint: CGPoint {
		CGPoint(
			x: min(max(request.point.x, 0), availableSize.width),
			y: min(max(request.point.y, 0), availableSize.height)
		)
	}

	var body: some View {
		let center = CGPoint(x: availableSize.width / 2, y: availableSize.height / 2)
		let startOffset = CGSize(
			width: sourcePoint.x - center.x,
			height: sourcePoint.y - center.y
		)

		ZStack {
			Color.black.opacity(request.depth == 1 ? 0.36 : 0.48)
				.ignoresSafeArea()

			BrowserWebView(controller: controller)
				.clipShape(RoundedRectangle(cornerRadius: 14))
				.shadow(color: .black.opacity(0.38), radius: 30, y: 16)
				.overlay(alignment: .topTrailing) {
					Button(action: dismiss) {
						Label("Close Peek", systemImage: "xmark")
							.labelStyle(.iconOnly)
					}
					.padding(12)
					.accessibilityIdentifier("close-peek")
				}
		}
		.frame(width: size.width, height: size.height)
		.scaleEffect(isPresented ? 1 : 0.04)
		.offset(isPresented ? .zero : startOffset)
		.animation(.smooth(duration: 0.42), value: isPresented)
		.onAppear {
			controller.newWindowRequested = { url, point in
				let origin = CGPoint(
					x: (availableSize.width - size.width) / 2,
					y: (availableSize.height - size.height) / 2
				)
				onNewWindow(
					url,
					CGPoint(x: point.x + origin.x, y: point.y + origin.y),
					request.depth + 1
				)
			}
			if request.depth == 2, Defaults[.secondPeekUses105PercentZoom] {
				controller.webView.pageZoom = 1.05
			}
			isPresented = true
		}
	}

	private func dismiss() {
		withAnimation(.smooth(duration: 0.32)) {
			isPresented = false
		}
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(320))
			onDismiss()
		}
	}
}
