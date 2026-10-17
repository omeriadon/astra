#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME
	import SwiftUI

	struct BoostsLibraryView: View {
		let browser: Browser
		@State private var store = BrowserBoostStore.shared

		var body: some View {
			List {
				ForEach(store.boosts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { boost in
					HStack(spacing: 10) {
						Button {
							store.toggle(boost.id)
						} label: {
							HStack(spacing: 10) {
								Image(systemName: boost.isEnabled ? "checkmark.circle.fill" : "circle")
									.foregroundStyle(boost.isEnabled ? Color.accentColor : .secondary)
									.frame(width: 20)
								VStack(alignment: .leading, spacing: 2) {
									Text(boost.name)
										.font(.subheadline)
										.lineLimit(1)
									Text(boost.domain ?? "All websites")
										.font(.caption)
										.foregroundStyle(.secondary)
										.lineLimit(1)
								}
								Spacer(minLength: 0)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.accessibilityLabel("\(boost.name), \(boost.isEnabled ? "Enabled" : "Disabled")")
						.accessibilityHint("Toggle Boost")
						.accessibilityIdentifier("boost-toggle-\(boost.id)")

						Button("Edit Boost", systemImage: "square.and.pencil") {
							BrowserBoostEditorWindowController.open(boost.id)
						}
						.labelStyle(.iconOnly)
						.buttonStyle(.borderless)
						.accessibilityIdentifier("boost-edit-\(boost.id)")
					}
					.padding(.vertical, 3)
					.contextMenu {
						Button("Edit Boost", systemImage: "square.and.pencil") {
							BrowserBoostEditorWindowController.open(boost.id)
						}
						Button(boost.isEnabled ? "Disable Boost" : "Enable Boost") {
							store.toggle(boost.id)
						}
						Divider()
						Button("Delete Boost", systemImage: "trash", role: .destructive) {
							remove(boost.id)
						}
					}
					.swipeActions(edge: .trailing, allowsFullSwipe: true) {
						Button("Delete", systemImage: "trash", role: .destructive) {
							remove(boost.id)
						}
					}
					.accessibilityIdentifier("boost-row-\(boost.id)")
				}
			}
			.scrollContentBackground(.hidden)
			.overlay {
				if store.boosts.isEmpty {
					ContentUnavailableView("No Boosts", systemImage: "curlybraces")
				}
			}
			.safeAreaInset(edge: .bottom, spacing: 0) {
				HStack {
					Text("\(store.boosts.count) Boosts")
						.foregroundStyle(.secondary)
					Spacer()
					Button("New Boost", systemImage: "plus") {
						let boost = store.create(domain: browser.selectedTab?.currentURL?.host)
						BrowserBoostEditorWindowController.open(boost.id)
					}
					.labelStyle(.iconOnly)
					.accessibilityIdentifier("boost-create-library")
				}
				.padding(10)
				.background(.regularMaterial)
			}
			.accessibilityIdentifier("boosts-library")
		}

		private func remove(_ id: UUID) {
			BrowserBoostEditorWindowController.close(id)
			store.delete(id)
		}
	}
#endif
