#if os(macOS)
	import AppKit
	import KeyboardShortcuts
	import Observation
	import SwiftUI

	/// App-local shortcuts are menu equivalents, not global hotkeys. The recorder
	/// owns storage; AppKit retains first-responder routing and menu validation.
	@MainActor
	@Observable
	final class BrowserShortcutRegistry {
		static let shared = BrowserShortcutRegistry()

		struct Definition: Identifiable {
			let id: String
			let title: String
			let section: String
			let name: KeyboardShortcuts.Name
		}

		private final class MenuBinding {
			weak var item: NSMenuItem?
			let name: KeyboardShortcuts.Name

			init(_ item: NSMenuItem, name: KeyboardShortcuts.Name) {
				self.item = item
				self.name = name
			}
		}

		private(set) var definitions: [Definition] = []
		private(set) var revision = 0
		@ObservationIgnored private var menuBindings: [MenuBinding] = []

		private init() {
			registerSpecial("Next Tab", section: "Tab", key: .tab, modifiers: [.control])
			registerSpecial("Previous Tab", section: "Tab", key: .backtick, modifiers: [.control])
			registerSpecial("Open Mini Astra Globally", section: "Window", key: .n, modifiers: [.command, .control, .option])
		}

		private func identifier(_ title: String, section: String) -> String {
			"astraShortcut_" + (section + "_" + title).map {
				$0.isLetter || $0.isNumber ? String($0) : "_"
			}.joined()
		}

		private func registerSpecial(
			_ title: String,
			section: String,
			key: KeyboardShortcuts.Key,
			modifiers: NSEvent.ModifierFlags
		) {
			let name = KeyboardShortcuts.Name(
				identifier(title, section: section),
				initial: .init(key, modifiers: modifiers)
			)
			definitions.append(Definition(id: name.rawValue, title: title, section: section, name: name))
		}

		func definition(_ title: String, section: String) -> Definition? {
			definitions.first { $0.title == title && $0.section == section }
		}

		func shortcut(_ title: String, section: String) -> KeyboardShortcuts.Shortcut? {
			definition(title, section: section).flatMap { KeyboardShortcuts.getShortcut(for: $0.name) }
		}

		func tabDirection(for event: NSEvent) -> Bool? {
			guard !event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
			      let pressed = KeyboardShortcuts.Shortcut(event: event) else { return nil }
			if pressed == shortcut("Next Tab", section: "Tab") {
				return true
			}
			if pressed == shortcut("Previous Tab", section: "Tab") {
				return false
			}
			return nil
		}

		func attach(menu: NSMenu) {
			menuBindings.removeAll()
			for root in menu.items {
				guard let submenu = root.submenu else { continue }
				registerMenu(submenu, section: root.title)
			}
			refreshMenus()
		}

		private func registerMenu(_ menu: NSMenu, section: String) {
			for item in menu.items {
				if let submenu = item.submenu {
					registerMenu(submenu, section: section)
					continue
				}
				guard !item.keyEquivalent.isEmpty,
				      let key = Self.key(for: item.keyEquivalent) else { continue }
				let name = KeyboardShortcuts.Name(
					identifier(item.title, section: section),
					initial: .init(key, modifiers: item.keyEquivalentModifierMask)
				)
				if !definitions.contains(where: { $0.id == name.rawValue }) {
					definitions.append(Definition(id: name.rawValue, title: item.title, section: section, name: name))
				}
				menuBindings.append(MenuBinding(item, name: name))
			}
		}

		func refreshMenus() {
			for binding in menuBindings {
				guard let item = binding.item else { continue }
				let shortcut = KeyboardShortcuts.getShortcut(for: binding.name)
				item.keyEquivalent = shortcut?.nsMenuItemKeyEquivalent ?? ""
				item.keyEquivalentModifierMask = shortcut?.modifiers ?? []
			}
		}

		func menuKeyboardShortcut(_ title: String, section: String) -> KeyboardShortcut? {
			_ = revision
			return shortcut(title, section: section)?.toSwiftUI
		}

		func didEditShortcut() {
			revision &+= 1
			refreshMenus()
			MiniAstraShortcut.shared.update()
		}

		func conflict(for candidate: KeyboardShortcuts.Shortcut, excluding definition: Definition) -> Definition? {
			definitions.first {
				$0.id != definition.id && KeyboardShortcuts.getShortcut(for: $0.name) == candidate
			}
		}

		func resetAllDefaults() {
			KeyboardShortcuts.reset(definitions.map(\.name))
			didEditShortcut()
		}

		private static func key(for equivalent: String) -> KeyboardShortcuts.Key? {
			switch equivalent.lowercased() {
				case "a": .a
				case "b": .b
				case "c": .c
				case "d": .d
				case "e": .e
				case "f": .f
				case "g": .g
				case "h": .h
				case "i": .i
				case "j": .j
				case "k": .k
				case "l": .l
				case "m": .m
				case "n": .n
				case "o": .o
				case "p": .p
				case "q": .q
				case "r": .r
				case "s": .s
				case "t": .t
				case "u": .u
				case "v": .v
				case "w": .w
				case "x": .x
				case "y": .y
				case "z": .z
				case "0": .zero
				case "1": .one
				case "2": .two
				case "3": .three
				case "4": .four
				case "5": .five
				case "6": .six
				case "7": .seven
				case "8": .eight
				case "9": .nine
				case ",": .comma
				case "=": .equal
				case "-": .minus
				case "[": .leftBracket
				case "]": .rightBracket
				case "←": .leftArrow
				case "→": .rightArrow
				default: nil
			}
		}
	}
#endif
