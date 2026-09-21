import SwiftUI

struct BrowserTabRow: View {
	@Bindable var tab: BrowserTab
	let isSelected: Bool
	let onSelect: (UUID) -> Void
	let onClose: (UUID) -> Void
	@State private var isRenaming = false
	@FocusState private var isTitleFocused: Bool

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

			if isRenaming {
				TextField("Tab Name", text: $tab.title)
					.textFieldStyle(.plain)
					.focused($isTitleFocused)
					.onSubmit(finishRenaming)
					.onChange(of: isTitleFocused) { _, isFocused in
						if !isFocused {
							isRenaming = false
						}
					}
					.accessibilityIdentifier("tab-name-\(tab.id.uuidString)")
			} else {
				Text(verbatim: tab.title)
					.lineLimit(1)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
					.contentShape(Rectangle())
					.onTapGesture {
						onSelect(tab.id)
					}
					.simultaneousGesture(
						TapGesture(count: 2)
							.onEnded { _ in beginRenaming() }
					)
					.accessibilityLabel(Text(verbatim: tab.title))
					.accessibilityAddTraits(.isButton)
					.accessibilityAction(.default) {
						onSelect(tab.id)
					}
					.accessibilityAction(named: "Rename") {
						beginRenaming()
					}
					.accessibilityIdentifier("tab-title-\(tab.id.uuidString)")
			}

			if isSelected {
				closeButton
					.keyboardShortcut("W", modifiers: .command)
			} else {
				closeButton
			}
		}
		.padding(.horizontal, 8)
		.frame(height: 28)
		.glassEffect(isSelected ? .clear.interactive() : .identity, in: RoundedRectangle(cornerRadius: 13))
		.onChange(of: isSelected) { _, selected in
			if !selected {
				finishRenaming()
			}
		}
	}

	private func beginRenaming() {
		onSelect(tab.id)
		isRenaming = true
		isTitleFocused = true
	}

	private func finishRenaming() {
		isTitleFocused = false
		isRenaming = false
	}
}
