import Defaults
import SwiftUI
import WebKit

struct ShellTopBarView: View {
	let browser: Browser
	let theme: BrowserTheme
	let sidebarShown: Bool
	let topBarColorScheme: ColorScheme
	var isCompact = false
	var reservesWindowControls = false
	var roundsLeadingButton = false
	var acceptsFocusRequests = true
	@Default(.developerModeEnabled) private var developerModeEnabled

	private var showsDeveloperMode: Bool {
		developerModeEnabled || browser.selectedTab?.isDeveloperMode == true
	}

	var body: some View {
		if browser.selectedTab?.internalPage == nil, !browser.isShowingNewTab {
			websiteControls
				.transition(.identity)
				.frame(height: isCompact ? BrowserChromeMetrics.topBarRegionHeight * 2 : BrowserChromeMetrics.topBarRegionHeight)
				.background {
					ZStack {
						browser.selectedTab?.activeController?.themeColor ?? theme.tabColor
						if showsDeveloperMode {
							Canvas { context, size in
								for x in stride(from: -size.height, through: size.width, by: 24) {
									var stripe = Path()
									stripe.move(to: CGPoint(x: x, y: 0))
									stripe.addLine(to: CGPoint(x: x + size.height, y: size.height))
									context.stroke(stripe, with: .color(.yellow.opacity(0.14)), lineWidth: 12)
								}
							}
							.allowsHitTesting(false)
							.accessibilityHidden(true)
						}
					}
				}
				.clipShape(RoundedRectangle(cornerRadius: sidebarShown ? BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar : BrowserChromeMetrics.tabWindowCornerRadiusWithoutSidebar))
				.padding([.top, .horizontal], sidebarShown ? BrowserChromeMetrics.shellEdgePadding : 0)
		}
	}

	private var controlsColorScheme: ColorScheme {
		if let isLight = browser.selectedTab?.activeController?.themeColorIsLight {
			return isLight ? .light : .dark
		}
		return theme.foregroundColor == .black ? .light : .dark
	}

	private var websiteControls: some View {
		Group {
			if isCompact {
				VStack(spacing: 0) {
					BrowserAddressField(browser: browser, acceptsFocusRequests: acceptsFocusRequests)
						.frame(height: BrowserChromeMetrics.topBarRegionHeight)
					HStack(spacing: 8) {
						ShellWebsiteNavigationControls(
							browser: browser,
							theme: theme,
							roundsLeadingButton: roundsLeadingButton
						)
						.offset(y: -0.5)
						ShellExtensionControls(browser: browser, theme: theme)
							.offset(y: -0.5)
					}
					.padding(.trailing, BrowserChromeMetrics.topBarTrailingInset)
					.frame(height: BrowserChromeMetrics.topBarRegionHeight)
				}
			} else {
				desktopWebsiteControls
			}
		}
		.padding(
			.leading,
			reservesWindowControls ? BrowserChromeMetrics.windowControlsAreaWidth + BrowserChromeMetrics.topBarLeadingInset : (sidebarShown ? BrowserChromeMetrics.topBarLeadingInset : BrowserChromeMetrics.persistentControlsAreaWidth + BrowserChromeMetrics.topBarLeadingInset)
		)
		.frame(height: isCompact ? BrowserChromeMetrics.topBarRegionHeight * 2 : BrowserChromeMetrics.topBarRegionHeight)
		.frame(maxWidth: .infinity, alignment: .leading)
		#if os(macOS)
			.background {
				NonDraggableTitlebarRegion()
			}
		#endif
			.environment(\.colorScheme, controlsColorScheme)
			.foregroundStyle(.primary)
			.overlay(alignment: .bottom) {
				if let controller = browser.selectedTab?.activeController {
					ShellTopBarLoadingBar(
						controller: controller,
						theme: theme,
						tabID: browser.selectedTabID
					)
				}
			}
	}

	private var desktopWebsiteControls: some View {
		HStack(spacing: 8) {
			ShellWebsiteNavigationControls(
				browser: browser,
				theme: theme,
				roundsLeadingButton: roundsLeadingButton
			)
			.offset(y: -0.5)
			.fixedSize(horizontal: true, vertical: false)
			BrowserAddressField(browser: browser, acceptsFocusRequests: acceptsFocusRequests)
				// Only the remaining width is available to the address field.
				.frame(minWidth: 72, maxWidth: .infinity)
				.layoutPriority(-1)
				.transaction { $0.animation = nil }
			ShellExtensionControls(browser: browser, theme: theme)
				.offset(y: -0.5)
				.fixedSize(horizontal: true, vertical: false)
		}
		.padding(.trailing, BrowserChromeMetrics.topBarTrailingInset)
	}
}

private struct ShellWebsiteNavigationControls: View {
	let browser: Browser
	let theme: BrowserTheme
	let roundsLeadingButton: Bool
	@Default(.developerModeEnabled) private var developerModeEnabled
	@Default(.usageLimitsProvider) private var usageLimitsProvider

	var body: some View {
		if let controller = browser.selectedTab?.activeController {
			BrowserNavigationControls(
				controller: controller,
				browser: browser,
				roundsLeadingEdge: roundsLeadingButton
			)
			.controlSize(.regular)
			.labelStyle(.iconOnly)
			.buttonSizing(.fitted)
			.buttonStyle(.bordered)
			.foregroundStyle(.primary)
			.id(ObjectIdentifier(controller))
			BrowserAgentControls(browser: browser)
			#if os(macOS)
				if developerModeEnabled || browser.selectedTab?.isDeveloperMode == true {
					Button("Inspect Element", systemImage: "cursorarrow.rays") {
						BrowserDesktopCommands.showWebInspector(controller, selectingElement: true)
					}
					.astraTopBarButton()
					.disabled(!controller.hasCurrentPageDocument)
					.help("Select an element to inspect in Web Inspector")
					.accessibilityLabel("Inspect Element")
					.accessibilityIdentifier("developer-inspect-element")
				}
				BrowserScreenshotButton(browser: browser, controller: controller)
					.id(ObjectIdentifier(controller))
				BrowserSiteInformationButton(controller: controller)
					.id(ObjectIdentifier(controller))
			#endif
			if developerModeEnabled || browser.selectedTab?.isDeveloperMode == true, usageLimitsProvider != .none, !browser.isPrivate {
				BrowserUsageLimitsButton(browser: browser)
			}
			#if os(iOS)
				BrowserWebsiteMonitorButton(browser: browser)
				BrowserTranslationButton(browser: browser, controller: controller)
			#endif
		}
	}
}

private struct BrowserUsageLimitsButton: View {
	let browser: Browser
	@Default(.usageLimitsProvider) private var provider
	@State private var showsPopover = false
	@State private var consumerID = UUID()

	private var store: BrowserUsageLimitsStore {
		browser.session.usageLimits
	}

	var body: some View {
		Button {
			showsPopover.toggle()
		} label: {
			AstraTopBarIcon(title: "Usage Limits", systemImage: "gauge.with.dots.needle.67percent")
		}
		.astraTopBarButton()
		.help("Show provider usage limits")
		.accessibilityLabel("Show \(provider.title) usage limits")
		.accessibilityIdentifier("usage-limits-button")
		.popover(isPresented: $showsPopover) {
			BrowserUsageLimitsPopover(store: store, provider: provider)
		}
		.task(id: provider) {
			store.start(provider: provider, consumerID: consumerID)
		}
		.onDisappear {
			store.stop(consumerID: consumerID)
		}
	}
}

private struct BrowserUsageLimitsPopover: View {
	let store: BrowserUsageLimitsStore
	let provider: BrowserUsageLimitsProvider

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("\(provider.title) limits")
				.font(.headline)
			if store.isRefreshing, store.windows.isEmpty {
				ProgressView("Loading limits…")
			} else if let error = store.error {
				Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
					.foregroundStyle(.secondary)
			} else if store.windows.isEmpty {
				Text("No usage limits are available.")
					.foregroundStyle(.secondary)
			} else {
				ForEach(store.windows, id: \.title) { window in
					VStack(alignment: .leading, spacing: 4) {
						HStack {
							Text(window.title)
							Spacer()
							Text("\(window.remainingPercent, specifier: "%.0f")% left")
						}
						ProgressView(value: window.remainingPercent, total: 100)
						if let resetAt = window.resetAt {
							Text("Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
				}
			}
			if let updatedAt = store.updatedAt {
				Text("Updated \(updatedAt, style: .relative) ago")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Text("Updates every 2 minutes")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.padding()
		.frame(minWidth: 260)
	}
}

struct ShellExtensionControls: View {
	let browser: Browser
	let theme: BrowserTheme
	@State private var extensions = BrowserExtensionManager.shared

	var body: some View {
		if !browser.isPrivate {
			if let listing = browser.selectedTab?.activeController?.url,
			   ChromeExtensionPackage.extensionID(from: listing) != nil
			{
				Button("Install Extension", systemImage: "square.and.arrow.down") {
					Task { await extensions.installFromChromeStore(listing) }
				}
				.disabled(extensions.isInstallingFromStore)
				.astraTopBarButton()
				.accessibilityIdentifier("install-chrome-store-extension")
			}
			let _ = extensions.actionsRevision
			ForEach(extensions.loadedNames().filter { extensions.isPinned($0) }, id: \.self) { name in
				let action = extensions.action(for: name, in: browser)
				Button {
					extensions.performAction(name, in: browser)
				} label: {
					#if os(macOS)
						if let icon = action?.icon(for: CGSize(width: 18, height: 18)) {
							Image(nsImage: icon)
								.resizable()
								.scaledToFit()
								.frame(width: 16, height: 16)
								.frame(width: BrowserChromeMetrics.topBarButtonLabelWidth, height: BrowserChromeMetrics.topBarButtonLabelHeight)
						} else {
							AstraTopBarIcon(title: action?.label ?? extensions.title(for: name), systemImage: "puzzlepiece.extension.fill")
						}
					#else
						if let icon = action?.icon(for: CGSize(width: 18, height: 18)) {
							Image(uiImage: icon)
								.resizable()
								.scaledToFit()
								.frame(width: 16, height: 16)
								.frame(width: BrowserChromeMetrics.topBarButtonLabelWidth, height: BrowserChromeMetrics.topBarButtonLabelHeight)
						} else {
							AstraTopBarIcon(title: action?.label ?? extensions.title(for: name), systemImage: "puzzlepiece.extension.fill")
						}
					#endif
				}
				.disabled(action?.isEnabled == false)
				.astraTopBarButton()
				.accessibilityLabel(action?.label ?? extensions.title(for: name))
				.accessibilityIdentifier("extension-action-\(name)")
			}

			Menu {
				ForEach(extensions.availableNames, id: \.self) { name in
					extensionMenuItem(extensions.title(for: name), name: name)
				}
				Divider()
				Button("Manage Extensions", systemImage: "gearshape") {
					browser.settingsPage = .extensions
					browser.openInternalPage(.settings)
				}
			} label: {
				AstraTopBarIcon(title: "Extensions", systemImage: "puzzlepiece.extension")
			}
			.menuIndicator(.hidden)
			.astraTopBarButton()
			.astraTopBarOuterCorners(.trailing)
			.accessibilityLabel("Extensions")
			.accessibilityIdentifier("browser-extensions")
		}
	}

	@ViewBuilder
	private func extensionMenuItem(_ title: String, name: String) -> some View {
		if extensions.isLoaded(name) {
			Button("Open \(title)", systemImage: "puzzlepiece.extension") {
				extensions.performAction(name, in: browser)
			}
		}
		Button(title, systemImage: extensions.isLoaded(name) ? "checkmark.circle.fill" : "circle") {
			extensions.setEnabled(!extensions.isEnabled(name), for: name)
		}
		if let error = extensions.loadErrors[name] {
			Button("\(title): \(error)", systemImage: "exclamationmark.triangle") {}
				.disabled(true)
		}
	}
}

private struct ShellTopBarLoadingBar: View {
	let controller: BrowserController
	let theme: BrowserTheme
	let tabID: UUID

	var body: some View {
		BrowserLoadingBar(
			isLoading: controller.isLoading,
			estimatedProgress: controller.estimatedProgress,
			theme: theme
		)
		.frame(height: 1.5)
		.id(tabID)
	}
}
