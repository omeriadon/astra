#if os(macOS)
	import SwiftUI

	struct ControlTabSwitcherCandidateView: View {
		let tab: BrowserTab
		let isSelected: Bool

		private var host: String {
			tab.controller.url?.host ?? "New Tab"
		}

		private var accessibilityTraits: AccessibilityTraits {
			isSelected ? .isSelected : []
		}

		private var candidateAccessibilityIdentifier: String {
			"control-tab-candidate-" + tab.id.uuidString
		}

		var body: some View {
			VStack(spacing: 6) {
				Image(systemName: "globe")
					.font(.title2)
				Text(verbatim: tab.title)
					.lineLimit(1)
				HStack(spacing: 4) {
					Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
					Text(verbatim: host)
				}
				.font(.caption)
				.foregroundStyle(.secondary)
			}
			.frame(width: 140, height: 78)
			.padding(8)
			.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
			.accessibilityElement(children: .combine)
			.accessibilityLabel(Text(verbatim: "\(tab.title), \(host)"))
			.accessibilityValue(isSelected ? "Selected" : "")
			.accessibilityAddTraits(accessibilityTraits)
			.accessibilityIdentifier(candidateAccessibilityIdentifier)
		}
	}
#endif
