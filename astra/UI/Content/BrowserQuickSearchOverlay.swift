import SwiftUI

/// Retains the former Spotlight new-tab chooser's shell and list styling, with
/// its own query and selection so opening commands cannot change a New Tab.
struct BrowserQuickSearchOverlay: View {
	let browser: Browser
	@State private var query = ""
	@State private var selectedID: String?
	@FocusState private var isSearchFocused: Bool

	private var actions: [BrowserSearchAction] {
		let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
		return BrowserSearchAction.paletteCatalogue(for: browser).filter { action in
			let searchable = ([action.title] + action.terms).joined(separator: " ")
			return terms.allSatisfy { searchable.localizedStandardContains($0) }
		}
	}

	private var selection: String? {
		if let selectedID, actions.contains(where: { $0.id == selectedID }) { return selectedID }
		return actions.first?.id
	}

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .top) {
				Button { browser.showsActionPalette = false } label: {
					Label("Dismiss Action Palette", systemImage: "xmark")
						.hidden()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.contentShape(Rectangle())
						.background(Color.black.opacity(0.15))
				}
				.buttonStyle(.plain)
				.keyboardShortcut(.cancelAction)
				.accessibilityLabel("Dismiss Action Palette")
				.accessibilityIdentifier("action-palette-dismiss")

				chooser
					.frame(width: min(640, max(0, geometry.size.width - 32)), height: min(440, max(0, geometry.size.height - 48)))
					.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
					.padding(.top, min(80, geometry.size.height * 0.12))
					.accessibilityIdentifier("action-palette-overlay")
			}
			.onKeyPress(.escape) {
				browser.showsActionPalette = false
				return .handled
			}
		}
		.task {
			await Task.yield()
			isSearchFocused = true
		}
	}

	private var chooser: some View {
		ScrollViewReader { proxy in
			List {
				Section("Browser Actions") {
					ForEach(actions) { action in
						Button { perform(action) } label: {
							Label {
								VStack(alignment: .leading, spacing: 2) {
									Text(verbatim: action.title).lineLimit(1)
									Text(verbatim: action.detail)
										.font(.caption)
										.foregroundStyle(.secondary)
										.lineLimit(1)
								}
								.frame(maxWidth: .infinity, alignment: .leading)
							} icon: {
								Image(systemName: action.symbol).frame(width: 20, height: 20)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.listRowBackground(Color.primary.opacity(selection == action.id ? 0.12 : 0))
						.accessibilityAddTraits(selection == action.id ? [.isSelected] : [])
						.accessibilityIdentifier("action-palette-result-\(action.id)")
						.id(action.id)
					}
					if actions.isEmpty {
						Text("No matching actions")
							.foregroundStyle(.secondary)
							.accessibilityIdentifier("action-palette-empty")
					}
				}
			}
			.listStyle(.sidebar)
			.scrollContentBackground(.hidden)
			.safeAreaBar(edge: .top) { searchHeader }
			.onChange(of: selection) { _, id in
				if let id { proxy.scrollTo(id) }
			}
		}
		.frame(maxWidth: 680)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var searchHeader: some View {
		HStack(spacing: 10) {
			Image(systemName: "magnifyingglass").accessibilityHidden(true)
			TextField("Search browser actions", text: $query)
				.focused($isSearchFocused)
				.textFieldStyle(.plain)
				.fontDesign(.monospaced)
				.onChange(of: query) { _, _ in selectedID = nil }
				.onSubmit {
					if let action = actions.first(where: { $0.id == selection }) { perform(action) }
				}
				.onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
				.onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
				.accessibilityLabel("Search browser actions")
				.accessibilityIdentifier("action-palette-search")
		}
		.padding(14)
		.glassEffect(.regular, in: RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar))
		.padding(.horizontal, 24)
		.padding(.top, 16)
		.padding(.bottom, 16)
	}

	private func moveSelection(by delta: Int) {
		let results = actions
		guard !results.isEmpty else { return }
		let index = results.firstIndex(where: { $0.id == selection }) ?? 0
		selectedID = results[(index + delta + results.count) % results.count].id
	}

	private func perform(_ action: BrowserSearchAction) {
		browser.showsActionPalette = false
		action.perform()
	}
}
