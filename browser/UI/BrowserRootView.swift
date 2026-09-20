import SwiftUI

struct BrowserRootView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        #if os(macOS)
        DesktopBrowserShell()
        #elseif os(iOS)
        Group {
            if horizontalSizeClass == .compact {
                CompactBrowserShell()
            } else {
                DesktopBrowserShell()
            }
        }
        #else
        DesktopBrowserShell()
        #endif
    }
}

#Preview {
    BrowserRootView()
}
