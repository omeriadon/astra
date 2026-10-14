#if os(macOS)
	import AppKit
	import CoreImage
	import QuartzCore

	/// Controls the real AppKit window buttons, including their action and hit testing.
	/// Each browser window keeps one animator so interrupted fades retain their progress.
	@MainActor
	final class BrowserWindowTrafficLightAnimator {
		private static let duration: TimeInterval = 0.2
		private static let maximumBlur: CGFloat = 4
		private static let filterName = "astraTrafficLightBlur"
		private static let blurKeyPath = "filters.astraTrafficLightBlur.inputRadius"
		private static let animationKey = "astra.traffic-light.blur"

		private weak var trackedWindow: NSWindow?
		private var targetHidden: Bool?
		private var generation = 0
		private var isAnimating = false
		private var trackedButtonIDs: [ObjectIdentifier] = []

		func setHidden(_ hidden: Bool, in window: NSWindow?, animated: Bool = true, reduceMotion: Bool = false) {
			guard let window else { return }
			let isNewWindow = trackedWindow !== window
			let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
				.compactMap { window.standardWindowButton($0) }
			guard !buttons.isEmpty else { return }
			let currentButtonIDs = buttons.map(ObjectIdentifier.init)
			let buttonsChanged = isNewWindow || currentButtonIDs != trackedButtonIDs
			if buttonsChanged {
				trackedWindow = window
				trackedButtonIDs = currentButtonIDs
				targetHidden = nil
				isAnimating = false
			}
			let shouldAnimate = animated && !reduceMotion && window.isVisible
			// Ignore duplicate SwiftUI notifications, but reinitialize any
			// controls AppKit recreates during a window style/fullscreen change.
			// Reduced Motion can also finish an in-flight transition immediately.
			if !buttonsChanged, targetHidden == hidden, (shouldAnimate || !isAnimating) {
				return
			}

			targetHidden = hidden
			generation &+= 1
			let currentGeneration = generation

			guard shouldAnimate else {
				isAnimating = false
				for button in buttons {
					removeBlur(from: button)
					button.alphaValue = hidden ? 0 : 1
					button.isHidden = hidden
					button.isEnabled = !hidden
				}
				return
			}

			isAnimating = true
			for button in buttons {
				// Keep the standard buttons in the hierarchy until the fade ends.
				// A fresh reveal begins blurred, and a hide starts sharp.
				animateBlur(
					on: button,
					to: hidden ? Self.maximumBlur : 0,
					defaultStart: hidden ? 0 : Self.maximumBlur
				)
				button.isHidden = false
				// Keep native traffic-light colours while fading. Disabling
				// before the fade finishes makes AppKit redraw them as grey.
				button.isEnabled = true
			}

			NSAnimationContext.runAnimationGroup { context in
				context.duration = Self.duration
				context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
				for button in buttons {
					button.animator().alphaValue = hidden ? 0 : 1
				}
			} completionHandler: {
				Task { @MainActor [weak self, weak window] in
					guard let self,
					      self.generation == currentGeneration,
					      self.trackedWindow === window else { return }
					self.isAnimating = false
					for button in buttons {
						button.alphaValue = hidden ? 0 : 1
						button.isHidden = hidden
						button.isEnabled = !hidden
						self.removeBlur(from: button)
					}
				}
			}
		}

		private func animateBlur(on button: NSButton, to target: CGFloat, defaultStart: CGFloat) {
			// Native titlebar controls normally have backing layers. If they
			// do not, enable a backing layer rather than replacing the buttons.
			if button.layer == nil {
				button.wantsLayer = true
			}
			guard let layer = button.layer else { return }
			button.layerUsesCoreImageFilters = true

			// Read the in-flight presentation value before cancelling it.
			// This prevents a blur jump when the pointer changes direction.
			let previousValue: CGFloat? = if layer.animation(forKey: Self.animationKey) != nil {
				Self.blurValue(layer.presentation()?.value(forKeyPath: Self.blurKeyPath))
			} else {
				nil
			}
			layer.removeAnimation(forKey: Self.animationKey)

			if !(layer.filters ?? []).contains(where: { ($0 as? CIFilter)?.name == Self.filterName }) {
				guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
				filter.name = Self.filterName
				filter.setValue(defaultStart, forKey: kCIInputRadiusKey)
				layer.filters = (layer.filters ?? []) + [filter]
			}
			let initial = previousValue ?? defaultStart

			// Core Animation requires changing an attached CIFilter through
			// the layer's named key path, not by mutating the filter directly.
			CATransaction.begin()
			CATransaction.setDisableActions(true)
			layer.setValue(target, forKeyPath: Self.blurKeyPath)
			CATransaction.commit()

			let animation = CABasicAnimation(keyPath: Self.blurKeyPath)
			animation.fromValue = initial
			animation.toValue = target
			animation.duration = Self.duration
			animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
			layer.add(animation, forKey: Self.animationKey)
		}

		private func removeBlur(from button: NSButton) {
			guard let layer = button.layer else { return }
			layer.removeAnimation(forKey: Self.animationKey)
			let filters = layer.filters ?? []
			guard filters.contains(where: { ($0 as? CIFilter)?.name == Self.filterName }) else { return }
			layer.filters = filters.filter { ($0 as? CIFilter)?.name != Self.filterName }
		}

		private static func blurValue(_ value: Any?) -> CGFloat? {
			(value as? NSNumber).map { CGFloat(truncating: $0) }
		}
	}
#endif
