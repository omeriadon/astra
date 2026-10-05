import SwiftUI

struct BrowserSearchResultIcon: View {
	let result: BrowserSearchResult

	var body: some View {
		if result.isGitHubRepository {
			Image("GitHubFavicon")
				.renderingMode(.template)
				.resizable()
				.scaledToFit()
				.accessibilityHidden(true)
		} else {
			Image(systemName: result.symbol)
				.accessibilityHidden(true)
		}
	}
}
