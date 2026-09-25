import SwiftUI

struct BrowserToastView: View {
	let toast: BrowserToast

	var body: some View {
		Label(toast.message, systemImage: toast.symbol)
			.lineLimit(1)
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(.regularMaterial, in: Capsule())
			.shadow(color: .black.opacity(0.2), radius: 12, y: 5)
			.accessibilityElement(children: .combine)
			.accessibilityLabel(Text(toast.message))
	}
}
