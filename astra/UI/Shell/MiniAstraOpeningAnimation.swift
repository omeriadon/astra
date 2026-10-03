#if os(macOS)
	import AppKit
	import QuartzCore

	@MainActor
	enum MiniAstraOpeningAnimation {
		static func show(
			_ window: NSWindow,
			from cursor: NSPoint,
			completion: @escaping @MainActor @Sendable () -> Void
		) {
			let destination = window.frame
			let size = NSSize(width: destination.width * 0.08, height: destination.height * 0.08)
			let origin = NSRect(
				x: cursor.x - size.width / 2,
				y: cursor.y - size.height / 2,
				width: size.width,
				height: size.height
			)
			let animationBehavior = window.animationBehavior
			let ignoresMouseEvents = window.ignoresMouseEvents
			window.animationBehavior = .none
			window.ignoresMouseEvents = true
			window.alphaValue = 0
			window.setFrame(origin, display: false)
			window.makeKeyAndOrderFront(nil)
			window.orderFrontRegardless()

			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.25
				context.timingFunction = CAMediaTimingFunction(name: .easeOut)
				window.animator().setFrame(destination, display: true)
				window.animator().alphaValue = 1
			} completionHandler: {
				Task { @MainActor in
					window.animationBehavior = animationBehavior
					window.ignoresMouseEvents = ignoresMouseEvents
					completion()
				}
			}
		}
	}
#endif
