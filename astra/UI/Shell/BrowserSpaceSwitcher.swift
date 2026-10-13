#if os(macOS)
import AppKit
import Observation
import SwiftUI

extension Notification.Name {
    static let cycleBrowserSpace = Notification.Name("CycleBrowserSpace")
}

/// A single switching session belongs to the focused desktop window.
/// The selection is preview-only until the modifier keys are released.
@MainActor
@Observable
final class BrowserSpaceSwitcher {
    private(set) var isPresented = false
    private(set) var highlightedSpaceID: UUID?

    @ObservationIgnored private let browser: Browser
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var originalSpaceID: UUID?
    @ObservationIgnored private var requiredModifiers: NSEvent.ModifierFlags = []
    @ObservationIgnored private var fallbackCommitTask: Task<Void, Never>?

    init(browser: Browser) {
        self.browser = browser
    }

    func setWindow(_ window: NSWindow?) {
        self.window = window
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isPresented else { return false }
                guard self.window === NSApp.keyWindow, self.window?.isKeyWindow == true else {
                    self.cancel()
                    return false
                }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.cancel()
                    return true
                }
                if event.type == .flagsChanged {
                    let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if !pressed.isSuperset(of: self.requiredModifiers) || self.requiredModifiers.isEmpty {
                        self.commit()
                    }
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        cancel()
    }

    func advance(direction: Int, modifiers: NSEvent.ModifierFlags) {
        let spaces = browser.workspace.spaces
        guard !browser.isMini, window?.isKeyWindow == true, spaces.count > 1,
              direction == 1 || direction == -1 else { return }

        if !isPresented {
            originalSpaceID = browser.selectedSpace.id
            highlightedSpaceID = browser.selectedSpace.id
            requiredModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
            withAnimation(.smooth(duration: 0.22)) {
                isPresented = true
            }
        }

        let index = spaces.firstIndex { $0.id == highlightedSpaceID }
            ?? spaces.firstIndex { $0.id == browser.selectedSpace.id } ?? 0
        let target = (index + direction + spaces.count) % spaces.count
        withAnimation(.spring(response: 0.28, dampingFraction: 0.66, blendDuration: 0.1)) {
            highlightedSpaceID = spaces[target].id
        }

        // A user-configured shortcut with no held modifier needs a completion path.
        fallbackCommitTask?.cancel()
        if requiredModifiers.isEmpty {
            fallbackCommitTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(550))
                if !Task.isCancelled { self?.commit() }
            }
        }
    }

    func spacesDidChange() {
        guard isPresented,
              let id = highlightedSpaceID,
              browser.workspace.spaces.contains(where: { $0.id == id }) else {
            cancel()
            return
        }
    }

    private func commit() {
        guard isPresented else { return }
        let destination = highlightedSpaceID
        end()
        if let destination, browser.workspace.spaces.contains(where: { $0.id == destination }) {
            browser.selectSpace(destination)
        }
    }

    func cancel() {
        guard isPresented else { return }
        end()
    }

    private func end() {
        fallbackCommitTask?.cancel()
        fallbackCommitTask = nil
        requiredModifiers = []
        originalSpaceID = nil
        withAnimation(.smooth(duration: 0.18)) {
            isPresented = false
        }
        highlightedSpaceID = nil
    }
}

struct BrowserSpaceSwitcherOverlay: View {
    let browser: Browser
    let switcher: BrowserSpaceSwitcher
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardWidth: CGFloat = 250
    private let cardHeight: CGFloat = 150
    private let cardSpacing: CGFloat = 18

    private var selectedIndex: Int {
        browser.workspace.spaces.firstIndex { $0.id == switcher.highlightedSpaceID } ?? 0
    }

    var body: some View {
        if switcher.isPresented {
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.14))
                        .ignoresSafeArea()

                    GlassEffectContainer {
                        VStack(spacing: 17) {
                            Text("Spaces")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.75))
                            GeometryReader { viewport in
                                HStack(spacing: cardSpacing) {
                                    ForEach(browser.workspace.spaces) { space in
                                        spaceCard(space)
                                            .frame(width: cardWidth, height: cardHeight)
                                    }
                                }
                                // Every card, including the first and last, can occupy the
                                // true viewport center. There is no user-driven scroll state.
                                .offset(x: viewport.size.width / 2
                                    - cardWidth / 2
                                    - CGFloat(selectedIndex) * (cardWidth + cardSpacing))
                                .animation(
                                    reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.66),
                                    value: switcher.highlightedSpaceID
                                )
                            }
                            .frame(height: cardHeight + 3)
                            .clipped()
                            Text("Release the shortcut to switch · Esc to cancel")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 19)
                        .frame(width: min(geometry.size.width - 36, 880))
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .transition(.opacity)
            .accessibilityIdentifier("space-switcher-overlay")
        }
    }

    private func spaceCard(_ space: BrowserSpace) -> some View {
        let isSelected = space.id == switcher.highlightedSpaceID
        return VStack(spacing: 14) {
            Image(systemName: space.symbol)
                .font(.system(size: 35, weight: .medium))
                .frame(height: 45)
            Text(space.name)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(space.theme.foregroundColor)
        .background {
            ThemeSurface(theme: space.theme)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(isSelected ? 1 : 0.12), lineWidth: isSelected ? 2.5 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.23 : 0.08), radius: isSelected ? 14 : 5)
        .scaleEffect(isSelected && !reduceMotion ? 1.025 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(space.name)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("space-switcher-card-\(space.id)")
    }
}
#endif
