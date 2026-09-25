#if DEBUG
	import SwiftUI

	struct BrowserFailedWebsiteStatesSettingsView: View {
		let browser: Browser

		var body: some View {
			List {
				Section("Error Pages") {
					ForEach(BrowserNavigationFailure.Kind.allCases, id: \.self) { kind in
						Button {
							browser.openFailedWebsiteState(kind)
						} label: {
							Label {
								Text(kind.title)
							} icon: {
								Image(systemName: kind.systemImage)
							}
						}
						.accessibilityIdentifier("debug-error-\(String(describing: kind))")
					}
				}
			}
			.scrollContentBackground(.hidden)
			.listStyle(.sidebar)
		}
	}
#endif
