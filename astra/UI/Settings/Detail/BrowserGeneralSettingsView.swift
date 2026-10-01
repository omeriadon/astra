import Defaults
import Sparkle
import SwiftUI

#if os(macOS)
	import AppKit
#endif

let addressDisplayStyleSpacing: CGFloat = 8

struct BrowserGeneralSettingsView: View {
	@Bindable private var updates = UpdateManager.shared
	@Default(.addressDisplayStyle) private var addressDisplayStyle
	@Default(.peekLevel) private var peekLevel
	@Default(.zoomOutInPeeks) private var zoomOutInPeeks
	@Default(.renameDownloadsWithAppleIntelligence) private var renameDownloadsWithAppleIntelligence
	@Default(.startupBehavior) private var startupBehavior
	@Default(.homepageURL) private var homepageURL
	@Default(.browserSearchConfiguration) private var browserSearchConfigurationValue

	#if os(macOS)
		@State private var isDefaultBrowser = false
		@State private var isSettingDefaultBrowser = false
		@State private var defaultBrowserError: String?
		@Default(.miniAstraEnabled) private var miniAstraEnabled
		@Default(.miniAstraWindowAnimation) private var miniAstraWindowAnimation
		@Default(.miniAstraShortcutEnabled) private var miniAstraShortcutEnabled
	#endif

	var body: some View {
		List {
			#if os(macOS)
				Section("Default Browser") {
					Text(isDefaultBrowser ? "Astra is your default browser." : "Open web links from other apps in Astra.")
						.foregroundStyle(.secondary)
						.accessibilityIdentifier("default-browser-status")

					Button("Make Default Browser", systemImage: "globe", role: .confirm) {
						Task { await makeDefaultBrowser() }
					}
					.buttonStyle(.glassProminent)
					.disabled(isDefaultBrowser || isSettingDefaultBrowser)
					.accessibilityLabel("Make Astra the default web browser")
					.accessibilityIdentifier("make-default-browser")
					.id("Make Default Browser")

					if let defaultBrowserError {
						Text(defaultBrowserError)
							.foregroundStyle(.red)
							.accessibilityIdentifier("default-browser-error")
					}
				}
				.id("Default Browser")
				.onAppear(perform: refreshDefaultBrowser)
				.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
					refreshDefaultBrowser()
				}
			#endif

			Section("Address Bar") {
				VStack(spacing: addressDisplayStyleSpacing) {
					ForEach(AddressDisplayStyle.allCases) { style in
						addressDisplayStyleOption(style: style)
							.id(style.title)
					}
				}
				.padding(5)
				.background {
					Color.primary.opacity(0.1)
						.clipShape(RoundedRectangle(cornerRadius: 20))
				}
				.accessibilityIdentifier("address-display-style-picker")
				.id("Address Bar")
			}

			Section("Search") {
				Picker("Normal browsing", selection: engineBinding(isPrivate: false)) {
					ForEach(BrowserSearchConfiguration.Engine.allCases) { engine in
						Text(engine.title).tag(engine)
					}
				}
				.accessibilityIdentifier("normal-search-engine-picker")

				Picker("Private browsing", selection: engineBinding(isPrivate: true)) {
					ForEach(BrowserSearchConfiguration.Engine.allCases) { engine in
						Text(engine.title).tag(engine)
					}
				}
				.accessibilityIdentifier("private-search-engine-picker")

				if searchConfiguration.normalEngine == .custom || searchConfiguration.privateEngine == .custom {
					TextField("HTTPS search template", text: customTemplateBinding)
						.accessibilityLabel("Custom HTTPS search template")
						.accessibilityIdentifier("custom-search-template")
					if searchConfiguration.customTemplateIsValid {
						Text("Use {query} as the search term. Only HTTPS templates are used.")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else {
						Text("Enter a valid HTTPS URL with one {query} placeholder in its query.")
							.font(.caption)
							.foregroundStyle(.red)
							.accessibilityIdentifier("custom-search-template-error")
					}
				}

				TextField("Keyword shortcuts", text: keywordShortcutsBinding, axis: .vertical)
					.lineLimit(1 ... 4)
					.accessibilityLabel("Search keyword shortcuts")
					.accessibilityIdentifier("search-keyword-shortcuts")
				Text("One per line: keyword=https://example.com/search?q={query}")
					.font(.caption)
					.foregroundStyle(.secondary)

				Toggle("Allow search suggestions in Private Browsing", isOn: privateSuggestionsBinding)
					.accessibilityIdentifier("private-search-suggestions-enabled")
			}
			.id("Search")

			Section("Startup") {
				Picker("When Astra opens", selection: $startupBehavior) {
					Text("Restore previous session").tag(BrowserStartupBehavior.restore)
					Text("Open a blank tab").tag(BrowserStartupBehavior.blank)
					Text("Open homepage").tag(BrowserStartupBehavior.homepage)
				}
				.accessibilityIdentifier("startup-behavior-picker")

				if startupBehavior == .homepage {
					TextField("Homepage URL", text: $homepageURL)
						.accessibilityLabel("Homepage URL")
						.accessibilityIdentifier("homepage-url")
				}
			}
			.id("Startup")

			#if os(macOS)
				Section("Mini Astra") {
					Toggle("Open links from other apps in Mini Astra", isOn: $miniAstraEnabled)
						.accessibilityIdentifier("mini-astra-enabled")

					Toggle("Animate Mini Astra from the pointer", isOn: $miniAstraWindowAnimation)
						.accessibilityIdentifier("mini-astra-window-animation")

					if miniAstraWindowAnimation {
						Text("Expands the window from the pointer position. Respects Reduce Motion.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}

					Toggle("Enable global shortcut: ⌃⌥⌘N", isOn: $miniAstraShortcutEnabled)
						.accessibilityLabel("Enable global Mini Astra shortcut: Control Option Command N")
						.accessibilityIdentifier("mini-astra-shortcut-enabled")
						.onChange(of: miniAstraShortcutEnabled) { _, _ in
							MiniAstraShortcut.shared.update()
						}
					Text("Opens a blank Mini Astra window from any app while Astra is running.")
						.font(.caption)
						.foregroundStyle(.secondary)
					if MiniAstraShortcut.shared.registrationFailed {
						Text("The shortcut could not be registered. Disable any conflicting shortcut, then enable it again.")
							.foregroundStyle(.red)
					}
				}
			#endif

			Section("Peek") {
				Picker("Levels", selection: $peekLevel) {
					ForEach(PeekLevel.allCases) { level in
						Text(level.title)
							.tag(level)
					}
				}
				.accessibilityIdentifier("peek-level-picker")
				.id("Levels")

				if peekLevel != .none {
					Toggle("Zoom out in Peeks", isOn: $zoomOutInPeeks)
						.accessibilityIdentifier("zoom-out-in-peeks-toggle")
						.id("Zoom out in Peeks")
				}
			}
			.id("Peek")

			Section("Downloads") {
				Toggle("Rename downloads with Apple Intelligence", isOn: $renameDownloadsWithAppleIntelligence)
					.accessibilityLabel("Rename downloads with Apple Intelligence")
					.accessibilityIdentifier("rename-downloads-with-apple-intelligence")
					.id("Rename downloads with Apple Intelligence")

				ZStack {}
			}
			.id("Downloads")

			Section("Updates") {
				Toggle("Automatically check for updates", isOn: $updates.automaticChecks)
					.accessibilityIdentifier("automatically-check-for-updates")
					.id("Automatically check for updates")

				Toggle("Automatically install updates", isOn: $updates.automaticInstalls)
					.disabled(!updates.automaticChecks || !updates.updater.allowsAutomaticUpdates)
					.accessibilityIdentifier("automatically-install-updates")
					.id("Automatically install updates")
			}
			.id("Updates")
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
	}

	private func bounded(_ value: String, maxBytes: Int) -> String {
		var result = ""
		for character in value {
			let next = String(character)
			guard result.utf8.count + next.utf8.count <= maxBytes else { break }
			result.append(character)
		}
		return result
	}

	private var searchConfiguration: BrowserSearchConfiguration {
		BrowserSearchConfiguration.decode(browserSearchConfigurationValue)
	}

	private func engineBinding(isPrivate: Bool) -> Binding<BrowserSearchConfiguration.Engine> {
		Binding(
			get: { searchConfiguration.engine(isPrivate: isPrivate) },
			set: { engine in
				var configuration = searchConfiguration
				if isPrivate {
					configuration.privateEngine = engine
				} else {
					configuration.normalEngine = engine
				}
				browserSearchConfigurationValue = configuration.encoded
			}
		)
	}

	private var customTemplateBinding: Binding<String> {
		Binding(
			get: { searchConfiguration.customTemplate },
			set: { value in
				var configuration = searchConfiguration
				configuration.customTemplate = bounded(value, maxBytes: 2_048)
				browserSearchConfigurationValue = configuration.encoded
			}
		)
	}

	private var keywordShortcutsBinding: Binding<String> {
		Binding(
			get: { searchConfiguration.keywordShortcuts },
			set: { value in
				var configuration = searchConfiguration
				configuration.keywordShortcuts = bounded(value, maxBytes: 4_096)
				browserSearchConfigurationValue = configuration.encoded
			}
		)
	}

	private var privateSuggestionsBinding: Binding<Bool> {
		Binding(
			get: { searchConfiguration.privateSuggestionsEnabled },
			set: { value in
				var configuration = searchConfiguration
				configuration.privateSuggestionsEnabled = value
				browserSearchConfigurationValue = configuration.encoded
			}
		)
	}

	#if os(macOS)
		private func refreshDefaultBrowser() {
			isDefaultBrowser = ["http", "https"].allSatisfy { scheme in
				guard let url = URL(string: "\(scheme)://example.com"),
				      let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url),
				      let bundleIdentifier = Bundle.main.bundleIdentifier
				else { return false }
				return Bundle(url: applicationURL)?.bundleIdentifier == bundleIdentifier
			}
		}

		private func makeDefaultBrowser() async {
			isSettingDefaultBrowser = true
			defaultBrowserError = nil
			defer {
				isSettingDefaultBrowser = false
				refreshDefaultBrowser()
			}
			do {
				for scheme in ["http", "https"] {
					try await NSWorkspace.shared.setDefaultApplication(
						at: Bundle.main.bundleURL,
						toOpenURLsWithScheme: scheme
					)
				}
			} catch {
				defaultBrowserError = error.localizedDescription
			}
		}
	#endif

	private func addressDisplayStyleOption(style: AddressDisplayStyle) -> some View {
		HStack {
			Text(style.title)
				.padding(.leading, 10)
				.frame(width: 70, alignment: .leading)

			VStack(spacing: 4) {
				ZStack {
					switch style {
						case .full:
							Text(verbatim: "https://apple.com")

						case .simple:
							Text("apple.com")

						case .dimmed:
							Text(
								"\(Text(verbatim: "https://").foregroundStyle(.tertiary))\(Text(verbatim: "apple.com"))"
							)
					}
				}
				.lineLimit(1)
				.padding(.vertical, 4)
				.padding(.horizontal, 6)
				.fixedSize(horizontal: true, vertical: false)
				.frame(maxWidth: .infinity, alignment: .leading)
				.clipped()
				.background {
					RoundedRectangle(cornerRadius: 9)
						.fill(Color.white.opacity(0.2))
						.strokeBorder(.white.opacity(0.3), lineWidth: 1)
				}

				ZStack {
					switch style {
						case .full:
							HStack(spacing: 4) {
								Image(systemName: "magnifyingglass")

								Text(verbatim: "https://www.google.com/search?q=apple&newwindow=1&sca_esv=bf93e7ad4ce70d45&sxsrf=APpeQnuqYbYJLPhMn5oNNgwYj17zOxJ_BQ%3A1790315221453&ei=1Qq2auqlG9LT1sQP-vi3uAM&biw=1515&bih=943&ved=2ahUKEwiq5L32g4mXAxXSqZUCHXr8DTcQ4dUDegQIBhAN&uact=5&oq=apple&gs_lp=Egxnd3Mtd2l6LXNlcnAiBWFwcGxlMgQQIxgnMgQQIxgnMgQQIxgnMhkQLhiABBiKBRhDGLEDGIMBGMkDGMcBGNEDMhAQABiABBiKBRhDGLEDGIMBMhAQABiABBiKBRhDGLEDGIMBMhAQABiABBiKBRhDGLEDGIMBMhAQABiABBiKBRhDGLEDGIMBMgoQABiABBiKBRhDMhQQLhiABBixAxiDARiSAxjHARivAUjvClAAWKkJcAB4AZABAJgBgwigAb0VqgELMi0xLjUtMS4xLjG4AQPIAQD4AQGYAgSgAskVmAMAkgcJMy0xLjAuMi4xoAf8LbIHCTMtMS4wLjIuMbgHyRXCBwUwLjMuMcgHB4AIAQ&sclient=gws-wiz-serp")
							}

						case .simple:
							HStack(spacing: 4) {
								Image(systemName: "magnifyingglass")

								Text("apple")
							}

						case .dimmed:
							HStack(spacing: 4) {
								Image(systemName: "magnifyingglass")

								Text(
									"\(Text(verbatim: "https://www.google.com/search?q=").foregroundStyle(.tertiary))\(Text(verbatim: "apple"))\(Text(verbatim: "&sca_esv=bf93e7ad4ce70d45&sxsrf=APpeQnvBa9UzORU_4vLzBenh_U84tBEIrQ%3A1790315249202&ei=8Qq2aqn6C_zd1sQP-oS74Q8&biw=1069&bih=769&ved=2ahUKEwjpttuDhImXAxX8rpUCHXrCLvwQ4dUDegQIBhAN&uact=5&oq=apple&gs_lp=Egxnd3Mtd2l6LXNlcnAiBWFwcGxlMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMg0QABiABBiKBRhDGLADMg0QABiABBiKBRhDGLADMg0QABiABBiKBRhDGLADSLgBUABYAHABeAGQAQCYAQCgAQCqAQC4AQPIAQCYAgGgAgeYAwCIBgGQBgySBwExoAcAsgcAuAcAwgcDMi0xyAcFgAgB&sclient=gws-wiz-serp").foregroundStyle(.tertiary))"
								)
							}
					}
				}
				.lineLimit(1)
				.padding(.vertical, 4)
				.padding(.horizontal, 6)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background {
					RoundedRectangle(cornerRadius: 9)
						.fill(Color.white.opacity(0.2))
						.strokeBorder(.white.opacity(0.3), lineWidth: 1)
				}
			}
		}
		.padding(6)
		.frame(maxWidth: .infinity, alignment: .top)
		.contentShape(RoundedRectangle(cornerRadius: 15))
		.overlay {
			RoundedRectangle(cornerRadius: 15)
				.fill(Color.primary.opacity(addressDisplayStyle == style ? 0.2 : 0.0))
				.strokeBorder(.white.opacity(addressDisplayStyle == style ? 0.6 : 0.3), lineWidth: 1)
		}
		.animation(.smooth(duration: 0.15), value: addressDisplayStyle == style)
		.onTapGesture {
			addressDisplayStyle = style
		}
	}
}
