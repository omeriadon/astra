import SwiftUI

struct BrowserSpacePager<Content: View>: View {
	let spaces: [BrowserSpace]
	let selectedSpaceID: UUID
	let favouriteTabIDs: [UUID]
	let scrollState: BrowserSpaceScrollState
	let onSelectSpace: (UUID) -> Void
	let content: (BrowserSpace, Bool, [UUID]) -> Content

	@State private var scrollPosition = ScrollPosition(idType: UUID.self)
	@State private var scrollPhase = ScrollPhase.idle
	@State private var userScrollPending = false
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	init(
		spaces: [BrowserSpace],
		selectedSpaceID: UUID,
		favouriteTabIDs: [UUID],
		scrollState: BrowserSpaceScrollState,
		onSelectSpace: @escaping (UUID) -> Void,
		@ViewBuilder content: @escaping (BrowserSpace, Bool, [UUID]) -> Content
	) {
		self.spaces = spaces
		self.selectedSpaceID = selectedSpaceID
		self.favouriteTabIDs = favouriteTabIDs
		self.scrollState = scrollState
		self.onSelectSpace = onSelectSpace
		self.content = content
		_scrollPosition = State(initialValue: ScrollPosition(id: selectedSpaceID, anchor: .center))
	}

	var body: some View {
		ScrollView(.horizontal) {
			HStack(spacing: 0) {
				ForEach(spaces) { space in
					// The page container is the horizontal target around its native vertical scroll view.
					VStack(spacing: 0) {
						content(space, space.id == selectedSpaceID, favouriteTabIDs)
					}
					.containerRelativeFrame(.horizontal)
					.id(space.id)
					.allowsHitTesting(space.id == selectedSpaceID)
					.accessibilityHidden(space.id != selectedSpaceID)
				}
			}
			.scrollTargetLayout()
		}
		.scrollIndicators(.hidden)
		.scrollTargetBehavior(.paging)
		.scrollPosition($scrollPosition, anchor: .center)
		.onScrollGeometryChange(for: Double.self) { geometry in
			Self.pagePosition(in: geometry)
		} action: { _, position in
			var transaction = Transaction(animation: nil)
			transaction.disablesAnimations = true
			withTransaction(transaction) {
				scrollState.position = min(max(position, 0), Double(max(spaces.count - 1, 0)))
			}
			selectSettledSpace(at: position)
		}
		.onScrollPhaseChange { _, phase, context in
			scrollPhase = phase
			if phase == .interacting {
				userScrollPending = true
			} else if phase == .animating {
				userScrollPending = false
			}
			selectSettledSpace(at: Self.pagePosition(in: context.geometry))
		}
		.onChange(of: selectedSpaceID, initial: true) { oldID, id in
			if oldID != id, let index = spaces.firstIndex(where: { $0.id == id }),
			   let position = scrollState.position, abs(position - Double(index)) < 0.001
			{
				return
			}
			withAnimation(reduceMotion || oldID == id ? nil : .smooth(duration: 0.3)) {
				scrollPosition.scrollTo(id: id, anchor: .center)
			}
		}
		.onChange(of: spaces.map(\.id)) { _, _ in
			// Membership changes keep the selected space aligned without rebuilding its page.
			var transaction = Transaction(animation: nil)
			transaction.disablesAnimations = true
			withTransaction(transaction) {
				scrollPosition.scrollTo(id: selectedSpaceID, anchor: .center)
			}
		}
	}

	private func selectSettledSpace(at position: Double) {
		guard userScrollPending, scrollPhase == .idle, !spaces.isEmpty,
		      abs(position - position.rounded()) < 0.001 else { return }
		userScrollPending = false
		let index = min(max(Int(position.rounded()), 0), spaces.count - 1)
		let id = spaces[index].id
		guard id != selectedSpaceID else { return }
		onSelectSpace(id)
	}

	private static func pagePosition(in geometry: ScrollGeometry) -> Double {
		guard geometry.containerSize.width > 0 else { return 0 }
		return Double((geometry.contentOffset.x + geometry.contentInsets.leading) / geometry.containerSize.width)
	}
}
