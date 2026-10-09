"""Run with python3 checks/window-chrome-runtime-check.py. Does not launch Astra."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]

native_check = r"""
import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class ProbeState {
	var creationCount = 0
}

@MainActor
@Observable
private final class LayoutState {
	var barHeight: CGFloat

	init(barHeight: CGFloat) {
		self.barHeight = barHeight
	}
}

private final class ProbeView: NSView {
	let state: ProbeState

	init(state: ProbeState) {
		self.state = state
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) is unavailable")
	}
}

private struct ChromeProbe: NSViewRepresentable {
	let state: ProbeState

	func makeNSView(context: Context) -> ProbeView {
		state.creationCount += 1
		return ProbeView(state: state)
	}

	func updateNSView(_ view: ProbeView, context: Context) {}
}

private struct SidebarChromeHarness: View {
	let barState: ProbeState
	let pageState: ProbeState
	let sidebarWidth: CGFloat
	@Bindable var layout: LayoutState

	var body: some View {
		GeometryReader { geometry in
			HStack(spacing: 0) {
				ScrollView {
					VStack(spacing: 0) {
						ForEach(0..<40) { index in
							Text("Sidebar row \(index)")
								.frame(maxWidth: .infinity)
								.frame(height: 32)
						}
					}
				}
				.frame(width: sidebarWidth, height: geometry.size.height)
				.sidebarScrollContentMargins()
				.sidebarScrollOpacityFade(top: 38, bottom: layout.barHeight + 38)
				.overlay(alignment: .bottom) {
					ChromeProbe(state: barState)
						.frame(maxWidth: .infinity)
						.frame(height: layout.barHeight)
				}

				ChromeProbe(state: pageState)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
	}
}

@main
struct SidebarChromeRuntimeCheck {
	@MainActor
	static func main() {
		let app = NSApplication.shared
		app.setActivationPolicy(.prohibited)

		for (width, height, sidebarWidth, initialBarHeight, updatedBarHeight) in [
			(CGFloat(800), CGFloat(600), CGFloat(240), CGFloat(48), CGFloat(86)),
			(CGFloat(1260), CGFloat(900), CGFloat(320), CGFloat(86), CGFloat(48)),
		] {
			let barState = ProbeState()
			let pageState = ProbeState()
			let layout = LayoutState(barHeight: initialBarHeight)
			let host = NSHostingView(rootView: SidebarChromeHarness(
				barState: barState,
				pageState: pageState,
				sidebarWidth: sidebarWidth,
				layout: layout
			).frame(width: width).ignoresSafeArea())
			host.sizingOptions = []
			host.frame = CGRect(x: 0, y: 0, width: width, height: height)
			let window = NSWindow(
				contentRect: host.frame,
				styleMask: [.titled, .fullSizeContentView],
				backing: .buffered,
				defer: false
			)
			window.titlebarAppearsTransparent = true
			window.contentView = host
			checkLayout(
				host: host,
				window: window,
				sidebarWidth: sidebarWidth,
				barHeight: initialBarHeight,
				barState: barState,
				pageState: pageState
			)

			layout.barHeight = updatedBarHeight
			RunLoop.main.run(until: Date().addingTimeInterval(0.15))
			host.layoutSubtreeIfNeeded()
			checkLayout(
				host: host,
				window: window,
				sidebarWidth: sidebarWidth,
				barHeight: updatedBarHeight,
				barState: barState,
				pageState: pageState
			)
			assert(barState.creationCount == 1 && pageState.creationCount == 1)
			window.contentView = nil
		}
		print("Sidebar chrome runtime check passed")
	}

	@MainActor
	private static func checkLayout(
		host: NSHostingView<some View>,
		window: NSWindow,
		sidebarWidth: CGFloat,
		barHeight: CGFloat,
		barState: ProbeState,
		pageState: ProbeState
	) {
		host.layoutSubtreeIfNeeded()
		RunLoop.main.run(until: Date().addingTimeInterval(0.15))
		host.layoutSubtreeIfNeeded()
		let views = descendants(of: host)
		let hazeViews = views.compactMap { $0 as? HazeEffectView<LinearGradientMaskProvider> }
		assert(hazeViews.count == 1, "one bottom Haze view must cover the shared sidebar")
		let scrollViews = views.compactMap { $0 as? NSScrollView }
		assert(scrollViews.count == 1, "the sidebar viewport must contain one native scroll view")
		let bar = views.compactMap { $0 as? ProbeView }.first { $0.state === barState }!
		let page = views.compactMap { $0 as? ProbeView }.first { $0.state === pageState }!
		let hazeFrame = hazeViews[0].convert(hazeViews[0].bounds, to: host)
		let barFrame = bar.convert(bar.bounds, to: host)
		let pageFrame = page.convert(page.bounds, to: host)
		let scrollViewportFrame = scrollViews[0].contentView.convert(scrollViews[0].contentView.bounds, to: host)
		let topEdge = host.isFlipped ? host.bounds.minY : host.bounds.maxY
		let viewportTop = host.isFlipped ? scrollViewportFrame.minY : scrollViewportFrame.maxY
		let viewportBottom = host.isFlipped ? scrollViewportFrame.maxY : scrollViewportFrame.minY
		let hazeBottom = host.isFlipped ? hazeFrame.maxY : hazeFrame.minY
		let barBottom = host.isFlipped ? barFrame.maxY : barFrame.minY
		assert(abs(scrollViewportFrame.width - sidebarWidth) < 1, "native clip width \(scrollViewportFrame.width), clip frame \(scrollViews[0].contentView.frame), scroll frame \(scrollViews[0].frame), host \(host.bounds), target \(sidebarWidth)")
		assert(abs(scrollViewportFrame.height - host.bounds.height) < 1, "native scroll viewport must span the full window height")
		assert(abs(viewportTop - topEdge) < 1, "native scroll viewport must start at the window top behind traffic lights")
		assert(abs(viewportBottom - (host.isFlipped ? host.bounds.maxY : host.bounds.minY)) < 1, "native scroll viewport must reach the window bottom")
		assert(abs(hazeFrame.width - sidebarWidth) < 1, "fade width must match the sidebar")
		assert(abs(hazeFrame.height - (barHeight + 38)) < 1, "bottom effect must include the measured bar and 38 point fade")
		assert(abs(hazeBottom - (host.isFlipped ? host.bounds.maxY : host.bounds.minY)) < 1, "bottom effect must extend to the window bottom behind the bar")
		assert(abs(barBottom - (host.isFlipped ? host.bounds.maxY : host.bounds.minY)) < 1, "native bottom bar must sit at the window bottom")
		assert(hazeFrame.intersects(barFrame), "bottom bar must overlay the blur region")
		assert(hazeFrame.maxX <= pageFrame.minX + 1, "the page must not overlap the sidebar effect")
		assert(descendants(of: bar).allSatisfy { !($0 is HazeEffectView<LinearGradientMaskProvider>) })
		assert(descendants(of: page).allSatisfy { !($0 is HazeEffectView<LinearGradientMaskProvider>) })
		assert(window.contentView === host)
	}

	@MainActor
	private static func descendants(of view: NSView) -> [NSView] {
		[view] + view.subviews.flatMap(descendants)
	}
}
"""

with tempfile.TemporaryDirectory() as directory:
    directory = Path(directory)
    helper = directory / "SidebarChrome.swift"
    helper.write_text((root / "astra/UI/Shell/topVariableBlur.swift").read_text().replace("import Haze", ""))
    check = directory / "RuntimeCheck.swift"
    check.write_text(native_check)
    executable = directory / "check"
    sources = sorted((root / "Packages/Haze/Sources").rglob("*.swift"))
    subprocess.run([
        "swiftc", "-parse-as-library", *map(str, sources), str(helper), str(check),
        "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
