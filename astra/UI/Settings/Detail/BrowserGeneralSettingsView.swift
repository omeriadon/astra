import Defaults
import SwiftUI

#if os(macOS)
	import AppKit
	import Sparkle
#endif

let addressDisplayStyleSpacing: CGFloat = 8

struct BrowserGeneralSettingsView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Default(.addressDisplayStyle) private var addressDisplayStyle
	@Default(.peekLevel) private var peekLevel
	@Default(.zoomOutInPeeks) private var zoomOutInPeeks
	@Default(.renameDownloadsWithAppleIntelligence) private var renameDownloadsWithAppleIntelligence

	#if os(macOS)
		@Bindable private var updates = UpdateManager.shared
		@State private var isDefaultBrowser = false
		@State private var isSettingDefaultBrowser = false
		@State private var defaultBrowserError: String?
		@Default(.miniAstraEnabled) private var miniAstraEnabled
		@Default(.miniAstraWindowAnimation) private var miniAstraWindowAnimation
		@Default(.miniAstraShortcutEnabled) private var miniAstraShortcutEnabled
	#endif

	var body: some View {
		List {
			#if os(macOS)
				Section("Default Browser") {
					Text(isDefaultBrowser ? "Astra is your default browser." : "Open web links from other apps in Astra.")
						.foregroundStyle(.secondary)
						.accessibilityIdentifier("default-browser-status")

					Button("Make Default Browser", systemImage: "globe", role: .confirm) {
						Task { await makeDefaultBrowser() }
					}
					.buttonStyle(.glassProminent)
					.disabled(isDefaultBrowser || isSettingDefaultBrowser)
					.accessibilityLabel("Make Astra the default web browser")
					.accessibilityIdentifier("make-default-browser")
					.id("Make Default Browser")

					if let defaultBrowserError {
						Text(defaultBrowserError)
							.foregroundStyle(.red)
							.accessibilityIdentifier("default-browser-error")
					}
				}
				.id("Default Browser")
				.onAppear(perform: refreshDefaultBrowser)
				.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
					refreshDefaultBrowser()
				}
			#endif

			Section("Address Bar") {
				VStack(spacing: addressDisplayStyleSpacing) {
					ForEach(AddressDisplayStyle.allCases) { style in
						addressDisplayStyleOption(style: style)
							.id(style.title)
					}
				}
				.accessibilityElement(children: .contain)
				.accessibilityIdentifier("address-display-style-picker")
				.id("Address Bar")
			}

			#if os(macOS)
				Section("Mini Astra") {
					Toggle("Open links from other apps in Mini Astra", isOn: $miniAstraEnabled)
						.accessibilityIdentifier("mini-astra-enabled")

					Toggle("Animate Mini Astra from the pointer", isOn: $miniAstraWindowAnimation)
						.accessibilityIdentifier("mini-astra-window-animation")

					if miniAstraWindowAnimation {
						Text("Expands the window from the pointer position. Respects Reduce Motion.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}

					Toggle("Enable global shortcut: ⌃⌥⌘N", isOn: $miniAstraShortcutEnabled)
						.accessibilityLabel("Enable global Mini Astra shortcut: Control Option Command N")
						.accessibilityIdentifier("mini-astra-shortcut-enabled")
						.onChange(of: miniAstraShortcutEnabled) { _, _ in
							MiniAstraShortcut.shared.update()
						}
					Text("Opens a blank Mini Astra window from any app while Astra is running.")
						.font(.caption)
						.foregroundStyle(.secondary)
					if MiniAstraShortcut.shared.registrationFailed {
						Text("The shortcut could not be registered. Disable any conflicting shortcut, then enable it again.")
							.foregroundStyle(.red)
					}
				}
			#endif

			Section("Peek") {
				Picker("Levels", selection: $peekLevel) {
					ForEach(PeekLevel.allCases) { level in
						Text(level.title)
							.tag(level)
					}
				}
				.accessibilityIdentifier("peek-level-picker")
				.id("Levels")

				if peekLevel != .none {
					Toggle("Zoom out in Peeks", isOn: $zoomOutInPeeks)
						.accessibilityIdentifier("zoom-out-in-peeks-toggle")
						.id("Zoom out in Peeks")
				}
			}
			.id("Peek")

			Section("Downloads") {
				Toggle("Rename downloads with Apple Intelligence", isOn: $renameDownloadsWithAppleIntelligence)
					.accessibilityLabel("Rename downloads with Apple Intelligence")
					.accessibilityIdentifier("rename-downloads-with-apple-intelligence")
					.id("Rename downloads with Apple Intelligence")
			}
			.id("Downloads")

			#if os(macOS)
				Section("Updates") {
					Toggle("Automatically check for updates", isOn: $updates.automaticChecks)
						.accessibilityIdentifier("automatically-check-for-updates")
						.id("Automatically check for updates")

					Toggle("Automatically install updates", isOn: $updates.automaticInstalls)
						.disabled(!updates.automaticChecks || !updates.updater.allowsAutomaticUpdates)
						.accessibilityIdentifier("automatically-install-updates")
						.id("Automatically install updates")
				}
				.id("Updates")
			#endif
		}
		.scrollContentBackground(.hidden)
		#if os(iOS)
			.listStyle(.insetGrouped)
		#else
			.listStyle(.sidebar)
		#endif
	}

	#if os(macOS)
		private func refreshDefaultBrowser() {
			isDefaultBrowser = ["http", "https"].allSatisfy { scheme in
				guard let url = URL(string: "\(scheme)://example.com"),
				      let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url),
				      let bundleIdentifier = Bundle.main.bundleIdentifier
				else { return false }
				return Bundle(url: applicationURL)?.bundleIdentifier == bundleIdentifier
			}
		}

		private func makeDefaultBrowser() async {
			isSettingDefaultBrowser = true
			defaultBrowserError = nil
			defer {
				isSettingDefaultBrowser = false
				refreshDefaultBrowser()
			}
			do {
				for scheme in ["http", "https"] {
					try await NSWorkspace.shared.setDefaultApplication(
						at: Bundle.main.bundleURL,
						toOpenURLsWithScheme: scheme
					)
				}
			} catch {
				defaultBrowserError = error.localizedDescription
			}
		}
	#endif

	private func addressDisplayStyleOption(style: AddressDisplayStyle) -> some View {
		Button {
			addressDisplayStyle = style
		} label: {
			VStack(alignment: .leading, spacing: 8) {
				Label(style.title, systemImage: addressDisplayStyle == style ? "checkmark.circle.fill" : "circle")
					.font(.headline)

				VStack(spacing: 4) {
					ZStack {
						switch style {
							case .full:
								Text(verbatim: "https://apple.com")

							case .simple:
								Text("apple.com")

							case .dimmed:
								Text(
									"\(Text(verbatim: "https://").foregroundStyle(.tertiary))\(Text(verbatim: "apple.com"))"
								)
						}
					}
					.lineLimit(1)
					.truncationMode(.middle)
					.padding(.vertical, 4)
					.padding(.horizontal, 6)
					.frame(maxWidth: .infinity, alignment: .leading)
					.clipped()
					.background {
						RoundedRectangle(cornerRadius: 9)
							.fill(Color.white.opacity(0.2))
							.strokeBorder(.white.opacity(0.3), lineWidth: 1)
					}

					ZStack {
						switch style {
							case .full:
								HStack(spacing: 4) {
									Image(systemName: "magnifyingglass")

									Text(verbatim: "https://www.google.com/search?q=apple")
								}

							case .simple:
								HStack(spacing: 4) {
									Image(systemName: "magnifyingglass")

									Text("apple")
								}

							case .dimmed:
								HStack(spacing: 4) {
									Image(systemName: "magnifyingglass")

									Text(
										"\(Text(verbatim: "https://www.google.com/search?q=").foregroundStyle(.tertiary))\(Text(verbatim: "apple"))"
									)
								}
						}
					}
					.lineLimit(1)
					.truncationMode(.middle)
					.padding(.vertical, 4)
					.padding(.horizontal, 6)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background {
						RoundedRectangle(cornerRadius: 9)
							.fill(Color.white.opacity(0.2))
							.strokeBorder(.white.opacity(0.3), lineWidth: 1)
					}
				}
			}
			.padding(12)
			.frame(maxWidth: .infinity, alignment: .leading)
			.contentShape(RoundedRectangle(cornerRadius: 15))
			.overlay {
				RoundedRectangle(cornerRadius: 15)
					.fill(Color.primary.opacity(addressDisplayStyle == style ? 0.2 : 0.0))
					.strokeBorder(.white.opacity(addressDisplayStyle == style ? 0.6 : 0.3), lineWidth: 1)
			}
		}
		.buttonStyle(.plain)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(style.title)
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(addressDisplayStyle == style ? .isSelected : [])
		.accessibilityIdentifier("address-display-style-\(style.rawValue)")
		.animation(reduceMotion ? nil : .smooth(duration: 0.15), value: addressDisplayStyle == style)
	}
}
