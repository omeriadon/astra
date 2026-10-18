import SwiftUI

struct PrivateBrowserSidebar: View {
	let browser: Browser
	var topMargin: CGFloat = 0

	var body: some View {
		let tabs = browser.tabs
		let items = [BrowserSidebarItem(id: "private-header", kind: .privateHeader, height: 48)]
			+ tabs.map { BrowserSidebarItem(id: $0.id.uuidString, height: 34, tabID: $0.id) }
			+ [BrowserSidebarItem(id: "private-new-tab", kind: .newTab, height: 34)]
		BrowserSidebarScrollView(items: items, revision: browser.selectedTabID, top: topMargin) { item in
			switch item.kind {
				case .privateHeader:
					Label("Private Browsing", systemImage: "eye.slash")
						.font(.headline)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.vertical, 12)
				case .tab:
					if let tab = item.tabID.flatMap({ browser.tabsByID[$0] }) {
						PrivateBrowserTabRow(tab: tab, browser: browser)
					}
				case .newTab:
					Button("New Tab", systemImage: "plus") { browser.requestNewTab() }
						.buttonStyle(.plain)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(8)
						.accessibilityIdentifier("private-new-tab")
				default:
					EmptyView()
			}
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
