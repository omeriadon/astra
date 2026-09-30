#if os(macOS)
	import SwiftUI

	struct MiniAstraView: View {
		let browser: Browser
		let promote: () -> Void

		var body: some View {
			VStack(spacing: 0) {
				MiniAstraTopBar(browser: browser, promote: promote)
				BrowserContentView(browser: browser)
			}
			.background {
				BrowserThemeBackground(theme: browser.theme)
			}
			.ignoresSafeArea()
			.accessibilityIdentifier("mini-astra-window")
		}
	}

	private struct MiniAstraTopBar: View {
		let browser: Browser
		let promote: () -> Void

		var body: some View {
			HStack(spacing: 8) {
				if let controller = browser.selectedTab?.controller {
					BrowserNavigationControls(controller: controller)
				}
				BrowserAddressField(browser: browser)
					.padding(.horizontal, 10)
					.padding(.vertical, 8)
					.background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
				Button("Move to Workspace", systemImage: "arrow.up.right.square", action: promote)
					.labelStyle(.iconOnly)
					.help("Move this tab to the main workspace")
					.accessibilityLabel("Move to Workspace")
					.accessibilityIdentifier("mini-astra-promote")
			}
			.buttonStyle(.glass)
			.padding(.leading, 78)
			.padding(.trailing, 10)
			.frame(height: 52)
			.background {
				WindowDragBackground()
			}
			.accessibilityIdentifier("mini-astra-top-bar")
		}
	}
#endif
