import SwiftUI

struct BrowserSplitView<Sidebar: View, Content: View>: View {
	let sidebarWidth: CGFloat

	@Binding var sidebarShown: Bool
	@Binding var isAboutToQuit: Bool

	@ViewBuilder let sidebar: Sidebar
	@ViewBuilder let content: Content

	init(
		sidebarShown: Binding<Bool>,
		isAboutToQuit: Binding<Bool>,
		sidebarWidth: CGFloat = 224,
		@ViewBuilder sidebar: () -> Sidebar,
		@ViewBuilder content: () -> Content
	) {
		_sidebarShown = sidebarShown
		_isAboutToQuit = isAboutToQuit
		self.sidebarWidth = sidebarWidth
		self.sidebar = sidebar()
		self.content = content()
	}

	@State private var quitExpiry: Date = .distantPast

	var body: some View {
		HStack(spacing: 0) {
			ZStack(alignment: .leading) {
				sidebar
					.frame(width: sidebarWidth)
					.offset(x: sidebarShown ? 0 : sidebarWidth)
			}
			.frame(width: sidebarShown ? sidebarWidth : 0, alignment: .trailing)
			.clipped()

			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.blur(radius: Date.now < quitExpiry ? 5 : 0)
		.animation(.snappy(duration: 0.2), value: Date.now < quitExpiry)
		.animation(.smooth(duration: 0.3), value: sidebarShown)
		.overlay(alignment: .center) {
			TimelineView(.animation) { timeline in
				let showQuitMessage = timeline.date < quitExpiry

				GlassEffectContainer {
					if showQuitMessage {
						ZStack {
							Rectangle()
								.fill(Color.black.gradient)
								.opacity(0.2)

							Label {
								Text("Press \(Image(systemName: "command"))Q again to quit")
							} icon: {
								Image(systemName: "rectangle.portrait.and.arrow.right")
							}
							.monospaced()
							.font(.title2)
							.padding(.horizontal, 20)
							.padding(.vertical, 16)
							.glassEffect(
								.regular,
								in: RoundedRectangle(cornerRadius: 20)
							)
							.glassEffectTransition(.materialize)
						}
					}
				}
				.animation(.snappy(duration: 0.2), value: showQuitMessage)
			}
		}
		.onChange(of: isAboutToQuit) { _, newValue in
			if newValue {
				quitExpiry = .now.addingTimeInterval(1)
			}
		}
		.task(id: quitExpiry) {
			guard quitExpiry > .now else { return }

			try? await Task.sleep(until: .now + .seconds(quitExpiry.timeIntervalSinceNow))

			guard Date.now >= quitExpiry else { return }
			isAboutToQuit = false
		}
	}
}
