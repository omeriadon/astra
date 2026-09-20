import SwiftUI

struct DesktopBrowserShell: View {
    var body: some View {
        BrowserSplitView {
            VStack(spacing: 18) {
                ForEach(0..<4) { _ in
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.gray.opacity(0.35))
                        .frame(height: 48)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .padding(.top, 42)
            .frame(maxHeight: .infinity)
            .background(.tint.opacity(0.9))
        } content: {
            RoundedRectangle(cornerRadius: 28)
                .fill(.background)
                .padding(12)
        }
        .background(.tint.opacity(0.9))
    }
}

#Preview {
    DesktopBrowserShell()
}
