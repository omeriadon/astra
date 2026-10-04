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
			if !controller.findText.isEmpty, controller.findHasMatch == false {
				Text("No matches")
					.font(.caption)
					.foregroundStyle(.secondary)
					.accessibilityIdentifier("find-in-page-no-match")
			}
			if !controller.findText.isEmpty, controller.findMatchCount > 0 {
				Text("\(controller.findMatchIndex) of \(controller.findMatchCount)")
					.monospacedDigit()
					.font(.caption)
					.accessibilityLabel("Match \(controller.findMatchIndex) of \(controller.findMatchCount)")
					.accessibilityIdentifier("find-in-page-match-count")
			}
			if !controller.findText.isEmpty, controller.findHasMatch == true, controller.findMatchCount == 0 {
				Text("Match found")
					.font(.caption)
					.accessibilityIdentifier("find-in-page-native-match")
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
		.onAppear {
			isFocused = true
			controller.findNext()
		}
		.task(id: controller.findFocusRequest) {
			await Task.yield()
			isFocused = true
		}
		.onDisappear { controller.invalidateFindResults() }
		.accessibilityIdentifier("find-in-page-bar")
	}
}
