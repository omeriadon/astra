import SwiftUI

struct CompactBrowserShell: View {
	var body: some View {
		VStack(spacing: 0) {
			RoundedRectangle(cornerRadius: 28)
				.fill(.background)
				.padding(10)
				.frame(maxWidth: .infinity, maxHeight: .infinity)

			HStack(spacing: 16) {
				Capsule()
					.fill(.gray.opacity(0.35))
					.frame(width: 40, height: 40)

				Capsule()
					.fill(.gray.opacity(0.35))
					.frame(maxWidth: .infinity)
					.frame(height: 40)

				Capsule()
					.fill(.gray.opacity(0.35))
					.frame(width: 40, height: 40)
			}
			.padding(.horizontal, 24)
			.padding(.vertical, 12)
			.background(.tint.opacity(0.9))
		}
		.background(.tint.opacity(0.9))
	}
}

#Preview {
	CompactBrowserShell()
}
