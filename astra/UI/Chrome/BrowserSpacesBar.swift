import SwiftUI

struct BrowserSpacesBar: View {
	let browser: Browser
	var onOpenPage: (() -> Void)?
	var onToggleSpacePicker: (() -> Void)?
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var spaceToDelete: BrowserSpace?
	@State private var showsDeleteAlert = false
	@Namespace private var selectionAnimation

	var body: some View {
		#if os(macOS)
			Button {
				onToggleSpacePicker?()
			} label: {
				Label(browser.selectedSpace.name, systemImage: browser.selectedSpace.symbol)
					.lineLimit(1)
					.frame(maxWidth: .infinity, alignment: .leading)
					.frame(height: 25)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Switch Space")
			.accessibilityValue(browser.selectedSpace.name)
			.accessibilityIdentifier("space-picker-button")
		#else
			ScrollViewReader { reader in
				ScrollView(.horizontal) {
					HStack(spacing: 4) {
						ForEach(browser.workspace.spaces) { space in
							SpaceButtonView(
								browser: browser,
								space: space,
								isSelected: browser.workspace.selectedSpaceID == space.id,
								spaceToDelete: $spaceToDelete,
								showsDeleteAlert: $showsDeleteAlert,
								selectionNamespace: selectionAnimation,
								onOpenPage: onOpenPage
							)
						}
					}
					#if os(macOS)
					.animation(reduceMotion ? nil : .smooth(duration: 0.25), value: browser.workspace.selectedSpaceID)
					#endif
				}
				.scrollIndicators(.hidden)
				.onChange(of: browser.workspace.selectedSpaceID, initial: true) { _, id in
					withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
						reader.scrollTo(id, anchor: .center)
					}
				}
			}
			#if os(iOS)
			.frame(height: 44)
			#else
			.frame(height: 25)
			#endif
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
		#endif
	}

	private struct SpaceButtonView: View {
		let browser: Browser
		let space: BrowserSpace
		let isSelected: Bool
		@Binding var spaceToDelete: BrowserSpace?
		@Binding var showsDeleteAlert: Bool
		let selectionNamespace: Namespace.ID
		var onOpenPage: (() -> Void)?

		var body: some View {
			Button {
				browser.selectSpace(space.id)
			} label: {
				Label(space.name, systemImage: space.symbol)
					.labelStyle(.iconOnly)
				#if os(iOS)
					.frame(width: 44, height: 44)
				#else
					.frame(width: 25, height: 25)
				#endif
					.background {
						if isSelected {
							RoundedRectangle(cornerRadius: 8)
								.fill(Color.primary.gradient)
								.opacity(0.4)
							#if os(macOS)
								.matchedGeometryEffect(id: "selected-space-highlight", in: selectionNamespace)
							#endif
						}
					}
			}
			.buttonStyle(.plain)
			.contextMenu {
				Button("Edit Space", systemImage: "paintpalette") {
					browser.selectSpace(space.id)
					browser.openInternalPage(.themeEditor)
					onOpenPage?()
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
}

#if os(macOS)
	struct BrowserSpacePickerPanel: View {
		let browser: Browser
		let maximumHeight: CGFloat
		let onDismiss: () -> Void
		@State private var spaceToDelete: BrowserSpace?
		@State private var showsDeleteAlert = false

		var body: some View {
			VStack(spacing: 4) {
				spaceList
				Button {
					browser.createSpace()
					onDismiss()
				} label: {
					Label("Add Space", systemImage: "plus")
						.labelStyle(.iconOnly)
						.frame(width: 25, height: 20)
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Add Space")
				.accessibilityIdentifier("space-picker-add")
			}
			.padding(6)
			.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
			.accessibilityIdentifier("space-picker-panel")
			.onExitCommand(perform: onDismiss)
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

		@ViewBuilder
		private var spaceList: some View {
			if #available(macOS 27, *) {
				ScrollView {
					LazyVStack(spacing: 2) {
						ForEach(browser.workspace.spaces) { space in
							spaceRow(space)
						}
						.reorderable()
					}
					.padding(4)
				}
				.frame(height: min(CGFloat(browser.workspace.spaces.count) * 28 + 8, max(0, maximumHeight - 36)))
				.reorderContainer(for: BrowserSpace.self) { difference in
					switch difference.destination.position {
						case let .before(destinationID):
							browser.reorderSpaces(difference.sources, before: destinationID)
						case .end:
							browser.reorderSpaces(difference.sources, before: nil)
					}
				}
			} else {
				List {
					ForEach(browser.workspace.spaces) { space in
						spaceRow(space)
							.listRowInsets(EdgeInsets())
							.listRowSeparator(.hidden)
							.listRowBackground(Color.clear)
					}
					.onMove { offsets, destination in
						let ids = offsets.sorted().compactMap { index in
							browser.workspace.spaces.indices.contains(index)
								? browser.workspace.spaces[index].id
								: nil
						}
						let removedBeforeDestination = offsets.filter { $0 < destination }.count
						let adjustedDestination = max(0, destination - removedBeforeDestination)
						let remaining = browser.workspace.spaces.enumerated()
							.filter { !offsets.contains($0.offset) }
						let destinationID = remaining.dropFirst(adjustedDestination).first?.element.id
						browser.reorderSpaces(ids, before: destinationID)
					}
				}
				.frame(height: min(CGFloat(browser.workspace.spaces.count) * 28 + 8, max(0, maximumHeight - 36)))
				.listStyle(.plain)
				.scrollContentBackground(.hidden)
			}
		}

		private func spaceRow(_ space: BrowserSpace) -> some View {
			let isSelected = browser.workspace.selectedSpaceID == space.id
			return Button {
				browser.selectSpace(space.id)
				onDismiss()
			} label: {
				HStack(spacing: 8) {
					Image(systemName: space.symbol)
						.frame(width: 16)
					Text(space.name)
						.lineLimit(1)
					Spacer(minLength: 4)
					if isSelected {
						Image(systemName: "checkmark")
							.font(.caption.weight(.semibold))
					}
				}
				.padding(.horizontal, 7)
				.frame(height: 26)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.contentShape(Rectangle())
			.accessibilityLabel(space.name)
			.accessibilityAddTraits(isSelected ? .isSelected : [])
			.accessibilityIdentifier("space-picker-\(space.id.uuidString)")
			.contextMenu {
				Button("Edit Space", systemImage: "paintpalette") {
					browser.selectSpace(space.id)
					browser.openInternalPage(.themeEditor)
					onDismiss()
				}
				Button("Delete Space", systemImage: "trash", role: .destructive) {
					spaceToDelete = space
					showsDeleteAlert = true
				}
				.disabled(browser.workspace.spaces.count == 1)
			}
			.background {
				BrowserDropZone(browser: browser, area: .normal, spaceID: space.id, beforeTabID: nil)
			}
		}
	}
#endif
