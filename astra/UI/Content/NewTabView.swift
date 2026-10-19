import Defaults
import Livable
import SwiftUI
#if os(macOS)
	import AppKit
	import UniformTypeIdentifiers
#endif

struct NewTabView: View {
	@Bindable var browser: Browser
	@Default(.searchSuggestionsEnabled) private var searchSuggestionsEnabled
	@Default(.browserSearchConfiguration) private var searchConfigurationValue
	@Default(.startPagePreferences) private var startPagePreferencesValue
	@FocusState private var isSearchFocused: Bool
	@Namespace private var transitions
	@AppStorage("astra.newTabBackgroundStyle") private var backgroundStyle = "default"
	@AppStorage("astra.newTabDitherConfiguration") private var ditherConfigurationData = Data()
	@State private var editingDither = false
	@State private var editingEffect = false
	@AppStorage("astra.newTabEffectSettings") private var effectSettingsData = Data()
	@AppStorage("astra.newTabTopographicImage") private var topographicImageID = ""
	@State private var ditherPointer = DitherPointerInput()
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.scenePhase) private var scenePhase
	@State private var isPresented = false
	@State private var entered = false
	#if os(macOS)
		@State private var windowCanAnimate = false
	#endif
	@State private var recentVisits: [BrowserVisit] = []
	@State private var frequentVisits: [BrowserVisitSummary] = []

	private var searchConfiguration: BrowserSearchConfiguration {
		BrowserSearchConfiguration.decode(searchConfigurationValue)
	}

	private var startPagePreferences: BrowserStartPagePreferences {
		BrowserStartPagePreferences.decode(startPagePreferencesValue) ?? .default
	}

	private var hasStartPageContent: Bool {
		let preferences = startPagePreferences
		return preferences.isVisible(.favourites) && !browser.favouriteTabs.isEmpty
			|| !browser.isPrivate && preferences.isVisible(.recent) && !recentVisits.isEmpty
			|| !browser.isPrivate && preferences.isVisible(.frequent) && !frequentVisits.isEmpty
			|| preferences.isVisible(.recentlyClosed) && !browser.closedHistoryTabs.isEmpty
	}

	private var emptyStartPageDescription: String {
		if BrowserStartPagePreferences.Module.allCases.allSatisfy({ !startPagePreferences.isVisible($0) }) {
			return "Enable a module in Customize Start Page to show it here."
		}
		if browser.isPrivate {
			return "Tabs closed in this private window will appear here."
		}
		return "Favorites and visited pages will appear here."
	}

	private var historySearchRequest: BrowserHistorySearchModel.Request {
		.init(query: browser.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines), revision: browser.historyChangeRevision)
	}

	var body: some View {
		let selectedResultID = browser.selectedNewTabSearchResult?.id
		ZStack(alignment: .bottomTrailing) {
			newTabBackground
			GeometryReader { geometry in
				VStack(spacing: 0) {
					searchHeader
						.opacity(entered || reduceMotion ? 1 : 0)
						.scaleEffect(entered || reduceMotion ? 1 : 0.94)
						.offset(y: entered || reduceMotion ? 0 : 12)
					if !browser.newTabSearchText.isEmpty {
						ScrollViewReader { proxy in
							List {
								BrowserSearchSuggestionsSection(
									browser: browser,
									results: browser.newTabSearchResults,
									query: browser.newTabSearchText,
									generation: browser.newTabSearchGeneration,
									selectedResultID: selectedResultID,
									fromNewTab: true,
									onSelect: browser.performNewTabSearchResult
								)
							}
							.listStyle(.sidebar)
							.scrollContentBackground(.hidden)
							.onChange(of: selectedResultID) { _, selection in
								if let selection {
									proxy.scrollTo(selection)
								}
							}
						}
					}
				}
				.frame(maxWidth: 680)
				.padding(.horizontal, 24)
				.padding(.top, max(24, geometry.size.height * 0.20))
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
			}
		}
		.overlay {
			#if os(macOS)
				if backgroundStyle == "dither" {
					NewTabPointerTracker(pointer: ditherPointer)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.allowsHitTesting(false)
				}
			#endif
		}
		.overlay(alignment: .bottomTrailing) {
			backgroundPicker.padding(20)
		}
		#if !os(macOS)
		.onContinuousHover { phase in
			guard backgroundStyle == "dither" else { return }
			switch phase {
				case let .active(location): ditherPointer.location = location
				case .ended: ditherPointer.location = nil
			}
		}
		#endif
		#if os(macOS)
		.background {
			NewTabWindowActivity { windowCanAnimate = $0 }
		}
		#endif
		.onAppear { isPresented = true }
		.onDisappear { isPresented = false }
		.task(id: browser.selectedTabID) {
			entered = false
			await Task.yield()
			guard !Task.isCancelled else { return }
			withAnimation(reduceMotion || !usesDefaultBackground ? nil : .smooth(duration: 0.55)) { entered = true }
		}
		.task(id: browser.quickSearchFocusRequest) {
			await Task.yield()
			isSearchFocused = true
		}
		.task(id: browser.selectedTabID) {
			isSearchFocused = true
		}
		.onChange(of: browser.addressFocusRequest) { _, _ in
			isSearchFocused = true
		}
		.onChange(of: browser.historyVisits, initial: true) { _, visits in
			recentVisits = BrowserStartPageProjection.recent(visits, isPrivate: browser.isPrivate)
			frequentVisits = BrowserStartPageProjection.frequent(visits, isPrivate: browser.isPrivate)
		}
		.task(id: historySearchRequest) {
			guard !historySearchRequest.query.isEmpty else { return }
			await browser.historySearch.update(historySearchRequest, scope: .newTab, visits: browser.historyVisits)
		}
		.task(id: suggestionRequest) {
			let request = suggestionRequest
			browser.newTabGoogleSuggestions = []
			guard request.suggestionsEnabled,
			      let provider = searchConfiguration.suggestionsProvider(isPrivate: request.isPrivate),
			      !request.query.isEmpty
			else {
				return
			}
			do {
				try await Task.sleep(for: .milliseconds(250))
				guard !Task.isCancelled,
				      searchSuggestionsEnabled,
				      suggestionRequest == request
				else {
					return
				}
				let suggestions = try await BrowserSearchSuggestions.fetch(
					for: request.query,
					provider: provider
				)
				try Task.checkCancellation()
				guard !Task.isCancelled,
				      searchSuggestionsEnabled,
				      suggestionRequest == request
				else {
					return
				}
				browser.newTabGoogleSuggestions = suggestions
			} catch {
				// Local suggestions and submitting the query remain available offline.
			}
		}
	}

	private var usesDefaultBackground: Bool {
		switch backgroundStyle {
			case "float", "dither", "smoke", "ripple", "datamosh", "topographic": false
			case "default", "solid", "image", "holographic": true
			default: true
		}
	}

	private var animatesBackground: Bool {
		#if os(macOS)
			isPresented && windowCanAnimate && !reduceMotion
		#else
			isPresented && scenePhase == .active && !reduceMotion
		#endif
	}

	private var defaultBackgroundColor: Color {
		let dark = browser.theme.appearanceMode == .dark
			|| (browser.theme.appearanceMode == .auto && colorScheme == .dark)
		return dark
			? Color(.sRGB, red: 24.933 / 255, green: 24.933 / 255, blue: 24.933 / 255, opacity: 0.7)
			: Color(.sRGB, red: 241.9 / 255, green: 242.06 / 255, blue: 242.19 / 255, opacity: 0.7)
	}

	/// Preserve each mesh point but expose dark Space colours before shading.
	/// Feeding near-black values to a blurred full-screen fill hid all motion.
	private var livingPalette: [Float] {
		let points = Array(browser.theme.meshColorPoints.prefix(4))
		let fallback = ThemeColorPoint(color: browser.theme.firstColor, x: 0.5, y: 0.5)
		return (0 ..< 4).flatMap { index -> [Float] in
			let point = points.isEmpty ? fallback : points[index % points.count]
			let source = point.color
			let peak = max(source.red, max(source.green, source.blue))
			let gain = min(3.2, max(1.0, 0.82 / max(peak, 0.12)))
			let lift: (Double) -> Float = { component in
				Float(min(1, max(0, component * gain + 0.045)))
			}
			return [Float(point.x), Float(point.y), lift(source.red), lift(source.green), lift(source.blue)]
		}
	}

	private var newTabBackground: some View {
		ZStack {
			// Every preset has the same dynamic light/dark foundation as Default.
			// Legacy image styles resolve to Default. Topographic owns its source image.
			defaultBackgroundColor
			if backgroundStyle == "dither" {
				DitherBackground(theme: browser.theme, configuration: DitherConfiguration.decode(ditherConfigurationData),
				                 pointer: ditherPointer, canAnimate: animatesBackground)
			} else if let preset = NewTabShaderPreset(rawValue: backgroundStyle), preset != .holographic {
				NewTabShaderSurface(theme: browser.theme, preset: preset, canAnimate: animatesBackground,
				                    settings: effectSettings.wrappedValue, imageID: topographicImageID)
					.opacity(preset == .ripple ? effectSettings.wrappedValue.value("ripple", "opacity") : 1)
			} else if backgroundStyle == "float" {
				Rectangle().fill(browser.theme.firstColor.color)
					.livable(palette: livingPalette, isAnimated: animatesBackground, speed: Float(effectSettings.wrappedValue.value("float", "speed")))
					.blur(radius: effectSettings.wrappedValue.value("float", "blur"))
					.overlay(defaultBackgroundColor.opacity(0.08))
			}
		}
		.clipped()
	}

	private var effectSettings: Binding<NewTabEffectSettings> {
		Binding(get: { NewTabEffectSettings.decode(effectSettingsData) },
		        set: { effectSettingsData = $0.encoded })
	}

	private var ditherConfiguration: Binding<DitherConfiguration> {
		Binding(get: { DitherConfiguration.decode(ditherConfigurationData) },
		        set: { ditherConfigurationData = $0.encoded })
	}

	private var backgroundPicker: some View {
		Menu {
			Button { backgroundStyle = "default" } label: {
				Label(
					"Default",
					systemImage: backgroundStyle == "default" ? "checkmark" : "circle"
				)
			}
			Button { backgroundStyle = "float" } label: {
				Label("Float", systemImage: backgroundStyle == "float" ? "checkmark" : "water.waves")
			}
			Button("Use Theme Dither", systemImage: "square.grid.3x3.fill") { backgroundStyle = "dither" }
			Button("Configure Dither…", systemImage: "slider.horizontal.3") {
				backgroundStyle = "dither"
				editingDither = true
			}
			Divider()
			Button { backgroundStyle = "smoke" } label: {
				Label("Smoke Reveal", systemImage: backgroundStyle == "smoke" ? "checkmark" : "smoke")
			}
			Button { backgroundStyle = "holographic" } label: {
				Label("Holographic Prismatic (Search Bar)", systemImage: backgroundStyle == "holographic" ? "checkmark" : "sparkles")
			}
			Button { backgroundStyle = "ripple" } label: {
				Label("Live Ripple", systemImage: backgroundStyle == "ripple" ? "checkmark" : "drop")
			}
			Button { backgroundStyle = "datamosh" } label: {
				Label("Datamosh", systemImage: backgroundStyle == "datamosh" ? "checkmark" : "waveform.path")
			}

			Button { backgroundStyle = "topographic" } label: {
				Label("Topographic", systemImage: backgroundStyle == "topographic" ? "checkmark" : "map")
			}
			Divider()
			if !NewTabEffectSettings.parameters(backgroundStyle).isEmpty {
				Button("Configure Effect…", systemImage: "slider.horizontal.3") { editingEffect = true }
			}
		} label: {
			Image(systemName: "paintpalette").font(.system(size: 15))
				.padding(10)
				.background(.ultraThinMaterial, in: Circle())
		}
		.menuStyle(.borderlessButton)
		.accessibilityLabel("Customize new tab background")
		.popover(isPresented: $editingEffect) {
			NewTabEffectControls(effect: backgroundStyle, settings: effectSettings, imageID: $topographicImageID)
				.frame(width: 360, height: 560)
		}
		.popover(isPresented: $editingDither) {
			DitherControls(configuration: ditherConfiguration).frame(width: 360, height: 600)
		}
	}

	@ViewBuilder
	private var startPageModules: some View {
		let preferences = startPagePreferences
		ForEach(preferences.moduleOrder) { module in
			if preferences.isVisible(module) {
				switch module {
					case .favourites:
						if !browser.favouriteTabs.isEmpty {
							Section("Favorites") {
								LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 100))], spacing: 12) {
									ForEach(browser.favouriteTabs) { tab in
										BrowserFavouriteTile(tab: tab, browser: browser, isSelected: browser.selectedTabID == tab.id, navigationNamespace: transitions)
									}
								}
								.padding(.vertical, 8)
							}
						}
					case .frequent:
						if !browser.isPrivate, !frequentVisits.isEmpty {
							Section("Frequently Visited") {
								ForEach(frequentVisits, id: \.url) { visit in
									StartPageVisitRow(
										title: visit.title,
										url: visit.url,
										count: visit.visitCount,
										session: browser.session,
										open: { browser.openHistoryURL(visit.url, inBackground: false) },
										openInBackground: { browser.openHistoryURL(visit.url, inBackground: true) }
									)
								}
							}
						}
					case .recent:
						if !browser.isPrivate, !recentVisits.isEmpty {
							Section("Recently Visited") {
								ForEach(recentVisits) { visit in
									StartPageVisitRow(
										title: visit.title,
										url: visit.url,
										count: nil,
										session: browser.session,
										open: { browser.openHistoryURL(visit.url, inBackground: false) },
										openInBackground: { browser.openHistoryURL(visit.url, inBackground: true) }
									)
								}
							}
						}
					case .recentlyClosed:
						if !browser.closedHistoryTabs.isEmpty {
							Section("Recently Closed") {
								ForEach(browser.closedHistoryTabs) { tab in
									Button {
										browser.reopenClosedTab(tab.id, inBackground: false)
									} label: {
										Label {
											VStack(alignment: .leading, spacing: 2) {
												Text(verbatim: tab.customTitle ?? tab.pageTitle)
													.lineLimit(1)
												Text(verbatim: tab.url?.host ?? "Recently closed tab")
													.font(.caption)
													.foregroundStyle(.secondary)
													.lineLimit(1)
											}
											.frame(maxWidth: .infinity, alignment: .leading)
										} icon: {
											Image(systemName: "arrow.uturn.backward")
												.frame(width: 20)
										}
									}
									.buttonStyle(.plain)
									.accessibilityLabel("Reopen \(tab.customTitle ?? tab.pageTitle)")
									.accessibilityIdentifier("start-page-closed-\(tab.id.uuidString)")
									.contextMenu {
										Button("Reopen in Background", systemImage: "plus.square.on.square") {
											browser.reopenClosedTab(tab.id, inBackground: true)
										}
										.accessibilityIdentifier("start-page-closed-background-\(tab.id.uuidString)")
									}
								}
							}
						}
				}
			}
		}
	}

	private var suggestionRequest: BrowserSearchSuggestionsRequest {
		BrowserSearchSuggestionsRequest(
			query: browser.newTabSearchText.trimmingCharacters(in: .whitespacesAndNewlines),
			generation: browser.newTabSearchGeneration,
			scope: "new-tab:\(browser.windowID):\(browser.selectedTabID)",
			provider: searchConfiguration.suggestionsProvider(isPrivate: browser.isPrivate) ?? .custom,
			isPrivate: browser.isPrivate,
			configuration: searchConfiguration.encoded,
			suggestionsEnabled: searchSuggestionsEnabled
		)
	}

	private var searchHeader: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(spacing: 10) {
				Image(systemName: "magnifyingglass")
					.accessibilityHidden(true)
				TextField("Search or type a URL", text: $browser.newTabSearchText,
				          prompt: Text("Search or type a URL").foregroundColor(backgroundStyle == "holographic" ? .white : .secondary))
					.focused($isSearchFocused)
					.textFieldStyle(.plain)
				#if os(macOS)
					.fontDesign(.monospaced)
				#elseif os(iOS)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.keyboardType(.webSearch)
				#endif
					.submitLabel(.go)
					.onSubmit { browser.submitNewTabSearch() }
					.onKeyPress(.downArrow) {
						browser.moveNewTabSearchSelection(by: 1)
						return .handled
					}
					.onKeyPress(.upArrow) {
						browser.moveNewTabSearchSelection(by: -1)
						return .handled
					}
					.onKeyPress(.escape) {
						browser.dismissQuickSearch()
						return .handled
					}
					.accessibilityLabel("Search the web, history, or browser actions")
					.accessibilityIdentifier("new-tab-search")
			}
			.padding(.horizontal, 22)
			.padding(.vertical, 20)
			.background {
				if backgroundStyle == "holographic" {
					NewTabShaderSurface(theme: browser.theme, preset: .holographic, canAnimate: animatesBackground,
					                    settings: effectSettings.wrappedValue)
						.overlay {
							RoundedRectangle(cornerRadius: 24, style: .continuous)
								.strokeBorder(.white.opacity(0.24), lineWidth: 1)
						}
				} else if usesDefaultBackground {
					RoundedRectangle(cornerRadius: 24, style: .continuous)
						.fill(.ultraThinMaterial)
				} else {
					RoundedRectangle(cornerRadius: 24, style: .continuous)
						.fill(.ultraThinMaterial)
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
			.foregroundStyle(backgroundStyle == "holographic" ? Color.white : Color.primary)
		}
		.padding(.horizontal, 10)
		.padding(.top, 10)
		.padding(.bottom, 16)
	}
}

private struct StartPageVisitRow: View {
	let title: String
	let url: URL
	let count: Int?
	let session: BrowserWebSession
	let open: () -> Void
	let openInBackground: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Button(action: open) {
				Label {
					VStack(alignment: .leading, spacing: 2) {
						Text(verbatim: title)
							.lineLimit(1)
						Text(count.map { "\(url.host ?? url.absoluteString) · \($0) visits" } ?? (url.host ?? url.absoluteString))
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				} icon: {
					Group {
						if let favicon = session.favicons.image(for: url) {
							favicon.resizable().scaledToFit()
						} else {
							Image(systemName: "clock.arrow.circlepath")
						}
					}
					.frame(width: 18, height: 18)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open \(title)")
			.accessibilityIdentifier("start-page-visit-\(url.absoluteString)")
			Button(action: openInBackground) {
				Label("Open in Background", systemImage: "plus.square.on.square")
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.accessibilityLabel("Open \(title) in Background")
			.accessibilityIdentifier("start-page-open-background-\(url.absoluteString)")
		}
	}
}

#Preview {
	NewTabView(browser: Browser())
}

#if os(macOS)
	/// One observer per displayed page. Saved blank tabs own no renderer or observers.
	private struct NewTabWindowActivity: NSViewRepresentable {
		let onChange: (Bool) -> Void

		func makeNSView(context _: Context) -> ActivityView {
			ActivityView(onChange: onChange)
		}

		func updateNSView(_ view: ActivityView, context _: Context) {
			view.onChange = onChange
		}

		static func dismantleNSView(_ view: ActivityView, coordinator _: ()) {
			view.stopObserving()
		}

		final class ActivityView: NSView {
			var onChange: (Bool) -> Void
			private var tokens: [NSObjectProtocol] = []

			init(onChange: @escaping (Bool) -> Void) {
				self.onChange = onChange
				super.init(frame: .zero)
			}

			@available(*, unavailable)
			required init?(coder _: NSCoder) {
				fatalError("init(coder:) is unavailable")
			}

			override func hitTest(_: NSPoint) -> NSView? {
				nil
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				stopObserving()
				for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
				             NSWindow.didDeminiaturizeNotification, NSApplication.didBecomeActiveNotification,
				             NSApplication.didResignActiveNotification]
				{
					tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
						Task { @MainActor [weak self] in self?.publish() }
					})
				}
				Task { @MainActor [weak self] in self?.publish() }
			}

			func stopObserving() {
				for token in tokens {
					NotificationCenter.default.removeObserver(token)
				}
				tokens.removeAll()
			}

			private func publish() {
				let owningWindow = unsafe window
				let visible = owningWindow.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
				onChange(NSApp.isActive && visible)
			}
		}
	}
#endif

#if os(macOS)
	/// AppKit's local mouse monitor sees pointer motion above TextFields and List
	/// rows, which a SwiftUI hover handler on a non-hit-testable backdrop misses.
	/// It is mounted only while Theme Dither is selected and never consumes events.
	private struct NewTabPointerTracker: NSViewRepresentable {
		let pointer: DitherPointerInput

		func makeNSView(context _: Context) -> TrackingView {
			TrackingView(pointer: pointer)
		}

		func updateNSView(_ view: TrackingView, context _: Context) {
			view.pointer = pointer
		}

		static func dismantleNSView(_ view: TrackingView, coordinator _: ()) {
			view.stopObserving()
		}

		final class TrackingView: NSView {
			var pointer: DitherPointerInput
			private var monitor: Any?
			private weak var monitoredWindow: NSWindow?
			private var previousMouseMovedEvents: Bool?

			init(pointer: DitherPointerInput) {
				self.pointer = pointer
				super.init(frame: .zero)
			}

			@available(*, unavailable)
			required init?(coder _: NSCoder) {
				fatalError("init(coder:) is unavailable")
			}

			override var isFlipped: Bool {
				true
			}

			override func hitTest(_: NSPoint) -> NSView? {
				nil
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				stopObserving()
				guard let window = unsafe window else { return }
				monitoredWindow = window
				previousMouseMovedEvents = window.acceptsMouseMovedEvents
				window.acceptsMouseMovedEvents = true
				monitor = NSEvent.addLocalMonitorForEvents(
					matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
				) { [weak self] event in
					self?.track(event)
					return event
				}
			}

			func stopObserving() {
				if let monitor {
					NSEvent.removeMonitor(monitor)
					self.monitor = nil
				}
				if let monitoredWindow, let previousMouseMovedEvents {
					monitoredWindow.acceptsMouseMovedEvents = previousMouseMovedEvents
				}
				monitoredWindow = nil
				previousMouseMovedEvents = nil
				pointer.location = nil
			}

			private func track(_ event: NSEvent) {
				guard let window = unsafe window, event.window === window else {
					pointer.location = nil
					return
				}
				let point = convert(event.locationInWindow, from: nil)
				pointer.location = bounds.contains(point) ? CGPoint(x: point.x, y: point.y) : nil
			}
		}
	}
#endif
