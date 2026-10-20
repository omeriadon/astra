#if os(macOS)
	import AppKit

	extension NSWindow {
		func setBrowserMinimumContentWidth(_ requiredWidth: CGFloat) {
			let screenFrame = screen?.visibleFrame
			let minimumWidth = min(requiredWidth, screenFrame?.width ?? requiredWidth)
			contentMinSize.width = minimumWidth
			guard !styleMask.contains(.fullScreen) else { return }
			let contentWidth = contentRect(forFrameRect: frame).width
			let targetWidth = max(minimumWidth, min(contentWidth, screenFrame?.width ?? contentWidth))
			guard contentWidth != targetWidth else { return }
			var nextFrame = frame
			nextFrame.size.width += targetWidth - contentWidth
			if let screenFrame {
				nextFrame.origin.x = max(screenFrame.minX, min(nextFrame.minX, screenFrame.maxX - nextFrame.width))
			}
			// Establish space before SwiftUI reveals a pane; setFrame does not enforce contentMinSize.
			setFrame(nextFrame, display: true)
		}
	}

	final class BrowserContentHostView: NSView {
		init(hostingView: NSView) {
			super.init(frame: .zero)

			hostingView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(hostingView)

			NSLayoutConstraint.activate([
				hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
				hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
				hostingView.topAnchor.constraint(equalTo: topAnchor),
				hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
			])

			#if DEBUG
				assert(
					responds(to: NSSelectorFromString("_opaqueRectForWindowMoveWhenInTitlebar")),
					"AppKit titlebar drag override is not visible to Objective-C"
				)
			#endif
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) is unavailable")
		}

		override var mouseDownCanMoveWindow: Bool {
			false
		}

		/// NSWindowStyleMaskFullSizeContentView normally lets AppKit force
		/// titlebar-overlapping content into the native window-drag region even
		/// when mouseDownCanMoveWindow is false. Firefox, Chromium, and Zed use
		/// this private selector to mark app-owned titlebar content as opaque to
		/// that drag-region calculation.
		///
		/// Returning the entire host bounds disables AppKit's implicit titlebar
		/// dragging across Astra. Explicit WindowDragBackground views still move
		/// the window with NSWindow.performDrag(with:).
		@objc(_opaqueRectForWindowMoveWhenInTitlebar)
		func opaqueRectForWindowMoveWhenInTitlebar() -> NSRect {
			bounds
		}
	}
#endif
