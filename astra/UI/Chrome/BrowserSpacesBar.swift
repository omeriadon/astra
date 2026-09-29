import SwiftUI
#if os(iOS)
	import UIKit
#endif

struct BrowserSpacesBar: View {
	let browser: Browser
	let onSwipeProgress: (UUID?, Double) -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var spaceToDelete: BrowserSpace?
	@State private var showsDeleteAlert = false

	var body: some View {
		ScrollViewReader { reader in
			ScrollView(.horizontal) {
				HStack(spacing: 4) {
					ForEach(browser.workspace.spaces) { space in
						SpaceButtonView(
							browser: browser,
							space: space,
							isSelected: browser.workspace.selectedSpaceID == space.id,
							spaceToDelete: $spaceToDelete,
							showsDeleteAlert: $showsDeleteAlert
						)
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
				let index = browser.workspace.spaces.firstIndex(where: { $0.id == browser.workspace.selectedSpaceID }) ?? 0
				SpaceWheelReader(
					sidebarShown: browser.sidebarShown,
					hasPreviousSpace: index > 0,
					hasNextSpace: index < browser.workspace.spaces.count - 1
				) { amount, isComplete in
					handleSwipe(amount, isComplete: isComplete)
				}
				.allowsHitTesting(false)
			}
			#endif
			.onChange(of: browser.workspace.selectedSpaceID, initial: true) { _, id in
				withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
					reader.scrollTo(id, anchor: .center)
				}
			}
		}
		.frame(height: 25)
		.alert("Delete Space?", isPresented: $showsDeleteAlert, presenting: spaceToDelete) { space in
			Button(role: .destructive) {
				browser.deleteSpace(space.id)
			} label: {
				Label("Delete Space", systemImage: "trash")
			}
			Button(role: .cancel) {}
		} message: { space in
			Text("Tabs in \(space.name) will move to another Space.")
		}
	}

	private struct SpaceButtonView: View {
		let browser: Browser
		let space: BrowserSpace
		let isSelected: Bool
		@Binding var spaceToDelete: BrowserSpace?
		@Binding var showsDeleteAlert: Bool

		var body: some View {
			Button {
				browser.selectSpace(space.id)
			} label: {
				Label(space.name, systemImage: space.symbol)
					.labelStyle(.iconOnly)
					.frame(width: 25, height: 25)
					.background {
						if isSelected {
							RoundedRectangle(cornerRadius: 8)
								.fill(Color.primary.gradient)
								.opacity(0.4)
						}
					}
			}
			.buttonStyle(.plain)
			.contextMenu {
				Button("Edit Space", systemImage: "paintpalette") {
					browser.selectSpace(space.id)
					browser.openInternalPage(.themeEditor)
				}
				Button("Delete Space", systemImage: "trash", role: .destructive) {
					spaceToDelete = space
					showsDeleteAlert = true
				}
				.disabled(browser.workspace.spaces.count == 1)
			}
			.accessibilityLabel(space.name)
			.accessibilityAddTraits(isSelected ? .isSelected : [])
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

	#if os(macOS)
		private func handleSwipe(_ amount: CGFloat, isComplete: Bool) {
			guard abs(amount) > 0.001 else {
				onSwipeProgress(nil, 0)
				return
			}
			let spaces = browser.workspace.spaces
			guard let index = spaces.firstIndex(where: { $0.id == browser.workspace.selectedSpaceID }) else { return }
			let nextIndex = index + (amount > 0 ? 1 : -1)
			guard spaces.indices.contains(nextIndex) else {
				onSwipeProgress(nil, 0)
				return
			}
			onSwipeProgress(spaces[nextIndex].id, min(Double(abs(amount)), 1))
			if isComplete, abs(amount) >= 0.99 {
				browser.selectSpace(spaces[nextIndex].id)
				NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
			}
		}
	#endif
}
