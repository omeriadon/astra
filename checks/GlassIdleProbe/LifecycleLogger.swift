import AppKit
import OSLog

let probeLogger = Logger(subsystem: "com.omeriadon.astra.GlassIdleProbe", category: "lifecycle")

final class LifecycleLogger: NSObject {
	private var observations: [NSObjectProtocol] = []

	func start() {
		let center = NotificationCenter.default
		let names: [Notification.Name] = [
			NSWindow.didBecomeKeyNotification,
			NSWindow.didChangeOcclusionStateNotification,
			NSWindow.didMiniaturizeNotification,
			NSWindow.didDeminiaturizeNotification,
			NSApplication.didHideNotification,
			NSApplication.didUnhideNotification,
		]
		observations = []
		for name in names {
			let eventName = name.rawValue
			observations.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
				Task { @MainActor in
					let window = NSApp.keyWindow
					let visible = window?.occlusionState.contains(.visible) ?? false
					let miniaturized = window?.isMiniaturized ?? false
					probeLogger.info("event=\(eventName, privacy: .public) appHidden=\(NSApp.isHidden, privacy: .public) appActive=\(NSApp.isActive, privacy: .public) windowVisible=\(visible, privacy: .public) windowMiniaturized=\(miniaturized, privacy: .public)")
				}
			})
		}
	}

	deinit {
		observations.forEach(NotificationCenter.default.removeObserver)
	}
}
