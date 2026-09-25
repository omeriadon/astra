#if os(macOS)
	import AppKit
	import SwiftUI

	struct ControlTabSwitcherCandidateView: View {
		static let totalWidth: CGFloat = 196

		let tab: BrowserTab
		let isSelected: Bool
		let onHover: () -> Void
		let action: () -> Void

		private var host: String {
			tab.internalPage == nil ? tab.currentURL?.host ?? "New Tab" : "Internal Page"
		}

		private var accessibilityTraits: AccessibilityTraits {
			isSelected ? .isSelected : []
		}

		private var candidateAccessibilityIdentifier: String {
			"control-tab-candidate-" + tab.id.uuidString
		}

		var body: some View {
			Button(action: action) {
				VStack(spacing: 7) {
					Group {
						if let page = tab.internalPage {
							Image(systemName: page.symbol)
								.font(.system(size: 32))
								.frame(maxWidth: .infinity, maxHeight: .infinity)
						} else if let snapshot = tab.controller?.previewSnapshot {
							Image(nsImage: snapshot)
								.resizable()
								.aspectRatio(contentMode: .fill)
						} else {
							Color.white.opacity(0.08)
						}
					}
					.frame(width: 180, height: 100)
					.clipped()
					.clipShape(RoundedRectangle(cornerRadius: 7))
					Text(verbatim: tab.title)
						.lineLimit(1)
					Text(verbatim: host)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.frame(width: 180)
				.padding(8)
				.glassEffect(
					isSelected ? .regular.tint(.white.opacity(0.2)) : .regular,
					in: RoundedRectangle(cornerRadius: 15)
				)
				.animation(.smooth(duration: 0.15), value: isSelected)
			}
			.buttonStyle(.plain)
			.onHover { isHovering in
				if isHovering {
					onHover()
				}
			}
			.accessibilityElement(children: .combine)
			.accessibilityLabel(Text(verbatim: "\(tab.title), \(host)"))
			.accessibilityValue(isSelected ? "Selected" : "")
			.accessibilityAddTraits(accessibilityTraits)
			.accessibilityIdentifier(candidateAccessibilityIdentifier)
		}
	}
#endif
