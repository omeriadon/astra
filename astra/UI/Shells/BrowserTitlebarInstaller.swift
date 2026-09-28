#if os(macOS)
	import AppKit
	import SwiftUI

	struct BrowserTitlebarInstaller: NSViewRepresentable {
		let browser: Browser

		func makeCoordinator() -> Coordinator {
			Coordinator(browser: browser)
		}

		func makeNSView(context: Context) -> ProbeView {
			let view = ProbeView()
			view.onWindowChange = { [weak coordinator = context.coordinator] window in
				coordinator?.install(on: window)
			}
			return view
		}

		func updateNSView(_: ProbeView, context: Context) {
			context.coordinator.browser = browser
			context.coordinator.updateRootView()
		}

		static func dismantleNSView(_: ProbeView, coordinator: Coordinator) {
			coordinator.uninstall()
		}

		@MainActor
		final class Coordinator {
			var browser: Browser

			private weak var window: NSWindow?
			private var accessoryController: NSTitlebarAccessoryViewController?
			private var hostingView: NSHostingView<BrowserTitlebarControls>?
			private var resizeObserver: NSObjectProtocol?
			private var enterFullScreenObserver: NSObjectProtocol?
			private var exitFullScreenObserver: NSObjectProtocol?

			init(browser: Browser) {
				self.browser = browser
			}

			func install(on window: NSWindow?) {
				guard let window else {
					uninstall()
					return
				}

				if self.window === window {
					updateAccessoryWidth()
					return
				}

				uninstall()
				self.window = window

				// Keep the real, single-row AppKit title bar. A toolbar would add
				// the taller toolbar geometry that we are deliberately avoiding.
				window.toolbar = nil
				window.titleVisibility = .hidden
				window.titlebarSeparatorStyle = .none
				window.tabbingMode = .disallowed

				let hostingView = NSHostingView(
					rootView: BrowserTitlebarControls(browser: browser)
				)
				hostingView.translatesAutoresizingMaskIntoConstraints = true

				let accessoryController = NSTitlebarAccessoryViewController()
				accessoryController.layoutAttribute = .right
				accessoryController.view = hostingView

				window.addTitlebarAccessoryViewController(accessoryController)

				self.hostingView = hostingView
				self.accessoryController = accessoryController

				resizeObserver = NotificationCenter.default.addObserver(
					forName: NSWindow.didResizeNotification,
					object: window,
					queue: .main
				) { [weak self] _ in
					self?.updateAccessoryWidth()
				}

				enterFullScreenObserver = NotificationCenter.default.addObserver(
					forName: NSWindow.didEnterFullScreenNotification,
					object: window,
					queue: .main
				) { [weak self] _ in
					self?.updateAccessoryWidth()
				}

				exitFullScreenObserver = NotificationCenter.default.addObserver(
					forName: NSWindow.didExitFullScreenNotification,
					object: window,
					queue: .main
				) { [weak self] _ in
					self?.updateAccessoryWidth()
				}

				updateAccessoryWidth()

				// Standard window buttons can finish laying out one run-loop turn
				// after the accessory is installed.
				DispatchQueue.main.async { [weak self] in
					self?.updateAccessoryWidth()
				}
			}

			func updateRootView() {
				hostingView?.rootView = BrowserTitlebarControls(browser: browser)
			}

			func uninstall() {
				removeObservers()

				if let window,
				   let accessoryController,
				   let index = window.titlebarAccessoryViewControllers.firstIndex(
				   	where: { $0 === accessoryController }
				   )
				{
					window.removeTitlebarAccessoryViewController(at: index)
				}

				hostingView = nil
				accessoryController = nil
				window = nil
			}

			private func updateAccessoryWidth() {
				guard let window, let view = accessoryController?.view else { return }

				let leftEdge = [
					NSWindow.ButtonType.closeButton,
					.miniaturizeButton,
					.zoomButton,
				]
				.compactMap { window.standardWindowButton($0) }
				.map { button in
					button.convert(button.bounds, to: nil).maxX
				}
				.max() ?? 0

				var frame = view.frame
				frame.size.width = max(0, window.frame.width - leftEdge)
				view.frame = frame
			}

			private func removeObservers() {
				for observer in [
					resizeObserver,
					enterFullScreenObserver,
					exitFullScreenObserver,
				] {
					if let observer {
						NotificationCenter.default.removeObserver(observer)
					}
				}

				resizeObserver = nil
				enterFullScreenObserver = nil
				exitFullScreenObserver = nil
			}

		}

		final class ProbeView: NSView {
			var onWindowChange: ((NSWindow?) -> Void)?

			override func hitTest(_: NSPoint) -> NSView? {
				nil
			}

			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				onWindowChange?(window)
			}
		}
	}

	private struct BrowserTitlebarControls: View {
		@Bindable var browser: Browser
		@Environment(\.colorScheme) private var colorScheme

		private var theme: BrowserTheme {
			browser.theme
		}

		private var titlebarColorScheme: ColorScheme {
			guard let themeColorIsLight = browser.selectedTab?.activeController?.themeColorIsLight else {
				return colorScheme
			}
			return themeColorIsLight ? .light : .dark
		}

		var body: some View {
			HStack(spacing: 10) {
				Button {
					browser.sidebarShown.toggle()
				} label: {
					Label("Toggle Sidebar", systemImage: "sidebar.leading")
						.labelStyle(.iconOnly)
				}
				.buttonStyle(.bordered)
				.accessibilityIdentifier("sidebar-toggle")

				if let controller = browser.selectedTab?.activeController {
					BrowserNavigationControls(controller: controller)
						.controlSize(.regular)
						.labelStyle(.iconOnly)
						.buttonSizing(.fitted)
						.buttonStyle(.bordered)
						.foregroundStyle(theme.foregroundColor)
						.id(ObjectIdentifier(controller))
				}

				if browser.selectedTab?.internalPage == nil {
					BrowserAddressField(browser: browser)
						.fixedSize(horizontal: true, vertical: false)
						.overlay(alignment: .bottom) {
							if let controller = browser.selectedTab?.activeController {
								BrowserLoadingBar(
									isLoading: controller.isLoading,
									estimatedProgress: controller.estimatedProgress,
									theme: theme
								)
								.frame(height: 1.5)
								.id(browser.selectedTabID)
							}
						}
				}

				Color.clear
					.contentShape(Rectangle())
					.gesture(WindowDragGesture())
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.accessibilityHidden(true)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(theme.tabColor)
			.foregroundStyle(theme.foregroundColor)
			.environment(\.colorScheme, titlebarColorScheme)
		}
	}
#endif
