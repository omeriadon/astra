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
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.accessibilityIdentifier("close-tab-\(tab.id.uuidString)")
		}
		.padding(.horizontal, 8)
		.frame(height: 28)
		.background(.green.opacity(isSelected ? 1 : 0.72), in: RoundedRectangle(cornerRadius: 24))
		.overlay {
			RoundedRectangle(cornerRadius: 24)
				.strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5)
		}
	}
}
