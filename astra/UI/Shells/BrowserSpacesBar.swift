import SwiftUI
#if os(iOS)
	import UIKit
#endif

struct BrowserSpacesBar: View {
	let browser: Browser
	let onSwipeProgress: (UUID?, Double) -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var scrollDistance: CGFloat = 0
	@State private var switchesThisSwipe = 0
	@State private var lastScrollAt: Date = .distantPast

	var body: some View {
		ScrollViewReader { reader in
			ScrollView(.horizontal) {
				HStack(spacing: 4) {
					ForEach(browser.workspace.spaces) { space in
						Button {
							withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
								browser.selectSpace(space.id)
							}
						} label: {
							Label(space.name, systemImage: space.symbol)
								.labelStyle(.iconOnly)
								.frame(width: 25, height: 25)
								.background {
									if browser.workspace.selectedSpaceID == space.id {
										RoundedRectangle(cornerRadius: 8)
											.fill(Color.primary.gradient)
											.opacity(0.4)
									}
								}
						}
						.buttonStyle(.plain)
						.accessibilityLabel(space.name)
						.accessibilityAddTraits(browser.workspace.selectedSpaceID == space.id ? .isSelected : [])
						.accessibilityIdentifier("space-\(space.id.uuidString)")
						#if os(macOS)
							.background {
								BrowserDropZone(
									browser: browser,
									area: .normal,
									spaceID: space.id,
									beforeTabID: nil
								)
							}
						#endif
							.id(space.id)
							.scrollTransition(axis: .horizontal) { content, phase in
								content
									.opacity(phase.isIdentity ? 1 : 0.25)
									.scaleEffect(phase.isIdentity ? 1 : 0.7)
									.blur(radius: phase.isIdentity ? 0 : 4)
							}
					}
				}
			}
			.scrollIndicators(.hidden)
			.scrollDisabled(true)
			#if os(iOS)
				.simultaneousGesture(
					DragGesture(minimumDistance: 10)
						.onEnded { value in
							let spaces = browser.workspace.spaces
							guard let index = spaces.firstIndex(where: { $0.id == browser.workspace.selectedSpaceID }) else { return }
							let count = abs(value.translation.width) > 200 ? 2 : 1
							let direction = value.translation.width < 0 ? 1 : -1
							let nextIndex = index + direction * count
							guard spaces.indices.contains(nextIndex) else { return }
							withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
								browser.selectSpace(spaces[nextIndex].id)
							}
							UISelectionFeedbackGenerator().selectionChanged()
						}
				)
			#endif
			#if os(macOS)
			.background {
				SpaceWheelReader { event in
					handleWheel(event)
				}
			}
			#endif
			.onChange(of: browser.workspace.selectedSpaceID, initial: true) { _, id in
				withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
					reader.scrollTo(id, anchor: .center)
				}
			}
		}
		.frame(height: 25)
	}

	#if os(macOS)
		private func handleWheel(_ event: NSEvent) {
			let now = Date.now
			if event.phase.contains(.began) || now.timeIntervalSince(lastScrollAt) > 0.35 {
				scrollDistance = 0
				switchesThisSwipe = 0
			}
			lastScrollAt = now
			if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
				onSwipeProgress(nil, 0)
				scrollDistance = 0
				switchesThisSwipe = 0
				return
			}
			scrollDistance += event.scrollingDeltaX
			let threshold: CGFloat = switchesThisSwipe == 0 ? 45 : 180
			let spaces = browser.workspace.spaces
			guard let index = spaces.firstIndex(where: { $0.id == browser.workspace.selectedSpaceID }) else { return }
			let nextIndex = index + (scrollDistance > 0 ? 1 : -1)
			if nextIndex == spaces.count, scrollDistance >= 90, switchesThisSwipe < 2 {
				browser.createSpace()
				switchesThisSwipe = 2
				scrollDistance = 0
				NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
				return
			}
			guard spaces.indices.contains(nextIndex), switchesThisSwipe < 2 else {
				onSwipeProgress(nil, 0)
				return
			}
			onSwipeProgress(spaces[nextIndex].id, min(Double(abs(scrollDistance) / threshold), 1))
			guard abs(scrollDistance) >= threshold else { return }
			withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
				browser.selectSpace(spaces[nextIndex].id)
			}
			switchesThisSwipe += 1
			scrollDistance = 0
			NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
		}
	#endif
}
