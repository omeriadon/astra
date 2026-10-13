import SwiftUI

struct BrowserEaselSplitView: View {
	let browser: Browser
	let leftTab: BrowserTab
	let rightTab: BrowserTab
	let cornerRadius: CGFloat
	@State private var fraction: CGFloat = 0.5
	@State private var startFraction: CGFloat?

	var body: some View {
		GeometryReader { geometry in
			let usableWidth = max(0, geometry.size.width - 8)
			let minimum = min(300, usableWidth / 2)
			let leftWidth = min(max(minimum, usableWidth * fraction), usableWidth - minimum)
			HStack(spacing: 0) {
				BrowserPageView(browser: browser, cornerRadius: cornerRadius, tabID: leftTab.id, showsPeeks: leftTab.internalPage != .easel)
					.frame(width: leftWidth)
					.simultaneousGesture(TapGesture().onEnded { browser.selectTab(leftTab.id) })
				Rectangle()
					.fill(.primary.opacity(0.15))
					.frame(width: 1)
					.frame(width: 8)
					.contentShape(Rectangle())
					.gesture(DragGesture(coordinateSpace: .global).onChanged { value in
						if startFraction == nil {
							startFraction = fraction
						}
						guard usableWidth > 0 else { return }
						fraction = min(max((startFraction ?? 0.5) + value.translation.width / usableWidth, minimum / usableWidth), 1 - minimum / usableWidth)
					}.onEnded { _ in startFraction = nil })
					.accessibilityLabel("Split width")
					.accessibilityValue("\(Int(fraction * 100)) percent")
					.accessibilityIdentifier("browser-tab-split-resizer")
					.accessibilityAdjustableAction { direction in
						fraction = min(max(fraction + (direction == .increment ? 0.05 : -0.05), 0.25), 0.75)
					}
				VStack(spacing: 0) {
					HStack {
						Text(rightTab.title).font(.headline).lineLimit(1)
						Spacer(minLength: 0)
						Button("Open Tab Alone", systemImage: "arrow.up.left.and.arrow.down.right") {
							browser.closeEaselSplit()
							browser.selectTab(rightTab.id)
						}
						.labelStyle(.iconOnly)
						.accessibilityIdentifier("split-open-alone")
						Button("Close Split", systemImage: "xmark") {
							browser.closeEaselSplit()
							browser.selectTab(leftTab.id)
						}
						.labelStyle(.iconOnly)
						.accessibilityIdentifier("split-close")
					}
					.padding(8)
					if rightTab.internalPage == .easel {
						BrowserEaselView(browser: browser, tab: rightTab)
							.id(rightTab.id)
					} else {
						BrowserPageView(browser: browser, cornerRadius: cornerRadius, tabID: rightTab.id)
					}
				}
				.frame(width: usableWidth - leftWidth)
				.background(browser.theme.contentShade(for: colorScheme))
				.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
			}
			.overlay {
				if !rightTab.peeks.isEmpty {
					PeekStackView(tab: rightTab, browser: browser)
				} else if leftTab.internalPage == .easel, !leftTab.peeks.isEmpty {
					PeekStackView(tab: leftTab, browser: browser)
				}
			}
		}
		.accessibilityIdentifier("browser-tab-split-view")
	}

	@Environment(\.colorScheme) private var colorScheme
}
