import Defaults
import SwiftUI

let addressDisplayStyleSpacing: CGFloat = 8

struct BrowserGeneralSettingsView: View {
	@Default(.tabSwitchingOrder) private var tabSwitchingOrder
	@Default(.addressDisplayStyle) private var addressDisplayStyle
	@Default(.peekLevel) private var peekLevel
	@Default(.zoomOutInPeeks) private var zoomOutInPeeks
	@Default(.renameDownloadsWithAppleIntelligence) private var renameDownloadsWithAppleIntelligence

	var body: some View {
		List {
			Section("Tab Switching") {
				Picker("Control-Tab order", selection: $tabSwitchingOrder) {
					ForEach(TabSwitchingOrder.allCases) { order in
						Text(order.title)
							.tag(order)
					}
				}
				.accessibilityIdentifier("tab-switching-order-picker")
			}

			Section("Address Bar") {
				VStack(spacing: addressDisplayStyleSpacing) {
					ForEach(AddressDisplayStyle.allCases) { style in
						addressDisplayStyleOption(style: style)
					}
				}
				.padding(5)
				.background {
					Color.primary.opacity(0.1)
						.clipShape(RoundedRectangle(cornerRadius: 20))
				}
				.accessibilityIdentifier("address-display-style-picker")
			}

			Section("Peek") {
				Picker("Levels", selection: $peekLevel) {
					ForEach(PeekLevel.allCases) { level in
						Text(level.title)
							.tag(level)
					}
				}
				.accessibilityIdentifier("peek-level-picker")

				if peekLevel != .none {
					Toggle("Zoom out in Peeks", isOn: $zoomOutInPeeks)
						.accessibilityIdentifier("zoom-out-in-peeks-toggle")
				}
			}

			Section("Website Data") {
				Button(role: .destructive, action: FaviconStore.shared.clear) {
					Label("Clear All Favicons", systemImage: "trash")
				}
				.disabled(FaviconStore.shared.isEmpty)
				.accessibilityIdentifier("clear-all-favicons")
			}

			Section("Downloads") {
				Toggle("Rename downloads with Apple Intelligence", isOn: $renameDownloadsWithAppleIntelligence)
					.accessibilityLabel("Rename downloads with Apple Intelligence")
					.accessibilityIdentifier("rename-downloads-with-apple-intelligence")
			}
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
	}

	private func addressDisplayStyleOption(style: AddressDisplayStyle) -> some View {
		HStack {
			Text(style.title)
				.padding(.leading, 10)
				.frame(width: 70, alignment: .leading)

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
				.padding(.vertical, 4)
				.padding(.leading, 6)
				.fixedSize(horizontal: true, vertical: false)
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

								Text(verbatim: "https://www.google.com/search?q=apple&newwindow=1&sca_esv=bf93e7ad4ce70d45&sxsrf=APpeQnuqYbYJLPhMn5oNNgwYj17zOxJ_BQ%3A1790315221453&ei=1Qq2auqlG9LT1sQP-vi3uAM&biw=1515&bih=943&ved=2ahUKEwiq5L32g4mXAxXSqZUCHXr8DTcQ4dUDegQIBhAN&uact=5&oq=apple&gs_lp=Egxnd3Mtd2l6LXNlcnAiBWFwcGxlMgQQIxgnMgQQIxgnMgQQIxgnMhkQLhiABBiKBRhDGLEDGIMBGMkDGMcBGNEDMhAQABiABBiKBRhDGLEDGIMBMhAQABiABBiKBRhDGLEDGIMBMhAQABiABBiKBRhDGLEDGIMBMhAQABiABBiKBRhDGLEDGIMBMgoQABiABBiKBRhDMhQQLhiABBixAxiDARiSAxjHARivAUjvClAAWKkJcAB4AZABAJgBgwigAb0VqgELMi0xLjUtMS4xLjG4AQPIAQD4AQGYAgSgAskVmAMAkgcJMy0xLjAuMi4xoAf8LbIHCTMtMS4wLjIuMbgHyRXCBwUwLjMuMcgHB4AIAQ&sclient=gws-wiz-serp")
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
									"\(Text(verbatim: "https://www.google.com/search?q=").foregroundStyle(.tertiary))\(Text(verbatim: "apple"))\(Text(verbatim: "&sca_esv=bf93e7ad4ce70d45&sxsrf=APpeQnvBa9UzORU_4vLzBenh_U84tBEIrQ%3A1790315249202&ei=8Qq2aqn6C_zd1sQP-oS74Q8&biw=1069&bih=769&ved=2ahUKEwjpttuDhImXAxX8rpUCHXrCLvwQ4dUDegQIBhAN&uact=5&oq=apple&gs_lp=Egxnd3Mtd2l6LXNlcnAiBWFwcGxlMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMgoQABhHGNYEGLADMg0QABiABBiKBRhDGLADMg0QABiABBiKBRhDGLADMg0QABiABBiKBRhDGLADSLgBUABYAHABeAGQAQCYAQCgAQCqAQC4AQPIAQCYAgGgAgeYAwCIBgGQBgySBwExoAcAsgcAuAcAwgcDMi0xyAcFgAgB&sclient=gws-wiz-serp").foregroundStyle(.tertiary))"
								)
							}
					}
				}
				.lineLimit(1)
				.padding(.vertical, 4)
				.padding(style == .simple ? .horizontal : .leading, 6)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background {
					RoundedRectangle(cornerRadius: 9)
						.fill(Color.white.opacity(0.2))
						.strokeBorder(.white.opacity(0.3), lineWidth: 1)
				}
			}
		}
		.padding(6)
		.frame(maxWidth: .infinity, alignment: .top)
		.contentShape(RoundedRectangle(cornerRadius: 15))
		.overlay {
			RoundedRectangle(cornerRadius: 15)
				.fill(Color.primary.opacity(addressDisplayStyle == style ? 0.2 : 0.0))
				.strokeBorder(.white.opacity(addressDisplayStyle == style ? 0.6 : 0.3), lineWidth: 1)
		}
		.animation(.smooth(duration: 0.15), value: addressDisplayStyle == style)
		.onTapGesture {
			addressDisplayStyle = style
		}
	}
}
