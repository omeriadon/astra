#if os(macOS)
import KeyboardShortcuts
import SwiftUI

struct BrowserKeyboardShortcutsSettingsView: View {
    @State private var revision = 0
    private let registry = BrowserShortcutRegistry.shared

    private var sections: [String] {
        var seen = Set<String>()
        return registry.definitions.map(\.section).filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            Section {
                Text("Record a shortcut to replace its default. Clear removes a binding; Reset restores the original. Changes take effect immediately.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Control–Option combinations overlap with macOS VoiceOver commands. VoiceOver users should assign different keys.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            ForEach(sections, id: \.self) { section in
                Section(section) {
                    ForEach(registry.definitions.filter { $0.section == section }) { definition in
                        HStack(spacing: 12) {
                            KeyboardShortcuts.Recorder(definition.title, name: definition.name) { _ in
                                changed()
                            }
                            .shortcutValidation { candidate in
                                if let conflict = registry.conflict(for: candidate, excluding: definition) {
                                    return .disallow(reason: "Already assigned to \(conflict.title).")
                                }
                                return .allow
                            }
                            Spacer(minLength: 8)
                            Button {
                                KeyboardShortcuts.setShortcut(nil, for: definition.name)
                                changed()
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .help("Remove shortcut")
                            .disabled(KeyboardShortcuts.getShortcut(for: definition.name) == nil)
                            .accessibilityLabel("Remove \(definition.title) shortcut")
                            Button {
                                KeyboardShortcuts.reset(definition.name)
                                changed()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .help("Restore default")
                            .accessibilityLabel("Reset \(definition.title) shortcut")
                        }
                        .id(definition.id)
                    }
                }
            }

            Section {
                Button("Reset All Shortcuts to Defaults", systemImage: "arrow.uturn.backward") {
                    registry.resetAllDefaults()
                    revision &+= 1
                }
                .accessibilityIdentifier("reset-all-shortcuts")
            }
        }
        .id(revision)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("keyboard-shortcuts-settings")
    }

    private func changed() {
        registry.didEditShortcut()
        revision &+= 1
    }
}
#endif
