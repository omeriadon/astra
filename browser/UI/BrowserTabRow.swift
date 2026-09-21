import SwiftUI

struct BrowserTabRow: View {
	@Bindable var tab: BrowserTab
	let isSelected: Bool
	let onSelect: (UUID) -> Void
	let onClose: (UUID) -> Void

	var body: some View {
		HStack(spacing: 6) {
			Button("Select Tab", systemImage: "globe") {
				onSelect(tab.id)
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.accessibilityIdentifier("select-tab-\(tab.id.uuidString)")

			TextField("Tab Name", text: $tab.title)
				.textFieldStyle(.plain)

			Button("Close Tab", systemImage: "xmark") {
				onClose(tab.id)
			}
			.keyboardShortcut("W", modifiers: .command)
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.accessibilityIdentifier("close-tab-\(tab.id.uuidString)")
		}
		.padding(.horizontal, 8)
		.frame(height: 28)
		.glassEffect(.regular.tint(.white.opacity(isSelected ? 0.2 : 0.0)), in: RoundedRectangle(cornerRadius: 10))
	}
}
