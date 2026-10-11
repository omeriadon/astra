#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

/// Renders each space's theme once and blends the two visible layers in AppKit.
/// Per-frame pager progress must not mutate a SwiftUI-observed property or
/// reconstruct a 10x10 MeshGradient (and its noise shader).
struct NativeSpaceThemeSurface: NSViewRepresentable {
    let theme: BrowserTheme
    let themes: [BrowserTheme]
    let palettes: [[Color]]
    let scrollState: BrowserSpaceScrollState?

    func makeNSView(context: Context) -> NativeSpaceThemeSurfaceView {
        NativeSpaceThemeSurfaceView()
    }

    func updateNSView(_ view: NativeSpaceThemeSurfaceView, context: Context) {
        view.configure(
            theme: theme,
            themes: themes,
            palettes: palettes,
            state: scrollState,
            environment: context.environment
        )
    }

    static func dismantleNSView(_ view: NativeSpaceThemeSurfaceView, coordinator: ()) {
        view.stopObserving()
    }
}

@MainActor
final class NativeSpaceThemeSurfaceView: NSView {
    private var currentTheme: BrowserTheme?
    private var currentThemes: [BrowserTheme] = []
    private var currentPalettes: [[Color]] = []
    private var currentColorScheme: ColorScheme?
    private var currentDynamicTypeSize: DynamicTypeSize?
    private var currentReduceMotion: Bool?
    private var environment = EnvironmentValues()
    private var slots: [Int: NSView] = [:]
    private var renderedPair: (Int, Int)?
    private weak var observedState: BrowserSpaceScrollState?
    private var observerID: UUID?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(
        theme: BrowserTheme,
        themes: [BrowserTheme],
        palettes: [[Color]],
        state: BrowserSpaceScrollState?,
        environment: EnvironmentValues
    ) {
        // Selecting a new space must NOT recreate all hosted gradients
        // at gesture release; its theme is already cached by space index.
        let contentChanged =
            currentThemes != themes ||
            currentPalettes != palettes ||
            (themes.isEmpty && currentTheme != theme) ||
            currentColorScheme != environment.colorScheme ||
            currentDynamicTypeSize != environment.dynamicTypeSize ||
            currentReduceMotion != environment.accessibilityReduceMotion

        self.environment = environment
        currentTheme = theme
        if contentChanged {
            currentThemes = themes
            currentPalettes = palettes
            currentColorScheme = environment.colorScheme
            currentDynamicTypeSize = environment.dynamicTypeSize
            currentReduceMotion = environment.accessibilityReduceMotion
            for slot in slots.values {
                slot.removeFromSuperview()
            }
            slots.removeAll(keepingCapacity: true)
            renderedPair = nil
        }

        if observedState !== state {
            stopObserving()
            observedState = state
            observerID = state?.addPresentationObserver { [weak self] position in
                self?.show(position: position)
            }
        }

        show(position: state?.presentationPosition)
    }

    func stopObserving() {
        if let observerID {
            observedState?.removePresentationObserver(observerID)
        }
        observerID = nil
        observedState = nil
    }

    override func layout() {
        super.layout()
        for slot in slots.values where slot.frame != bounds {
            slot.frame = bounds
        }
    }

    private func slot(for index: Int) -> NSView {
        if let existing = slots[index] {
            return existing
        }
        let selectedTheme = index >= 0 && currentThemes.indices.contains(index)
            ? currentThemes[index] : currentTheme!
        let selectedColors: [Color]? =
            index >= 0 && currentPalettes.indices.contains(index)
                ? currentPalettes[index] : nil

        let surface = ThemeSurface(theme: selectedTheme, colors: selectedColors)
            .environment(\.self, environment)
        let host = NSHostingView(rootView: AnyView(surface))
        host.sizingOptions = []
        let container = NSView(frame: bounds)
        container.wantsLayer = true
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.isHidden = true
        addSubview(container)
        slots[index] = container
        return container
    }

    private func show(position: Double?) {
        guard currentTheme != nil else { return }
        guard !currentThemes.isEmpty else {
            let fallback = slot(for: -1)
            fallback.isHidden = false
            fallback.layer?.opacity = 1
            return
        }

        let selected = currentThemes.firstIndex(of: currentTheme!) ?? 0
        let raw = position ?? Double(selected)
        let safe = raw.isFinite ? raw : Double(selected)
        let clamped = min(max(safe, 0), Double(currentThemes.count - 1))
        let lower = Int(floor(clamped))
        let upper = min(lower + 1, currentThemes.count - 1)
        let progress = Float(clamped - Double(lower))
        // Prewarm one neighboring theme. Only two hosts are displayed.
        let keep = Set([lower, upper, max(lower - 1, 0), min(upper + 1, currentThemes.count - 1)])
        for index in Array(slots.keys) where !keep.contains(index) {
            slots.removeValue(forKey: index)?.removeFromSuperview()
        }
        for index in keep {
            _ = slot(for: index)
        }
        for (index, view) in slots {
            let visible = index == lower || index == upper
            if view.isHidden == visible {
                view.isHidden = !visible
            }
        }

        if renderedPair?.0 != lower || renderedPair?.1 != upper {
            let bottom = slots[lower]!
            if upper != lower {
                addSubview(slots[upper]!, positioned: .above, relativeTo: bottom)
            }
            renderedPair = (lower, upper)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slots[lower]?.layer?.opacity = 1
        if upper != lower {
            slots[upper]?.layer?.opacity = progress
        }
        CATransaction.commit()
    }
}
#endif
