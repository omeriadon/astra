import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
	private let lifecycleLogger = LifecycleLogger()
	private var window: NSWindow?

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.regular)
		let content = NSHostingView(
			rootView: NavigationStack {
				GlassIdleProbeView()
			}
		)
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Glass Idle Probe"
		window.contentView = content
		window.center()
		window.makeKeyAndOrderFront(nil)
		NSApp.activate()
		self.window = window
		lifecycleLogger.start()
		_ = notification
	}
}
