#if os(macOS)
	import Carbon
	import Defaults
	import KeyboardShortcuts
	import Observation

	@MainActor
	@Observable
	@safe
	final class MiniAstraShortcut {
		static let shared = MiniAstraShortcut()
		static let notification = Notification.Name("MiniAstraShortcutPressed")
		private(set) var registrationFailed = false
		@ObservationIgnored private var hotKey: EventHotKeyRef?
		@ObservationIgnored private var handler: EventHandlerRef?

		func update() {
			if let hotKey = unsafe hotKey {
				unsafe UnregisterEventHotKey(hotKey)
				unsafe self.hotKey = nil
			}
			registrationFailed = false
			if unsafe handler == nil {
				var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
				let status = unsafe InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
					NotificationCenter.default.post(name: Notification.Name("MiniAstraShortcutPressed"), object: nil)
					return noErr
				}, 1, &event, nil, &handler)
				guard status == noErr else {
					registrationFailed = true
					return
				}
			}
			guard let shortcut = BrowserShortcutRegistry.shared.shortcut("Open Mini Astra Globally", section: "Window") else { return }
			let status = unsafe RegisterEventHotKey(
				UInt32(shortcut.carbonKeyCode),
				UInt32(shortcut.carbonModifiers),
				EventHotKeyID(signature: 0x4153_5452, id: 1),
				GetApplicationEventTarget(),
				0,
				&hotKey
			)
			registrationFailed = status != noErr
		}
	}
#endif
