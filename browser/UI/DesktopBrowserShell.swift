import Haze
import SwiftUI
import WebKit

let topBarItemWidth: CGFloat = 8
let topBarItemHeight: CGFloat = 14

let topHeight: CGFloat = 33

struct TopBarButton: Identifiable {
	let title: String
	let systemImage: String
	let accessibilityIdentifier: String
	let isDisabled: Bool
	let action: () -> Void
	let modifier: String

	var id: String {
		accessibilityIdentifier
	}
}

struct DesktopBrowserShell: View {
	let browser: Browser
	@Environment(\.colorScheme) private var colorScheme
	@AppStorage("addressDisplayStyle") private var addressDisplayStyle = AddressDisplayStyle.simple.rawValue
	@State private var sidebarShown = true
	@State private var addressText = ""
	@State private var addressSelection: TextSelection?
	@FocusState private var addressFieldFocused: Bool
	#if os(macOS)
		@AppStorage("tabSwitchingOrder") private var tabSwitchingOrder = TabSwitchingOrder.visibleTabList.rawValue
		@State private var controlTabSwitcher: ControlTabSwitcher
	#endif

	init(browser: Browser) {
		self.browser = browser
		#if os(macOS)
			_controlTabSwitcher = State(initialValue: ControlTabSwitcher(browser: browser))
		#endif
	}

	private var navigationButtons: [TopBarButton] {
		[
			TopBarButton(
				title: "Back",
				systemImage: "chevron.backward",
				accessibilityIdentifier: "browser-back",
				isDisabled: !(browser.selectedTab?.controller.canGoBack ?? false),
				action: { browser.selectedTab?.controller.goBack() },
				modifier: "["
			),
			TopBarButton(
				title: "Forward",
				systemImage: "chevron.forward",
				accessibilityIdentifier: "browser-forward",
				isDisabled: !(browser.selectedTab?.controller.canGoForward ?? false),
				action: { browser.selectedTab?.controller.goForward() },
				modifier: "]"
			),
			TopBarButton(
				title: "Refresh",
				systemImage: "arrow.clockwise",
				accessibilityIdentifier: "browser-reload",
				isDisabled: false,
				action: { browser.selectedTab?.controller.reload() },
				modifier: "R"
			),
		]
	}

	private var topBar: some View {
		HStack {
			HStack(spacing: 0) {
				Spacer()
					.frame(width: 85)

				Button {
					sidebarShown.toggle()
				} label: {
					Label("Toggle Sidebar", systemImage: "sidebar.leading")
						.labelStyle(.iconOnly)
						.frame(width: topBarItemWidth, height: topBarItemHeight)
				}
				.controlSize(.regular)
				.buttonSizing(.fitted)
				.keyboardShortcut("S", modifiers: .command)
				.buttonStyle(.bordered)
				.clipShape(RoundedRectangle(cornerRadius: 8))
				.accessibilityIdentifier("sidebar-toggle")
			}
			.frame(width: sidebarShown ? 224 : 125, alignment: .leading)

			HStack(spacing: 6) {
				ForEach(navigationButtons) { item in
					Button(action: item.action) {
						Label(item.title, systemImage: item.systemImage)
							.labelStyle(.iconOnly)
							.frame(width: topBarItemWidth, height: topBarItemHeight)
					}
					.keyboardShortcut(KeyEquivalent(item.modifier.first!), modifiers: .command)
					.disabled(item.isDisabled)
					.controlSize(.regular)
					.buttonSizing(.fitted)
					.clipShape(RoundedRectangle(cornerRadius: 8))
					.buttonStyle(.bordered)
					.accessibilityIdentifier(item.accessibilityIdentifier)
				}

				TextField("", text: $addressText, selection: $addressSelection)
					.textFieldStyle(.plain)
					.lineLimit(1)
					.foregroundStyle(isDimmedAddress ? .clear : .primary)
					.focused($addressFieldFocused)
					.submitLabel(.go)
					.onSubmit(submitAddress)
					.overlay(alignment: .leading) {
						if isDimmedAddress {
							Text(dimmedAddressText)
								.lineLimit(1)
								.allowsHitTesting(false)
								.accessibilityHidden(true)
						}
					}
					.accessibilityLabel("Address")
					.accessibilityIdentifier("browser-address")

				Spacer()
			}
			.padding(.leading, sidebarShown ? 1.5 : 20)
			.padding(.top, sidebarShown ? 8 : 0)
		}
		.frame(width: nil, height: topHeight, alignment: .center)
		.animation(.smooth(duration: 0.3), value: sidebarShown)
	}

	private var topBarColorScheme: ColorScheme {
		guard let themeColorIsLight = browser.selectedTab?.controller.themeColorIsLight else { return colorScheme }
		return themeColorIsLight ? .light : .dark
	}

	var body: some View {
		BrowserSplitView(sidebarShown: $sidebarShown) {
			ZStack(alignment: .top) {
				ScrollView {
					LazyVStack(spacing: 5) {
						ForEach(browser.tabs) { tab in
							BrowserTabRow(
								tab: tab,
								isSelected: browser.selectedTabID == tab.id,
								onSelect: browser.selectTab,
								onClose: browser.closeTab
							)
						}

						Spacer(minLength: 0)

						Button("New Tab", systemImage: "plus") {
							browser.addTab()
							addressText = ""
							addressSelection = TextSelection(range: addressText.startIndex ..< addressText.endIndex)
							addressFieldFocused = true
						}
						.keyboardShortcut("T", modifiers: .command)
						.padding(.leading, 8)
						.buttonStyle(.plain)
						.frame(maxWidth: .infinity, alignment: .leading)
						.accessibilityIdentifier("new-tab")
					}
					.padding(.horizontal, 7)
					.padding(.top, 35)
				}

				HazeEffect(
					maskProvider: LinearGradientMaskProvider(
						startPoint: .top,
						endPoint: .bottom,
						startOpacity: 1,
						endOpacity: 0,
						isSmooth: true
					),
					maxBlurRadius: 2
				)
				.frame(height: topHeight)
				.frame(maxWidth: .infinity)
			}

		} content: {
			ZStack(alignment: .top) {
				BrowserContentView(
					browser: browser,
					insets: BrowserViewportInsets(
						obscured: EdgeInsets(top: topHeight, leading: 0, bottom: 0, trailing: 0),
						minimum: EdgeInsets(top: topHeight, leading: 0, bottom: 0, trailing: 0),
						maximum: EdgeInsets(top: topHeight, leading: 0, bottom: 0, trailing: 0)
					)
				)

				HazeEffect(
					maskProvider: LinearGradientMaskProvider(
						startPoint: .top,
						endPoint: .bottom,
						startOpacity: 1.0,
						endOpacity: 1.0,
						isSmooth: false
					),
					maxBlurRadius: 6
				)
				.frame(height: topHeight)
				.frame(maxWidth: .infinity)
				.overlay {
					if let themeColor = browser.selectedTab?.controller.themeColor {
						themeColor.opacity(0.6)
					}
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: sidebarShown ? 13 : 16))
			.animation(.smooth(duration: 0.3)) { view in
				view
					.padding(sidebarShown ? 4 : 0)
			}
			.shadow(color: browser.selectedTab?.controller.themeColor?.opacity(0.8) ?? .black.opacity(0.8), radius: 11)
		}
		.background(.blue)
		.overlay(alignment: .top) {
			topBar
				.environment(\.colorScheme, topBarColorScheme)
		}
		#if os(macOS)
		.overlay {
			ControlTabSwitcherPreview(browser: browser, switcher: controlTabSwitcher)
				.animation(.easeInOut(duration: 0.05), value: controlTabSwitcher.isPreviewVisible)
		}
		.onAppear {
			controlTabSwitcher.start(order: TabSwitchingOrder(rawValue: tabSwitchingOrder) ?? .visibleTabList)
		}
		.onChange(of: tabSwitchingOrder) { _, value in
			controlTabSwitcher.start(order: TabSwitchingOrder(rawValue: value) ?? .visibleTabList)
		}
		.onChange(of: browser.tabs.map(\.id)) { _, _ in
			controlTabSwitcher.tabsDidChange()
		}
		.onDisappear {
			controlTabSwitcher.stop()
		}
		#endif
		.onChange(of: browser.selectedTabID) { _, _ in
			addressText = addressDisplayString(for: browser.selectedTab?.controller.url)
			if addressFieldFocused {
				addressSelection = TextSelection(range: addressText.startIndex ..< addressText.endIndex)
			}
		}
		.onChange(of: browser.selectedTab?.controller.url) { _, url in
			guard !addressFieldFocused else { return }
			addressText = addressDisplayString(for: url)
		}
		.onChange(of: addressDisplayStyle) { _, _ in
			addressText = addressDisplayString(for: browser.selectedTab?.controller.url)
		}
		.onChange(of: addressFieldFocused) { _, _ in
			addressText = addressDisplayString(for: browser.selectedTab?.controller.url)
		}
		.ignoresSafeArea()
		.onAppear {
			addressText = addressDisplayString(for: browser.selectedTab?.controller.url)
		}
	}

	private func submitAddress() {
		guard let destination = Self.destination(for: addressText) else { return }
		browser.selectedTab?.controller.load(destination)
		addressText = addressDisplayString(for: destination)
		addressFieldFocused = false
	}

	private func addressDisplayString(for url: URL?) -> String {
		guard let url else { return "" }
		let style = AddressDisplayStyle(rawValue: addressDisplayStyle) ?? .simple
		if style == .full {
			return url.absoluteString
		}

		if let query = Self.googleSearchQuery(for: url) {
			return query
		}

		if !addressFieldFocused, style == .simple {
			return Self.hostWithoutWWW(for: url) ?? url.absoluteString
		}

		if !addressFieldFocused, style == .dimmed {
			return Self.urlWithoutWWW(for: url)
		}

		return url.absoluteString
	}

	private var isDimmedAddress: Bool {
		addressDisplayStyle == AddressDisplayStyle.dimmed.rawValue && !addressFieldFocused
	}

	private var dimmedAddressText: AttributedString {
		var text = AttributedString(addressText)
		text.foregroundColor = Color.primary.opacity(0.2)
		guard let url = browser.selectedTab?.controller.url,
		      Self.googleSearchQuery(for: url) == nil,
		      let components = URLComponents(string: addressText),
		      let host = components.host,
		      let schemeEnd = addressText.range(of: "://")?.upperBound
		else {
			text.foregroundColor = .primary
			return text
		}

		let authorityEnd = addressText[schemeEnd...].firstIndex(where: { "/?#".contains($0) }) ?? addressText.endIndex
		let authorityRange = schemeEnd ..< authorityEnd
		if let hostRange = addressText.range(of: host, options: .caseInsensitive, range: authorityRange),
		   let attributedHostRange = Range(hostRange, in: text)
		{
			text[attributedHostRange].foregroundColor = .primary
		}

		if let pathRange = addressText.range(of: components.percentEncodedPath, range: authorityEnd ..< addressText.endIndex),
		   let attributedPathRange = Range(pathRange, in: text)
		{
			text[attributedPathRange].foregroundColor = .primary
		}
		return text
	}

	private static func hostWithoutWWW(for url: URL) -> String? {
		guard let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host else { return nil }
		return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
	}

	private static func urlWithoutWWW(for url: URL) -> String {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let host = components.host,
		      host.lowercased().hasPrefix("www.")
		else { return url.absoluteString }
		var output = url.absoluteString
		guard let schemeEnd = output.range(of: "://")?.upperBound else { return output }
		let authorityEnd = output[schemeEnd...].firstIndex(where: { "/?#".contains($0) }) ?? output.endIndex
		guard
			let hostRange = output.range(of: host, options: .caseInsensitive, range: schemeEnd ..< authorityEnd)
		else { return output }
		output.replaceSubrange(hostRange, with: String(host.dropFirst(4)))
		return output
	}

	private static func googleSearchQuery(for url: URL) -> String? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let host = components.host?.lowercased(),
		      isGoogleHost(host),
		      components.path == "/search",
		      let encodedQuery = components.percentEncodedQueryItems?.first(where: { $0.name == "q" })?.value,
		      let query = encodedQuery.replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
		      !query.isEmpty
		else { return nil }
		return query
	}

	private static func isGoogleHost(_ host: String) -> Bool {
		let labels = host.split(separator: ".")
		guard let googleIndex = labels.lastIndex(of: "google"), googleIndex + 1 < labels.count else { return false }
		let domainSuffix = labels[googleIndex...]
		let region = Array(domainSuffix.dropFirst())
		return region == ["com"]
			|| region.count == 1 && region[0].count == 2
			|| region.count == 2 && ["com", "co"].contains(region[0]) && region[1].count == 2
	}

	private static func destination(for input: String) -> URL? {
		let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return nil }

		if let components = URLComponents(string: text),
		   let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme)
		{
			guard !text.contains(where: \.isWhitespace),
			      let host = components.host, !host.isEmpty,
			      !host.contains(where: \.isWhitespace)
			else { return searchURL(for: text) }
			return components.url ?? searchURL(for: text)
		}

		if !text.contains(where: \.isWhitespace),
		   let components = URLComponents(string: "https://" + text),
		   let host = components.host,
		   host.contains(".") || host.lowercased() == "localhost",
		   !host.contains(where: \.isWhitespace),
		   let url = components.url
		{
			return url
		}

		return searchURL(for: text)
	}

	private static func searchURL(for query: String) -> URL? {
		var components = URLComponents(string: "https://www.google.com/search")
		components?.queryItems = [URLQueryItem(name: "q", value: query)]
		return components?.url
	}
}

#Preview {
	DesktopBrowserShell(browser: Browser())
}
