import AppKit
import SwiftUI

struct WindowVisibilityReader: NSViewRepresentable {
	let onChange: (Bool) -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(onChange: onChange)
	}

	func makeNSView(context: Context) -> NSView {
		let view = TrackingView(frame: .zero)
		view.coordinator = context.coordinator
		context.coordinator.attach(view)
		return view
	}

	func updateNSView(_ nsView: NSView, context: Context) {
		context.coordinator.attach(nsView)
	}

	static func dismantleNSView(_: NSView, coordinator: Coordinator) {
		coordinator.stop()
	}

	@MainActor
	final class Coordinator: NSObject {
		private weak var view: NSView?
		private weak var window: NSWindow?
		private var observations: [NSObjectProtocol] = []
		private var currentValue = false
		private var hasLoggedSnapshot = false
		private let onChange: (Bool) -> Void

		init(onChange: @escaping (Bool) -> Void) {
			self.onChange = onChange
		}

		@MainActor
		func attach(_ view: NSView) {
			self.view = view
			guard window !== view.window || window == nil else {
				publish()
				return
			}
			stop()
			self.window = view.window
			guard let window else {
				publish()
				return
			}
			let center = NotificationCenter.default
			let names: [Notification.Name] = [
				NSWindow.didChangeOcclusionStateNotification,
				NSWindow.didMiniaturizeNotification,
				NSWindow.didDeminiaturizeNotification,
				NSApplication.didHideNotification,
				NSApplication.didUnhideNotification,
			]
			observations = names.map { name in
				center.addObserver(forName: name, object: nil, queue: .main) { [weak self, weak window] notification in
					let notificationWindow = notification.object as? NSWindow
					MainActor.assumeIsolated { [weak self, weak window] in
						guard let self, let window else { return }
						guard name == NSApplication.didHideNotification || name == NSApplication.didUnhideNotification || notificationWindow === window else { return }
						publish()
					}
				}
			}
			publish()
		}

		@MainActor
		func stop() {
			observations.forEach(NotificationCenter.default.removeObserver)
			observations.removeAll()
			window = nil
		}

		@MainActor
		private func publish() {
			let value = canRenderWindow(
				appHidden: NSApp.isHidden,
				windowVisible: window?.isVisible ?? false,
				miniaturized: window?.isMiniaturized ?? false,
				occlusionVisible: window?.occlusionState.contains(.visible) ?? false
			)
			guard !hasLoggedSnapshot || value != currentValue else { return }
			currentValue = value
			hasLoggedSnapshot = true
			probeLogger.info("windowState windowExists=\(window != nil, privacy: .public) windowVisible=\(window?.isVisible ?? false, privacy: .public) windowMiniaturized=\(window?.isMiniaturized ?? false, privacy: .public) occlusionVisible=\(window?.occlusionState.contains(.visible) ?? false, privacy: .public) appHidden=\(NSApp.isHidden, privacy: .public) canRender=\(value, privacy: .public)")
			onChange(value)
		}
	}
}

@MainActor
private final class TrackingView: NSView {
	weak var coordinator: WindowVisibilityReader.Coordinator?

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		coordinator?.attach(self)
	}
}
