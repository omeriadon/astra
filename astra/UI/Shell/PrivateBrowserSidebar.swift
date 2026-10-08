import SwiftUI

struct PrivateBrowserSidebar: View {
	let browser: Browser

	var body: some View {
		ScrollView {
			LazyVStack(spacing: 2) {
				Label("Private Browsing", systemImage: "eye.slash")
					.font(.headline)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.vertical, 12)
				ForEach(browser.tabs) { tab in
					PrivateBrowserTabRow(tab: tab, browser: browser)
				}
				Button("New Tab", systemImage: "plus") {
					browser.requestNewTab()
				}
				.buttonStyle(.plain)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(8)
				.accessibilityIdentifier("private-new-tab")
			}
			.padding(.horizontal, BrowserChromeMetrics.shellEdgePadding)
			.padding(.bottom, 48)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityIdentifier("private-sidebar")
	}
}

private struct PrivateBrowserTabRow: View {
	let tab: BrowserTab
	let browser: Browser

	var body: some View {
		HStack(spacing: 6) {
			Button {
				browser.selectTab(tab.id)
			} label: {
				Label(tab.title, systemImage: "globe")
					.lineLimit(1)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.buttonStyle(.plain)
			.accessibilityAddTraits(browser.selectedTabID == tab.id ? [.isSelected] : [])
			.accessibilityIdentifier("private-select-tab-\(tab.id)")
			Button("Close Tab", systemImage: "xmark") {
				browser.closeTab(tab.id)
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.plain)
			.accessibilityIdentifier("private-close-tab-\(tab.id)")
		}
		.padding(8)
		.background {
			if browser.selectedTabID == tab.id {
				Color.clear.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10))
			}
		}
	}
}
