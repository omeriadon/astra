#if DEBUG
	import Defaults
	import SwiftUI

	struct BrowserDebugView: View {
		@State private var path: [BrowserNavigationFailure.Kind] = []
		@Default(.browserTheme) private var theme
		@Environment(\.colorScheme) private var colorScheme

		var body: some View {
			NavigationStack(path: $path) {
				List {
					Section("Error Pages") {
						ForEach(BrowserNavigationFailure.Kind.allCases, id: \.self) { kind in
							NavigationLink(value: kind) {
								Label {
									Text(kind.title)
								} icon: {
									Image(systemName: kind.systemImage)
								}
							}
							.accessibilityLabel(Text(kind.title))
							.accessibilityIdentifier("debug-error-\(String(describing: kind))")
						}
					}
				}
				.scrollContentBackground(.hidden)
				.navigationTitle("Debug Stuff")
				.navigationDestination(for: BrowserNavigationFailure.Kind.self) { kind in
					BrowserNavigationErrorView(kind: kind) {
						path.removeLast()
					}
					.navigationTitle("Error Preview")
				}
			}
			.background(theme.contentShade(for: colorScheme).gradient)
			.frame(minWidth: 360, minHeight: 180)
		}
	}
#endif
