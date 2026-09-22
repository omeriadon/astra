import SwiftUI

struct BrowserLoadingBar: View {
	let isLoading: Bool
	let estimatedProgress: Double

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var displayedProgress = 0.0
	@State private var isVisible = false
	@State private var completionGeneration = 0

	var body: some View {
		Rectangle()
			.fill(.green)
			.scaleEffect(x: displayedProgress, anchor: .leading)
			.opacity(isVisible ? 1 : 0)
			.accessibilityElement(children: .ignore)
			.accessibilityLabel("Page loading progress")
			.accessibilityValue(Text(displayedProgress, format: .percent))
			.accessibilityHidden(!isVisible)
			.onChange(of: estimatedProgress, initial: true) { _, progress in
				guard isLoading else { return }
				withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
					displayedProgress = min(clamped(progress), 0.99)
				}
			}
			.onChange(of: isLoading, initial: true) { _, isLoading in
				loadingDidChange(isLoading)
			}
	}

	private func loadingDidChange(_ isLoading: Bool) {
		completionGeneration += 1

		if isLoading {
			displayedProgress = min(clamped(estimatedProgress), 0.99)
			isVisible = true
			return
		}

		guard isVisible else { return }
		let generation = completionGeneration

		guard !reduceMotion else {
			displayedProgress = 1
			isVisible = false
			return
		}

		withAnimation(
			.easeOut(duration: 0.2),
			completionCriteria: .removed
		) {
			displayedProgress = 1
		} completion: {
			guard completionGeneration == generation else { return }
			withAnimation(.easeOut(duration: 0.1)) {
				isVisible = false
			}
		}
	}

	private func clamped(_ progress: Double) -> Double {
		min(max(progress, 0), 1)
	}
}
