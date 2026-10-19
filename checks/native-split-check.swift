// Compile with BrowserSplitView.swift + BrowserChromeMetrics.swift on macOS.
// Exercises production native layout and compares every frame against the old
// SwiftUI split's geometry, without booting a browser session or WebKit.
import AppKit
import SwiftUI

@MainActor
private enum Probe {
	static var appearances = 0
	static var identities: Set<UUID> = []
	static func pulse(_ view: NSView) {
		view.layoutSubtreeIfNeeded()
		RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
		view.layoutSubtreeIfNeeded()
	}
}

@MainActor
private struct StatefulPane: View {
	@State private var identity = UUID()
	var body: some View {
		let _ = Probe.identities.insert(identity)
		Text("Preserved state")
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.onAppear { Probe.appearances += 1 }
	}
}

@main
struct NativeSplitCheck {
	@MainActor static func main() {
		geometryParity()
		stateChecks()
		nativeLayoutChecks()
		print("Native split geometry parity, release-only publication and hosted state checks passed")
	}

	@MainActor private static func configuration(leading: Bool = true) -> BrowserNativeSplitConfiguration {
		.init(preferredWidth: leading ? 224 : 364,
		      limits: leading ? 168 ... 330 : 300 ... 600,
		      minimumContentWidth: 600, leading: leading, overlaysContent: false,
		      shown: true, visibility: 1, reservation: 1)
	}

	/// Reference coordinates are copied from the previous GeometryReader/ZStack
	/// implementation. Exercise fractional animation widths as well as settled UI.
	@MainActor private static func geometryParity() {
		for leading in [true, false] {
			for available in [0, 100, 168, 300, 767, 768, 899, 900, 1024, 1280, 1600] as [CGFloat] {
				for height in [480, 800.5] as [CGFloat] {
					for visibility in [0, 0.125, 0.5, 0.999, 1] as [CGFloat] {
						for overlay in [true, false] {
							for preferred in [100, 168, 224, 364, 600, 900] as [CGFloat] {
								var c = configuration(leading: leading)
								c.visibility = visibility
								c.reservation = overlay ? 0 : visibility
								c.overlaysContent = overlay
								// Following sidebar reservation is part of this input.
								for following in [0, 364] as [CGFloat] {
									c.minimumContentWidth = 600 + following
									let g = BrowserNativeSplitGeometry(size: CGSize(width: available, height: height), configuration: c, preferredWidth: preferred)
									let fits = available >= c.minimumContentWidth + c.limits.lowerBound
									let width = min(available, max(c.limits.lowerBound, min(preferred, c.limits.upperBound, available - c.minimumContentWidth)))
									let visible = width * visibility
									let reserved = fits ? width * c.reservation : 0
									precondition(g.width == width)
									precondition(g.content == CGRect(x: leading ? reserved : 0, y: 0, width: available - reserved, height: height))
									precondition(g.sidebarClip == CGRect(x: leading ? 0 : available - visible, y: 0, width: visible, height: height))
									precondition(g.sidebar.width == width && g.sidebar.height == height)
									let absoluteX = g.sidebarClip.minX + g.sidebar.minX
									precondition(abs(absoluteX - (leading ? 0 : available - width)) < 0.000001)
									precondition(g.divider == CGRect(x: leading ? width - 4 : available - width - 6, y: 0, width: 8, height: height))
									precondition(g.canResize == (visibility == 1 && !overlay && fits))
								}
							}
						}
					}
				}
			}
		}
	}

	@MainActor private static func stateChecks() {
		for leading in [true, false] {
			let state = BrowserNativeSplitState(configuration: configuration(leading: leading))
			let size = CGSize(width: 1400, height: 800)
			var reports: [CGFloat] = []
			state.onWidthChange = { reports.append($0) }
			state.reportWidth(state.geometry(size).width)
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
			precondition(reports.count == 1)
			state.begin(size)
			for step in 1 ... 1000 {
				state.drag(translation: (leading ? 1 : -1) * CGFloat(step) / 20, size: size)
				state.reportWidth(state.geometry(size).width)
			}
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
			precondition(reports.count == 1, "Live resize must not publish shell state")
			let final = state.geometry(size).width
			precondition(final == (leading ? 274 : 414), "Drag direction or baseline changed")
			state.end(size)
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
			precondition(reports == [leading ? 224 : 364, final])
			state.reportWidth(final)
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
			precondition(reports.count == 2, "Duplicate width report")
			// External window clamping does not erase the requested width.
			let clamped = state.geometry(CGSize(width: 800, height: 800)).width
			precondition(clamped < final)
			precondition(state.geometry(size).width == final)
			state.adjust(by: -20, size: size)
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
			precondition(reports.last == final - 20, "Accessibility adjustment must commit")
			state.begin(size)
			state.drag(translation: leading ? -10000 : 10000, size: size)
			precondition(state.geometry(size).width == state.configuration.limits.lowerBound)
			state.end(size)
			state.invalidate()
		}
	}

	@MainActor private static func nativeLayoutChecks() {
		let app = NSApplication.shared
		app.setActivationPolicy(.prohibited)
		let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		let container = BrowserNativeSplitContainer(configuration: configuration())
		window.contentView = container
		container.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
		container.sidebarHost.rootView = AnyView(StatefulPane())
		container.contentHost.rootView = AnyView(Color.blue)
		Probe.pulse(container)
		let sidebarHost = container.sidebarHost
		let contentHost = container.contentHost
		let appearances = Probe.appearances
		let identities = Probe.identities
		precondition(appearances == 1 && identities.count == 1)
		container.state.begin(container.bounds.size)
		for step in 1 ... 80 {
			container.state.drag(translation: CGFloat(step), size: container.bounds.size)
			container.layoutPanes()
		}
		container.state.end(container.bounds.size)
		Probe.pulse(container)
		precondition(container.sidebarHost === sidebarHost && container.contentHost === contentHost)
		precondition(Probe.appearances == appearances && Probe.identities == identities, "Resize remounted hosted controls")
		precondition(sidebarHost.frame.width == 304)
		precondition(contentHost.frame == CGRect(x: 304, y: 0, width: 976, height: 800))
		// A completed hide leaves roots mounted and gives content the full width.
		container.state.configuration.shown = false
		container.state.configuration.visibility = 0
		container.state.configuration.reservation = 0
		container.layoutPanes()
		precondition(contentHost.frame == container.bounds)
		precondition(sidebarHost.superview?.isHidden == true)
		precondition(sidebarHost.superview?.hitTest(.zero) == nil)
		container.state.invalidate()
		window.close()
	}
}
