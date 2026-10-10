#if os(macOS)
	import SwiftUI

	struct ControlTabSwitcherPreview: View {
		let browser: Browser
		let switcher: ControlTabSwitcher

		private let spacing: CGFloat = 12
		private let padding: CGFloat = 12
		private let horizontalMargin: CGFloat = 20

		private func visibleCount(fitting width: CGFloat) -> Int {
			let availableWidth = max(0, width - horizontalMargin * 2 - padding * 2)
			return max(
				1,
				Int((availableWidth + spacing) / (ControlTabSwitcherCandidateView.totalWidth + spacing))
			)
		}

		private func visibleCandidateIDs(fitting width: CGFloat) -> [UUID] {
			let ids = switcher.candidateIDs
			return Array(ids.prefix(visibleCount(fitting: width)))
		}

		private func refreshVisibleCandidates(fitting width: CGFloat) async {
			let controllers = visibleCandidateIDs(fitting: width).compactMap { id in
				browser.tab(withID: id)?.controller
			}

			await withTaskGroup(of: Void.self) { group in
				for controller in controllers {
					group.addTask { @MainActor in
						try? await Task.sleep(for: .milliseconds(Int.random(in: 0 ... 40)))
						guard !Task.isCancelled else { return }
						// Most tabs already have a retained navigation/sidebar
						// snapshot. Opening the switcher must not queue a burst
						// of redundant WebKit captures on every candidate.
						if !controller.hasCurrentPreviewSnapshot {
							await controller.refreshPreviewSnapshot()
						}
					}
				}
			}
		}

		var body: some View {
			GeometryReader { geometry in
				ZStack {
					if switcher.isPreviewVisible {
						CandidateGridView(
							browser: browser,
							switcher: switcher,
							candidateIDs: visibleCandidateIDs(fitting: geometry.size.width)
						)
						.padding(padding)
						.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 27))
						.accessibilityIdentifier("control-tab-switcher-preview")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
					}
				}
				.onChange(of: visibleCount(fitting: geometry.size.width), initial: true) { _, count in
					switcher.setVisibleCandidateCount(count)
				}
				// Quick Control-Tab releases never display the switcher. The old
				// candidateIDs task still captured WebKit screenshots during
				// those interactions, even though no preview could appear.
				// Fetch snapshots only once the 200 ms display delay elapses,
				// and refresh only when the actually visible candidate set changes.
				.task(id: switcher.isPreviewVisible ? visibleCandidateIDs(fitting: geometry.size.width) : []) {
					guard switcher.isPreviewVisible, !Task.isCancelled else { return }
					await refreshVisibleCandidates(fitting: geometry.size.width)
				}
			}
		}
	}

	private struct CandidateGridView: View {
		let browser: Browser
		let switcher: ControlTabSwitcher
		let candidateIDs: [UUID]
		private let spacing: CGFloat = 12

		var body: some View {
			HStack(spacing: spacing) {
				ForEach(candidateIDs, id: \.self) { id in
					if let tab = browser.tab(withID: id) {
						ControlTabSwitcherCandidateView(
							tab: tab,
							isSelected: switcher.highlightedTabID == id,
							onHover: { switcher.highlight(id) },
							action: { switcher.select(id) }
						)
					}
				}
			}
		}
	}
#endif
