#if os(macOS)
	import AppKit
	import SwiftUI

	struct MiniAstraView: View {
		let browser: Browser
		let resolveSpaceBrowser: () -> Browser?
		let onOpenInSpace: (UUID) -> Void
		let onRevealSpaceBrowser: () -> Void

		@Environment(\.accessibilityReduceMotion) private var reduceMotion
		@State private var showsTopBar = true
		@State private var isTopBarRevealed = false
		@State private var showsSpacePicker = false
		@State private var spaceBrowser: Browser?
		@State private var spaceToDelete: BrowserSpace?
		@State private var hostWindow: NSWindow?
		@State private var trafficLightAnimator = BrowserWindowTrafficLightAnimator()

		/// A permanent black-to-charcoal gradient, with no GPU noise.
		private static let miniTheme: BrowserTheme = {
			var theme = BrowserTheme()
			theme.usesGradient = true
			theme.firstColor = BrowserColor(red: 0.015, green: 0.015, blue: 0.018)
			theme.secondColor = BrowserColor(red: 0.19, green: 0.19, blue: 0.21)
			theme.meshColorPoints = [
				ThemeColorPoint(color: theme.firstColor, x: 0, y: 0),
				ThemeColorPoint(color: theme.secondColor, x: 1, y: 1),
			]
			theme.shaderNoiseEnabled = false
			theme.shaderNoiseAmount = 0
			theme.appearanceMode = .dark
			return theme
		}()

		private var isShowingChrome: Bool {
			showsTopBar || isTopBarRevealed
		}

		private var topBarHeight: CGFloat {
			guard browser.selectedTab?.internalPage == nil, !browser.isShowingNewTab, isShowingChrome else { return 0 }
			return BrowserChromeMetrics.topBarRegionHeight + BrowserChromeMetrics.shellEdgePadding
		}

		private var openInSpaceButton: some View {
			Button {
				guard let destination = resolveSpaceBrowser() else { return }
				spaceBrowser = destination
				showsSpacePicker = true
			} label: {
				Label("Open in Space", systemImage: "arrow.up.right.square")
					.lineLimit(1)
			}
			.buttonStyle(.glassProminent)
			.buttonBorderShape(.capsule)
			.controlSize(.small)
			.help("Move this page into a browser Space")
			.accessibilityIdentifier("mini-astra-open-in-space")
			.popover(isPresented: $showsSpacePicker, arrowEdge: .bottom) {
				if let spaceBrowser {
					BrowserSpacePickerPopover(
						browser: spaceBrowser,
						onDismiss: { showsSpacePicker = false },
						onRequestDeleteSpace: requestSpaceDeletion,
						onSelectSpace: { space in onOpenInSpace(space.id) },
						onRevealSpace: onRevealSpaceBrowser
					)
				}
			}
		}

		private var topBar: some View {
			ShellTopBarView(
				browser: browser,
				theme: Self.miniTheme,
				sidebarShown: true,
				topBarColorScheme: .dark,
				reservesWindowControls: true,
				acceptsFocusRequests: topBarHeight > 0,
				trailingAccessory: AnyView(openInSpaceButton),
				usesThemeSurface: true
			)
			.background {
				WindowDragBackground()
			}
			.accessibilityIdentifier("mini-astra-top-bar")
		}

		var body: some View {
			ZStack(alignment: .top) {
				topBar
					.frame(height: BrowserChromeMetrics.topBarRegionHeight + BrowserChromeMetrics.shellEdgePadding, alignment: .top)
					.frame(maxWidth: .infinity, alignment: .trailing)
					.opacity(topBarHeight > 0 ? 1 : 0)
					.allowsHitTesting(topBarHeight > 0)
					.accessibilityHidden(topBarHeight == 0)

				VStack(spacing: 0) {
					Spacer(minLength: 0)
						.frame(height: topBarHeight)
						.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showsTopBar)
					BrowserPageView(
						browser: browser,
						cornerRadius: topBarHeight > 0
							? BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar
							: BrowserChromeMetrics.tabWindowCornerRadiusWithoutSidebar
					)
					.padding(.top, topBarHeight > 0 ? BrowserChromeMetrics.shellEdgePadding : 0)
					.padding([.bottom, .horizontal], topBarHeight > 0 ? BrowserChromeMetrics.shellEdgePadding : 0)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
			.background {
				BrowserThemeBackground(theme: Self.miniTheme)
			}
			.onContinuousHover { phase in
				switch phase {
					case let .active(location):
						let revealHeight = isTopBarRevealed
							? BrowserChromeMetrics.topBarRegionHeight + BrowserChromeMetrics.shellEdgePadding
							: 6
						let shouldReveal = !showsTopBar && location.y < revealHeight
						guard shouldReveal != isTopBarRevealed else { return }
						withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
							isTopBarRevealed = shouldReveal
						}
					case .ended:
						isTopBarRevealed = false
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: .toggleBrowserTopBar)) { notification in
				guard notification.object as? UUID == browser.windowID else { return }
				withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
					showsTopBar.toggle()
					if showsTopBar {
						isTopBarRevealed = false
					}
				}
			}
			.background {
				WindowFocusReader { window in
					hostWindow = window
				}
				.allowsHitTesting(false)
			}
			.onChange(of: hostWindow) { _, _ in updateWindowButtons(animated: false) }
			.onChange(of: topBarHeight) { _, _ in updateWindowButtons() }
			.onChange(of: reduceMotion) { _, _ in updateWindowButtons() }
			.alert("Delete Space?", isPresented: Binding(
				get: { spaceToDelete != nil },
				set: {
					if !$0 {
						spaceToDelete = nil
					}
				}
			), presenting: spaceToDelete) { space in
				Button("Delete Space", role: .destructive) {
					spaceBrowser?.deleteSpace(space.id)
					spaceToDelete = nil
				}
				Button("Cancel", role: .cancel) {
					spaceToDelete = nil
				}
			} message: { space in
				Text("Tabs in \(space.name) will move to another Space.")
			}
			.modifier(BrowserQuitFeedback(browser: browser))
			.ignoresSafeArea()
			.accessibilityIdentifier("mini-astra-window")
		}

		private func requestSpaceDeletion(_ space: BrowserSpace) {
			guard let destination = spaceBrowser, destination.workspace.spaces.count > 1 else { return }
			if destination.requiresSpaceDeletionConfirmation(space.id) {
				spaceToDelete = space
			} else {
				destination.deleteSpace(space.id)
			}
		}

		private func updateWindowButtons(animated: Bool = true) {
			trafficLightAnimator.setHidden(topBarHeight == 0, in: hostWindow, animated: animated, reduceMotion: reduceMotion)
		}
	}
#endif
