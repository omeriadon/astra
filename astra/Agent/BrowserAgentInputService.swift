#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
	import AppKit
	import Foundation
	import WebKit

	/// Targeted AppKit input never posts global events or controls another application.
	@MainActor
	enum BrowserAgentInputService {
		static let keyOperations: Set<String> = ["press_key", "key_down", "key_up"]
		private static let keys: [String: (UInt16, String)] = [
			"Enter": (36, "\r"), "Return": (36, "\r"), "Escape": (53, "\u{1B}"),
			"Tab": (48, "\t"), "Backspace": (51, "\u{8}"), "Delete": (117, "\u{7F}"),
			"ArrowLeft": (123, "\u{F702}"), "ArrowRight": (124, "\u{F703}"),
			"ArrowDown": (125, "\u{F701}"), "ArrowUp": (126, "\u{F700}"),
			"Home": (115, "\u{F729}"), "End": (119, "\u{F72B}"),
			"F1": (122, "\u{F704}"), "F2": (120, "\u{F705}"), "F3": (99, "\u{F706}"), "F4": (118, "\u{F707}"),
			"F5": (96, "\u{F708}"), "F6": (97, "\u{F709}"), "F7": (98, "\u{F70A}"), "F8": (100, "\u{F70B}"),
			"F9": (101, "\u{F70C}"), "F10": (109, "\u{F70D}"), "F11": (103, "\u{F70E}"), "F12": (111, "\u{F70F}"),
			"PageUp": (116, "\u{F72C}"), "PageDown": (121, "\u{F72D}"), "Space": (49, " "),
		]
		private static let letters: [String: UInt16] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46]
		private static let digits: [String: UInt16] = ["1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29]

		static func key(_ operation: String, arguments: [String: Any], view: WKWebView) throws -> [String: Any] {
			guard let window = unsafe view.window, window.isVisible, !view.isHidden,
			      let raw = arguments["key"] as? String else { throw InputError("INPUT_TARGET_UNAVAILABLE: Select the intended tab in a visible window and supply key.") }
			let modifiers = arguments["modifiers"] as? [String] ?? []
			var flags: NSEvent.ModifierFlags = []
			for modifier in modifiers {
				switch modifier.lowercased() {
					case "command", "cmd", "meta": flags.insert(.command)
					case "control", "ctrl": flags.insert(.control)
					case "option", "alt": flags.insert(.option)
					case "shift": flags.insert(.shift)
					default: throw InputError("INVALID_ARGUMENT: Unknown key modifier.")
				}
			}
			let key: (UInt16, String)
			if raw == "Shift-Tab" {
				key = keys["Tab"]!; flags.insert(.shift)
			} else if let special = keys[raw] {
				key = special
			} else if raw.count == 1, let code = digits[raw] {
				key = (code, raw)
			} else if raw.count == 1, let code = letters[raw.lowercased()] {
				key = (code, raw)
			} else {
				throw InputError("UNSUPPORTED_KEY: Supported named navigation keys and letter shortcuts only.")
			}
			guard window.makeFirstResponder(view) else { throw InputError("INPUT_TARGET_UNAVAILABLE: WebKit could not receive keyboard focus.") }
			let target = window.firstResponder ?? view
			func send(_ type: NSEvent.EventType) throws {
				guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
				                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
				                                   context: nil, characters: key.1, charactersIgnoringModifiers: key.1.lowercased(), isARepeat: false, keyCode: key.0) else { throw InputError("INPUT_UNAVAILABLE: AppKit did not create the event.") }
				if type == .keyDown {
					target.keyDown(with: event)
				} else {
					target.keyUp(with: event)
				}
			}
			if operation != "key_up" {
				try send(.keyDown)
			}
			if operation != "key_down" {
				try send(.keyUp)
			}
			return ["dispatched": true, "inputSource": "native_appkit", "trusted": NSNull(),
			        "trustReason": "Delivered through AppKit responder APIs; DOM trust and website postconditions must be verified."]
		}

		static func pointer(_ operation: String, arguments: [String: Any], view: WKWebView, point: CGPoint) throws -> [String: Any] {
			guard let window = unsafe view.window, window.isVisible, !view.isHidden, view.bounds.contains(point) else { throw InputError("INPUT_TARGET_UNAVAILABLE: Native pointer input requires a visible viewport.") }
			window.makeKeyAndOrderFront(nil)
			window.makeFirstResponder(view)
			let location = view.convert(point, to: nil)
			let parent = unsafe view.superview
			guard let target = view.hitTest(view.convert(point, to: parent)) else { throw InputError("INPUT_TARGET_UNAVAILABLE: No WebKit target at coordinates.") }
			let right = operation == "right_click"
			let modifiers = arguments["modifiers"] as? [String] ?? []
			var flags: NSEvent.ModifierFlags = []
			for modifier in modifiers {
				switch modifier.lowercased() {
					case "command", "cmd", "meta": flags.insert(.command)
					case "control", "ctrl": flags.insert(.control)
					case "option", "alt": flags.insert(.option)
					case "shift": flags.insert(.shift)
					default: throw InputError("INVALID_ARGUMENT: Unknown pointer modifier.")
				}
			}
			func send(_ type: NSEvent.EventType, count: Int) throws {
				guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags,
				                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
				                                     eventNumber: 0, clickCount: count, pressure: 1) else { throw InputError("INPUT_UNAVAILABLE: AppKit did not create pointer event.") }
				switch type {
					case .leftMouseDown: target.mouseDown(with: event)
					case .leftMouseUp: target.mouseUp(with: event)
					case .rightMouseDown: target.rightMouseDown(with: event)
					case .rightMouseUp: target.rightMouseUp(with: event)
					default: target.mouseMoved(with: event)
				}
			}
			if operation == "hover" || operation == "move_pointer" {
				try send(.mouseMoved, count: 0)
			} else {
				try send(right ? .rightMouseDown : .leftMouseDown, count: 1)
				try send(right ? .rightMouseUp : .leftMouseUp, count: 1)
				if operation == "double_click" {
					try send(.leftMouseDown, count: 2); try send(.leftMouseUp, count: 2)
				}
			}
			return ["dispatched": true, "inputSource": "native_appkit", "trusted": NSNull(), "postconditionVerified": false]
		}

		private struct InputError: LocalizedError {
			let message: String
			init(_ message: String) {
				self.message = message
			}

			var errorDescription: String? {
				message
			}
		}
	}
#endif
