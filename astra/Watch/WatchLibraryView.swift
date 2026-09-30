import AuthenticationServices
import SwiftUI

struct WatchLibraryView: View {
	@State private var connection = WatchLibrarySync()
	@State private var browser = WatchBrowser()
	@State private var selectedPage = "bookmarks"
	@State private var didSelectInitialPage = false
	@Environment(\.scenePhase) private var scenePhase

	var body: some View {
		Group {
			if !connection.isSignedIn {
				List {
					Section("Account") {
						SignInWithAppleButton(.signIn) { _ in
						} onCompletion: { result in
							Task { await connection.signIn(result: result) }
						}
						.frame(height: 44)
						.disabled(connection.isLoading)
						.accessibilityLabel("Sign in with Apple")
						.accessibilityIdentifier("watch.signInWithApple")
						if connection.isLoading {
							ProgressView("Signing In")
						}
						if let error = connection.errorDescription {
							Text(error)
								.accessibilityIdentifier("watch.syncError")
						}
					}
				}
				.listStyle(.carousel)
			} else if let library = connection.library {
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
					Text(connection.errorDescription ?? "Loading your spaces and bookmarks from the server.")
				} actions: {
					accountControls
				}
			}
		}
		.task { await connection.restoreSession() }
		.onChange(of: scenePhase) { _, phase in
			if phase == .active {
				Task { await connection.refresh() }
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

	@ViewBuilder
	private var accountControls: some View {
		Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
			Task { await connection.refresh() }
		}
		.disabled(connection.isLoading)
		.accessibilityLabel("Refresh from server")
		.accessibilityIdentifier("watch.refresh")
		Button(role: .destructive) {
			connection.signOut()
		} label: {
			Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
		}
		.disabled(connection.isLoading)
		.accessibilityLabel("Sign out")
		.accessibilityIdentifier("watch.signOut")
		if connection.isLoading {
			ProgressView("Syncing")
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
			Section("Account") {
				accountControls
			}
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
