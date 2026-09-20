import SwiftUI

struct BrowserSplitView<Sidebar: View, Content: View>: View {
    let sidebarWidth: CGFloat
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let content: Content

    init(
        sidebarWidth: CGFloat = 224,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content
    ) {
        self.sidebarWidth = sidebarWidth
        self.sidebar = sidebar()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
