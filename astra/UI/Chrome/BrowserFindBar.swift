import SwiftUI

struct BrowserFindBar: View {
	@Bindable var controller: BrowserController
	@FocusState private var isFocused: Bool

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.accessibilityHidden(true)
			TextField("Find in Page", text: $controller.findText)
				.textFieldStyle(.plain)
				.focused($isFocused)
				.onSubmit { controller.findNext() }
				.onChange(of: controller.findText) { _, _ in
					controller.findNext()
				}
				.onKeyPress(.escape) {
					controller.dismissFind()
					return .handled
				}
				.accessibilityIdentifier("find-in-page-field")
			if !controller.findText.isEmpty, !controller.findHasMatch {
				Text("No matches")
					.font(.caption)
					.foregroundStyle(.secondary)
					.accessibilityIdentifier("find-in-page-no-match")
			}
			Button("Previous Match", systemImage: "chevron.up") {
				controller.findNext(backwards: true)
			}
			.labelStyle(.iconOnly)
			.accessibilityIdentifier("find-previous-match")
			Button("Next Match", systemImage: "chevron.down") {
				controller.findNext()
			}
			.labelStyle(.iconOnly)
			.accessibilityIdentifier("find-next-match")
			Button("Close Find", systemImage: "xmark", action: controller.dismissFind)
				.labelStyle(.iconOnly)
				.accessibilityIdentifier("find-close")
		}
		.buttonStyle(.glass)
		.padding(10)
		.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
		.frame(maxWidth: 440)
		.padding(12)
		.onAppear { isFocused = true }
		.accessibilityIdentifier("find-in-page-bar")
	}
}
