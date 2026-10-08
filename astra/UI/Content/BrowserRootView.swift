import Defaults
import SwiftUI

struct BrowserRootView: View {
	@Binding var browser: Browser
	@State private var sync = BrowserSync.shared
	@Default(.historyRetentionDays) private var historyRetentionDays
	@Environment(\.scenePhase) private var scenePhase

	#if os(macOS)
		@State private var controlTabSwitcher: ControlTabSwitcher
		@State private var hostWindow: NSWindow?
	#endif

	init(browser: Binding<Browser>) {
		_browser = browser
		#if os(macOS)
			_controlTabSwitcher = State(initialValue: ControlTabSwitcher(browser: browser.wrappedValue))
		#endif
	}

	#if os(iOS)
		@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	#endif

	var body: some View {
		shell
			.allowsHitTesting(!browser.showsQuickSearch)
			.accessibilityHidden(browser.showsQuickSearch)
			.overlay {
				if browser.showsQuickSearch {
					BrowserQuickSearchOverlay(browser: browser)
				}
			}
			.overlay(alignment: .bottom) {
				if let error = browser.persistenceErrorDescription {
					Label(error, systemImage: "exclamationmark.triangle")
						.font(.caption)
						.padding(12)
						.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
						.padding(12)
						.accessibilityIdentifier("session-save-error")
				}
			}
			.onAppear {
				sync.attach(browser)
			}
			.onChange(of: historyRetentionDays) { _, _ in
				browser.applyHistoryRetention()
			}
			.onChange(of: scenePhase) { _, phase in
				if phase != .active {
					browser.flushPersistence()
				}
			}
		#if os(macOS)
			.background {
				BrowserDropZone(
					browser: browser,
					area: .normal,
					spaceID: browser.workspace.selectedSpaceID,
					beforeTabID: nil,
					isWindowFallback: true
				)
			}
			.background {
				WindowFocusReader { window in
					hostWindow = window
					controlTabSwitcher.setWindow(window)
					if window?.isKeyWindow == true {
						BrowserWindowRegistry.shared.activate(browser)
					}
				}
				.allowsHitTesting(false)
			}
			.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
				if let window = notification.object as? NSWindow, window === hostWindow {
					BrowserWindowRegistry.shared.activate(browser)
				}
			}
			.overlay {
				ControlTabSwitcherPreview(browser: browser, switcher: controlTabSwitcher)
					.animation(.easeInOut(duration: 0.05), value: controlTabSwitcher.isPreviewVisible)
			}
			.onAppear {
				controlTabSwitcher.start()
			}
			.onChange(of: browser.visibleTabs.map(\.id)) { _, _ in
				controlTabSwitcher.tabsDidChange()
			}
			.onDisappear {
				controlTabSwitcher.stop()
			}
			.modifier(BrowserQuitFeedback(browser: browser))
		#endif
	}

	@ViewBuilder
	var shell: some View {
		#if os(macOS)
			DesktopBrowserShell(browser: browser)
		#elseif os(iOS)
			if horizontalSizeClass == .compact {
				CompactBrowserShell(browser: browser)
			} else {
				DesktopBrowserShell(browser: browser)
			}
		#else
			DesktopBrowserShell(browser: browser)
		#endif
	}
}

#if os(macOS)
	struct BrowserQuitFeedback: ViewModifier {
		let browser: Browser
		@State private var quitExpiry: Date = .distantPast

		func body(content: Content) -> some View {
			content
				.blur(radius: browser.isAboutToQuit ? 5 : 0)
				.overlay(alignment: .center) {
					if Date.now < quitExpiry {
						QuitBannerOverlay(quitExpiry: quitExpiry)
					}
				}
				.onChange(of: browser.isAboutToQuit) { _, newValue in
					if newValue {
						quitExpiry = .now.addingTimeInterval(1)
					}
				}
				.task(id: quitExpiry) {
					guard quitExpiry > .now else { return }
					try? await Task.sleep(until: .now + .seconds(quitExpiry.timeIntervalSinceNow))
					guard !Task.isCancelled, Date.now >= quitExpiry else { return }
					browser.isAboutToQuit = false
					quitExpiry = .distantPast
				}
				.animation(.snappy(duration: 0.2), value: Date.now < quitExpiry)
		}
	}

	private struct QuitBannerOverlay: View {
		let quitExpiry: Date

		var body: some View {
			TimelineView(.animation) { timeline in
				let showQuitMessage = timeline.date < quitExpiry

				GlassEffectContainer {
					if showQuitMessage {
						ZStack {
							Rectangle()
								.fill(Color.black.gradient)
								.opacity(0.2)

							Label {
								Text("Press \(Image(systemName: "command"))Q again to quit")
							} icon: {
								Image(systemName: "rectangle.portrait.and.arrow.right")
							}
							.monospaced()
							.font(.title2)
							.padding(.horizontal, 20)
							.padding(.vertical, 16)
							.glassEffect(
								.regular,
								in: RoundedRectangle(cornerRadius: 20)
							)
							.glassEffectTransition(.materialize)
						}
					}
				}
				.animation(.snappy(duration: 0.2), value: showQuitMessage)
			}
		}
	}
#endif
