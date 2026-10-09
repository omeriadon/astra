"""Render real theme views and exercise native animation. Does not launch Astra."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
background = (root / 'astra/UI/Background/BrowserThemeBackground.swift').read_text()
assert background.count('ThemeSurface(') == 2, 'Themes must share one persistent surface'
assert 'transitionProgress' not in background, 'Remove the opacity crossfade'

# The window material and Noise package shader are outside this color-animation check.
background = background.replace('import MaterialView', '').replace('WindowMaterial()', 'Color.clear')
start = background.index('\t#if os(macOS)')
end = background.index('\n\tvar body:', start)
background = background[:start] + background[end:]
# Apple's Reduce Motion environment is read-only; inject the same Bool through a test key.
background = background.replace('accessibilityReduceMotion', 'themeCheckReduceMotion')
noise = (root / 'astra/UI/Background/StableRandomNoise.swift').read_text().replace('import Noise', '')

harness = r'''
import AppKit
import Observation
import SwiftUI

struct BrowserSpace {
    var theme: BrowserTheme
}

extension EnvironmentValues {
    @Entry var themeCheckReduceMotion = false
}

@MainActor
private var noiseCreations = 0
private struct NoiseProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        noiseCreations += 1
        return NSView()
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
struct Noise: View {
    enum Style { case random }
    let style: Style
    var body: some View { NoiseProbe() }
    func monochrome() -> Self { self }
}
@MainActor
@Observable
private final class ThemeState {
    var theme = BrowserTheme()
}
private struct LinkedThemeHarness: View {
    let theme: BrowserTheme
    let spaces: [BrowserSpace]
    let scroll: BrowserSpaceScrollState
    let reduceMotion: Bool
    var body: some View {
        BrowserThemeBackground(theme: theme, spaces: spaces, scrollState: scroll)
            .environment(\.themeCheckReduceMotion, reduceMotion)
    }
}
private struct ThemeHarness: View {
    let state: ThemeState
    let reduceMotion: Bool
    var body: some View {
        BrowserThemeBackground(theme: state.theme)
            .environment(\.themeCheckReduceMotion, reduceMotion)
    }
}
@main
struct ThemeTransitionCheck {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var red = BrowserTheme()
        red.shaderNoiseEnabled = true
        red.shaderNoiseAmount = 0.2
        red.meshColorPoints = [ThemeColorPoint(color: BrowserColor(red: 1, green: 0, blue: 0), x: 0.5, y: 0.5)]
        var blue = red
        blue.meshColorPoints = (0..<4).map { index in
            ThemeColorPoint(color: BrowserColor(red: 0, green: 0, blue: 1), x: Double(index % 2), y: Double(index / 2))
        }
        blue.shaderNoiseMonochrome = false
        var empty = red
        empty.meshColorPoints = []
        for reduceMotion in [false, true] {
            noiseCreations = 0
            let state = ThemeState()
            state.theme = red
            let host = NSHostingView(rootView: ThemeHarness(state: state, reduceMotion: reduceMotion))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.contentView = host
            window.orderFront(nil)
            func wait(_ seconds: Double) {
                RunLoop.main.run(until: Date().addingTimeInterval(seconds))
            }
            func sample() -> NSColor {
                host.layoutSubtreeIfNeeded()
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                return bitmap.colorAt(x: 40, y: 40)!.usingColorSpace(.sRGB)!
            }
            wait(0.1)
            let initial = sample()
            assert(initial.redComponent > 0.85, "Expected red, got \(initial)")
            state.theme = blue
            wait(reduceMotion ? 0.05 : 0.12)
            let middle = sample()
            assert(middle.alphaComponent > 0.98, "Theme blend must not expose the window material")
            if reduceMotion {
                assert(middle.blueComponent > 0.85, "Reduce Motion must apply the target immediately")
            } else {
                assert(middle.redComponent < initial.redComponent - 0.05 && middle.blueComponent > initial.blueComponent + 0.05, "Mesh colors must interpolate in place")
                assert(middle.blueComponent < 0.85, "The target must not jump into place")
                state.theme = red
                wait(0.015)
                let interrupted = sample()
                assert(abs(interrupted.redComponent - middle.redComponent) < 0.25, "Interrupted animation must continue from its displayed color")
                wait(0.4)
                assert(sample().redComponent > 0.85, "Expected red, got \(sample())")
                state.theme = blue
            }
            wait(0.4)
            assert(sample().blueComponent > 0.85)
            assert(noiseCreations == 1, "Space switches must retain one noise subtree")
            state.theme = empty
            wait(0.4)
            assert(sample().alphaComponent < 0.05, "An empty palette must remain transparent")
            state.theme = red
            wait(0.4)
            assert(sample().redComponent > 0.85 && sample().alphaComponent > 0.98)
            window.close()
        }
        for reduceMotion in [false, true] {
            noiseCreations = 0
            let scroll = BrowserSpaceScrollState()
            scroll.position = 0
            let host = NSHostingView(rootView: LinkedThemeHarness(
                theme: red,
                spaces: [BrowserSpace(theme: red), BrowserSpace(theme: blue)],
                scroll: scroll,
                reduceMotion: reduceMotion
            ))
            let reference = NSHostingView(rootView: MeshGradientSurface(points: red.meshColorPoints))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
            let referenceWindow = NSWindow(contentRect: NSRect(x: 100, y: 0, width: 80, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            referenceWindow.isReleasedWhenClosed = false
            window.contentView = host
            referenceWindow.contentView = reference
            window.orderFront(nil)
            referenceWindow.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            func pixel(_ view: NSView) -> NSColor {
                view.layoutSubtreeIfNeeded()
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                return bitmap.colorAt(x: 40, y: 40)!.usingColorSpace(.sRGB)!
            }
            let redColors = MeshGradientSurface.colors(for: red.meshColorPoints)
            let blueColors = MeshGradientSurface.colors(for: blue.meshColorPoints)
            for progress in [0.25, 0.5, 0.75, 0.5, 0, 1, 0.5] {
                scroll.position = progress
                reference.rootView = MeshGradientSurface(colors: zip(redColors, blueColors).map {
                    $0.mix(with: $1, by: progress)
                })
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
                let actual = pixel(host)
                let expected = pixel(reference)
                assert(abs(actual.redComponent - expected.redComponent) < 0.025, "Red channel must follow scroll fraction immediately: \(progress), \(actual), expected \(expected)")
                assert(abs(actual.blueComponent - expected.blueComponent) < 0.025, "Blue channel must follow scroll fraction immediately")
                assert(actual.alphaComponent > 0.98)
            }
            assert(noiseCreations == 1, "Dragging and cancelling must retain the noise view")
            window.close()
            referenceWindow.close()
        }
        print("Theme animation and exact scroll-linked quarter/half/three-quarter blends, reversal, cancellation, Reduce Motion, and noise lifetime passed")
    }
}
'''

with tempfile.TemporaryDirectory() as directory:
    directory = Path(directory)
    files = []
    for name, source in [
        ('BrowserTheme.swift', (root / 'astra/Models/Spaces/BrowserTheme.swift').read_text()),
        ('MeshGradientSurface.swift', (root / 'astra/UI/Settings/Theme/MeshGradientSurface.swift').read_text()),
        ('ThemeSurface.swift', (root / 'astra/UI/Background/ThemeSurface.swift').read_text()),
        ('StableRandomNoise.swift', noise),
        ('BrowserThemeBackground.swift', background),
        ('BrowserSpaceScrollState.swift', (root / 'astra/UI/Shell/BrowserSpaceScrollState.swift').read_text()),
        ('Check.swift', harness),
    ]:
        path = directory / name
        path.write_text(source)
        files.append(str(path))
    executable = directory / 'check'
    subprocess.run(['swiftc', '-parse-as-library', *files, '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
