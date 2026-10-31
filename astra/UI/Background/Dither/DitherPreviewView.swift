#if os(macOS)
	import AppKit
	import QuartzCore
	import SwiftUI

	final class DitherPreviewView: NSView {
		static let displayAspectRatio: CGFloat = 16.0 / 9.0

		private let metalLayer = CAMetalLayer()
		private var renderer: DitherMetalRenderer?
		private var timer: Timer?
		private var configuration = DitherConfiguration()
		private var hasConfiguration = false
		private var renderInputs = DitherRenderInputs.empty
		private weak var pointerInput: DitherPointerInput?
		private var motion = DitherMotion()
		private var isActive = false
		var scalesCellsForPreview = true
		private(set) var lastRenderError: String?
		private(set) var renderedFrames = 0

		override init(frame frameRect: NSRect) {
			super.init(frame: frameRect)
			wantsLayer = true
			metalLayer.pixelFormat = .bgra8Unorm
			metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
			metalLayer.framebufferOnly = true
			metalLayer.contentsGravity = .resizeAspect
			metalLayer.isOpaque = false
			metalLayer.backgroundColor = NSColor.clear.cgColor
			metalLayer.cornerRadius = 16
			metalLayer.masksToBounds = true
			layer = metalLayer
			do {
				renderer = try DitherMetalRenderer()
			} catch {
				lastRenderError = error.localizedDescription
				NSLog("Astra Dither: Metal initialization failed: %@", error.localizedDescription)
			}
			metalLayer.device = renderer?.device
			setAccessibilityElement(true)
			setAccessibilityRole(.image)
			setAccessibilityLabel("Live dither preview")
		}

		required init?(coder: NSCoder) {
			super.init(coder: coder)
		}

		func setConfiguration(_ configuration: DitherConfiguration) {
			let boundedConfiguration = configuration.bounded()
			guard !hasConfiguration || self.configuration != boundedConfiguration else { return }
			hasConfiguration = true
			if self.configuration.topBlur != boundedConfiguration.topBlur {
				do {
					renderer = try DitherMetalRenderer(usesTopBlur: boundedConfiguration.topBlur)
					metalLayer.device = renderer?.device
					lastRenderError = nil
				} catch {
					lastRenderError = error.localizedDescription
					NSLog("Dither: failed to recreate renderer for top blur change: %@", error.localizedDescription)
				}
			}
			if self.configuration.intro == false && boundedConfiguration.intro {
				renderer?.restartIntro()
			}
			self.configuration = boundedConfiguration
			alphaValue = CGFloat(boundedConfiguration.opacity)
			if boundedConfiguration.disableAnimation || !boundedConfiguration.cursorInteractionEnabled {
				motion = DitherMotion()
			}
			if isActive {
				stopTimer()
				startTimerIfNeeded()
			}
			renderFrame(advance: false)
		}

		func setRenderInputs(_ inputs: DitherRenderInputs) {
			guard renderInputs != inputs else { return }
			renderInputs = inputs
			renderFrame(advance: false)
		}

		func setPointerInput(_ pointer: DitherPointerInput?) {
			guard pointerInput !== pointer else { return }
			pointerInput = pointer
			observePointerInput()
		}

		func setActive(_ active: Bool) {
			guard isActive != active else {
				return
			}
			isActive = active
			if active {
				updatePointer(pointerInput?.location)
				startTimerIfNeeded()
				renderFrame(advance: false)
			} else {
				stopTimer()
				motion = DitherMotion()
			}
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			if window == nil {
				stopTimer()
			} else {
				startTimerIfNeeded()
				renderFrame(advance: false)
			}
		}

		private func observePointerInput() {
			guard let pointerInput else { return }
			withObservationTracking {
				_ = pointerInput.location
			} onChange: { [weak self, weak pointerInput] in
				DispatchQueue.main.async {
					guard let self, let pointerInput, self.pointerInput === pointerInput else { return }
					self.updatePointer(pointerInput.location)
					self.observePointerInput()
				}
			}
		}

		private func updatePointer(_ location: CGPoint?) {
			guard isActive, window != nil, !isHiddenOrHasHiddenAncestor,
			      configuration.cursorInteractionEnabled, !configuration.disableAnimation else { return }
			motion.move(
				to: location,
				at: CACurrentMediaTime(),
				response: configuration.cursorResponse,
				fade: configuration.cursorFadeDuration
			)
			if timer?.timeInterval != renderInterval {
				stopTimer()
			}
			startTimerIfNeeded()
		}

		override func hitTest(_: NSPoint) -> NSView? {
			nil
		}

		override func viewDidHide() {
			super.viewDidHide()
			stopTimer()
		}

		override func viewDidUnhide() {
			super.viewDidUnhide()
			startTimerIfNeeded()
		}

		override func setFrameSize(_ newSize: NSSize) {
			super.setFrameSize(newSize)
			renderFrame(advance: false)
		}

		override func viewDidChangeBackingProperties() {
			super.viewDidChangeBackingProperties()
			renderFrame(advance: false)
		}

		func useDesktopPresentation() {
			scalesCellsForPreview = false
			metalLayer.cornerRadius = 0
			setAccessibilityElement(false)
		}

		private func startTimerIfNeeded() {
			guard isActive,
			      window != nil,
			      !isHiddenOrHasHiddenAncestor,
			      timer == nil,
			      renderer != nil,
			      let interval = renderInterval
			else {
				return
			}
			renderer?.seedAnimationTiming()
			let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
				MainActor.assumeIsolated {
					guard let self else {
						return
					}
					guard self.isActive, self.window != nil, !self.isHiddenOrHasHiddenAncestor else {
						self.stopTimer()
						return
					}
					self.renderFrame(advance: true)
					let nextInterval = self.renderInterval
					if nextInterval != self.timer?.timeInterval {
						self.stopTimer()
						self.startTimerIfNeeded()
					}
				}
			}
			self.timer = timer
			RunLoop.main.add(timer, forMode: .common)
		}

		private func stopTimer() {
			timer?.invalidate()
			timer = nil
			renderer?.resetAnimationTiming()
		}

		private var renderInterval: TimeInterval? {
			if !configuration.disableAnimation, configuration.cursorInteractionEnabled,
			   pointerInput?.location != nil || motion.presence(at: CACurrentMediaTime(), fade: configuration.cursorFadeDuration) > 0.001
			{
				return 1 / DitherRenderSchedulingPolicy.maximumFramesPerSecond
			}
			return DitherRenderSchedulingPolicy.interval(
				for: configuration,
				introComplete: renderer?.isIntroComplete ?? true
			)
		}

		private func renderFrame(advance: Bool) {
			guard window != nil,
			      !isHiddenOrHasHiddenAncestor,
			      bounds.width > 0,
			      bounds.height > 0,
			      let renderer
			else {
				return
			}
			let scale = window?.backingScaleFactor ?? 1
			let drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
			if metalLayer.drawableSize != drawableSize {
				metalLayer.drawableSize = drawableSize
			}
			guard let drawable = metalLayer.nextDrawable() else {
				return
			}
			do {
				var previewConfiguration = configuration
				if scalesCellsForPreview, let screenWidth = window?.screen?.frame.width, screenWidth > 0 {
					previewConfiguration.pixelSize *= Float(bounds.width / screenWidth)
				}
				var frameInputs = renderInputs
				frameInputs.cursorTrail = []
				frameInputs.cursorPresence = 0
				if configuration.cursorInteractionEnabled, !configuration.disableAnimation {
					let now = CACurrentMediaTime()
					let values = motion.trail(at: now, duration: configuration.cursorTrailDuration, fade: configuration.cursorFadeDuration)
					if values.count >= 3 {
						frameInputs.cursorTrail = stride(from: 0, through: 7, by: 1).map { index in
							let offset = index * 3
							return values.count >= offset + 3
								? SIMD3<Float>(values[offset], values[offset + 1], values[offset + 2])
								: .zero
						}
						frameInputs.cursorPresence = Float(motion.presence(at: now, fade: configuration.cursorFadeDuration))
					}
				}
				try renderer.render(to: drawable, size: bounds.size, configuration: previewConfiguration, inputs: frameInputs, advance: advance)
				renderedFrames += 1
				lastRenderError = nil
			} catch {
				lastRenderError = error.localizedDescription
				NSLog("Dither: preview render failed: %@", String(describing: error))
			}
		}
	}

	struct DitherNativeSurface: NSViewRepresentable {
		let configuration: DitherConfiguration
		let inputs: DitherRenderInputs
		let pointer: DitherPointerInput?
		let isActive: Bool

		func makeNSView(context _: Context) -> DitherPreviewView {
			let view = DitherPreviewView(frame: .zero)
			view.useDesktopPresentation()
			view.setConfiguration(configuration)
			view.setRenderInputs(inputs)
			view.setPointerInput(pointer)
			view.setActive(isActive)
			return view
		}

		func updateNSView(_ view: DitherPreviewView, context _: Context) {
			view.setConfiguration(configuration)
			view.setRenderInputs(inputs)
			view.setPointerInput(pointer)
			view.setActive(isActive)
		}

		static func dismantleNSView(_ view: DitherPreviewView, coordinator _: ()) {
			view.setActive(false)
			view.setPointerInput(nil)
		}
	}

#endif
