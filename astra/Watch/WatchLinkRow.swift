import SwiftUI

struct WatchLinkRow: View {
	let link: WatchLink
	let symbol: String
	let browser: WatchBrowser

	private var title: String {
		link.title.isEmpty ? (link.url.host ?? "Website") : link.title
	}

	var body: some View {
		Button {
			browser.open(link)
		} label: {
			Label(title, systemImage: symbol)
				.lineLimit(2)
		}
		.disabled(!link.canOpen)
		.accessibilityLabel(title)
		.accessibilityHint("Opens \(link.url.host ?? "website") in the system browser")
		.accessibilityIdentifier("watch.link.\(link.id)")
		.listRowBackground(Color.black.opacity(0.2))
	}
}
