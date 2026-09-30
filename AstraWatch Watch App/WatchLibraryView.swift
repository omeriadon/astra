import SwiftUI

struct WatchLibraryView: View {
	@State private var connection = WatchLibraryConnection.shared
	@State private var browser = WatchBrowser()
	@State private var selectedPage = "bookmarks"
	@State private var didSelectInitialPage = false
	@Environment(\.scenePhase) private var scenePhase

	var body: some View {
		Group {
			if let library = connection.library {
				TabView(selection: $selectedPage) {
					page(title: "Bookmarks", symbol: "book.closed.fill", theme: library.spaces.first?.theme ?? BrowserTheme()) {
						links(library.bookmarks, symbol: "bookmark.fill")
					}
					.tag("bookmarks")
					.accessibilityIdentifier("watch.bookmarks")

					ForEach(library.spaces) { space in
						page(title: space.name, symbol: space.symbol, theme: space.theme) {
							Section("Pinned") {
								links(space.pinned, symbol: "pin.fill")
							}
							Section("Favourites") {
								links(space.favourites, symbol: "star.fill")
							}
							Section("Today") {
								links(space.today, symbol: "globe")
							}
						}
						.tag(space.id.uuidString)
						.accessibilityIdentifier("watch.space.\(space.id)")
					}
				}
				.tabViewStyle(.page)
			} else {
				ContentUnavailableView {
					Label("Your Spaces", systemImage: "circle.grid.2x2.fill")
				} description: {
					Text(connection.errorDescription ?? "Open Astra on your paired iPhone to sync spaces and bookmarks.")
				}
			}
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .active {
				connection.refresh()
			}
		}
		.onChange(of: connection.library?.spaces.map(\.id), initial: true) { _, ids in
			if !didSelectInitialPage, let ids {
				selectedPage = ids.first?.uuidString ?? "bookmarks"
				didSelectInitialPage = true
			}
			if selectedPage != "bookmarks", !(ids ?? []).contains(where: { $0.uuidString == selectedPage }) {
				selectedPage = "bookmarks"
			}
		}
		.alert("Unable to Open Website", isPresented: Binding(
			get: { browser.errorDescription != nil },
			set: {
				if !$0 {
					browser.errorDescription = nil
				}
			}
		)) {
			Button(role: .cancel) {
				browser.errorDescription = nil
			}
			.accessibilityLabel("Dismiss website error")
			.accessibilityIdentifier("watch.dismissWebsiteError")
		} message: {
			Text(browser.errorDescription ?? "")
		}
	}

	private func page(
		title: String,
		symbol: String,
		theme: BrowserTheme,
		@ViewBuilder content: () -> some View
	) -> some View {
		List {
			Label(title, systemImage: symbol)
				.font(.headline)
				.accessibilityAddTraits(.isHeader)
				.listRowBackground(Color.clear)
			content()
			if let error = connection.errorDescription {
				Text(error)
					.font(.caption)
			}
		}
		.listStyle(.carousel)
		.scrollContentBackground(.hidden)
		.background {
			MeshGradientSurface(points: theme.meshColorPoints)
				.opacity(theme.meshOpacity)
				.background(theme.firstColor.color)
				.overlay(theme.contentShade(for: theme.appearanceMode == .light ? .light : .dark))
				.ignoresSafeArea()
		}
		.foregroundStyle(theme.foregroundColor)
		.preferredColorScheme(theme.appearanceMode == .light ? .light : .dark)
	}

	@ViewBuilder
	private func links(_ links: [WatchLink], symbol: String) -> some View {
		if links.isEmpty {
			Text("No links")
				.font(.caption)
				.listRowBackground(Color.clear)
		} else {
			ForEach(links) { link in
				WatchLinkRow(link: link, symbol: symbol, browser: browser)
			}
		}
	}
}
