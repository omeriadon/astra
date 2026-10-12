import SwiftUI

struct BrowserSpacesBar: View {
	let browser: Browser
	var onOpenPage: (() -> Void)?
	var onRequestDeleteSpace: ((BrowserSpace) -> Void)?
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var spaceToDelete: BrowserSpace?
	@State private var showsDeleteAlert = false
	@State private var showsSpacePicker = false
	@Namespace private var selectionAnimation

	var body: some View {
		#if os(macOS)
			Button {
				showsSpacePicker.toggle()
			} label: {
				HStack {
					Label(browser.selectedSpace.name, systemImage: browser.selectedSpace.symbol)
						.lineLimit(1)
						.contentShape(Rectangle())
						.popover(isPresented: $showsSpacePicker, arrowEdge: .bottom) {
							BrowserSpacePickerPopover(
								browser: browser,
								onDismiss: { showsSpacePicker = false },
								onRequestDeleteSpace: { space in
									onRequestDeleteSpace?(space)
								}
							)
						}
					Spacer()
				}
				.frame(height: 25)
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
	struct BrowserSpacePickerPopover: View {
		let browser: Browser
		let onDismiss: () -> Void
		let onRequestDeleteSpace: (BrowserSpace) -> Void

		var body: some View {
			VStack(alignment: .trailing, spacing: 8) {
				spaceList

				Button {
					browser.createSpace()
					onDismiss()
				} label: {
					Label("Add Space", systemImage: "plus")
						.labelStyle(.iconOnly)
				}
				.buttonStyle(.glass)
				.buttonBorderShape(.roundedRectangle)
				.frame(width: 20, height: 20)
				.padding(.trailing, 2)
				.padding(.bottom, 1)
				.accessibilityLabel("Add Space")
				.accessibilityIdentifier("space-picker-add")
			}
			.padding(11)
			.frame(width: 250)
			.fixedSize(horizontal: false, vertical: true)
			.accessibilityIdentifier("space-picker-panel")
			.onExitCommand(perform: onDismiss)
		}

		@ViewBuilder
		private var spaceList: some View {
			if #available(macOS 27, *) {
				// Native swipe and reorder actions work directly in this
				// content-sized stack; no scroll view or height cap is needed.
				VStack(spacing: 4) {
					ForEach(browser.workspace.spaces) { space in
						spaceRow(space)
							.swipeActions(edge: .trailing, allowsFullSwipe: false) {
								if browser.workspace.spaces.count > 1 {
									Button {
										requestSpaceDeletion(space)
									} label: {
										Label("Delete Space", systemImage: "trash")
									}
									.tint(.red)
								}
							} onPresentationChanged: { _ in }
					}
					.reorderable()
				}
				.swipeActionsContainer()
				.reorderContainer(for: BrowserSpace.self) { difference in
					switch difference.destination.position {
						case let .before(destinationID):
							browser.reorderSpaces(difference.sources, before: destinationID)
						case .end:
							browser.reorderSpaces(difference.sources, before: nil)
					}
				}
			} else {
				// Preserve List reordering on older macOS versions without
				// limiting the number of rows shown in the popover.
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
				.frame(height: CGFloat(browser.workspace.spaces.count) * 36 + 8)
				.listStyle(.plain)
				.scrollDisabled(true)
				.scrollContentBackground(.hidden)
			}
		}

		private func requestSpaceDeletion(_ space: BrowserSpace) {
			guard browser.workspace.spaces.count > 1 else { return }
			onDismiss()
			// Let the popover close before the shell presents its own alert.
			Task { @MainActor in
				await Task.yield()
				onRequestDeleteSpace(space)
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
				.padding(.horizontal, 10)
				.frame(height: 32)
				.contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
			}
			.buttonStyle(.plain)
			.foregroundStyle(space.theme.foregroundColor)
			.background {
				let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
				shape.fill(.ultraThinMaterial)
				ThemeSurface(theme: space.theme)
					.clipShape(shape)
			}
			.overlay {
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.strokeBorder(
						space.theme.foregroundColor.opacity(isSelected ? 0.4 : 0.12),
						lineWidth: isSelected ? 1.25 : 0.5
					)
					.allowsHitTesting(false)
			}
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
					requestSpaceDeletion(space)
				}
				.disabled(browser.workspace.spaces.count == 1)
			}
			.background {
				BrowserDropZone(browser: browser, area: .normal, spaceID: space.id, beforeTabID: nil)
			}
		}
	}
#endif
