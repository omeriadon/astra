import SwiftUI

struct BrowserTabRow: View {
	@Bindable var tab: BrowserTab
	let isSelected: Bool
	let onSelect: (UUID) -> Void
	let onClose: (UUID) -> Void

	private var closeButton: some View {
		Button("Close Tab", systemImage: "xmark") {
			onClose(tab.id)
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.plain)
		.accessibilityIdentifier("close-tab-\(tab.id.uuidString)")
	}

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

			if isSelected {
				closeButton
					.keyboardShortcut("W", modifiers: .command)
			} else {
				closeButton
			}
		}
		.padding(.horizontal, 8)
		.frame(height: 28)
		.glassEffect(.regular.tint(.white.opacity(isSelected ? 0.2 : 0.0)), in: RoundedRectangle(cornerRadius: 10))
	}
}
