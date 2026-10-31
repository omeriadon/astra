import SwiftUI
#if os(macOS)
	import AppKit
#else
	import UIKit
#endif

struct EaselImageView: View {
	let data: Data
	var roundedCorners = false
	@State private var image: Image?

	var body: some View {
		Group {
			if let image {
				image.resizable().scaledToFit()
					.clipShape(EaselImageMask(isRounded: roundedCorners))
			} else {
				Image(systemName: "photo")
			}
		}
		.onChange(of: data, initial: true) { _, data in
			#if os(macOS)
				image = NSImage(data: data).map { Image(nsImage: $0) }
			#else
				image = UIImage(data: data).map { Image(uiImage: $0) }
			#endif
		}
		.accessibilityLabel("Easel image")
		.accessibilityIdentifier("easel-image")
	}
}

/// Shared by image rendering and the parent Easel item's pointer hit region so
/// transparent corner pixels do not intercept pointer selection.
nonisolated struct EaselImageMask: Shape {
	var isRounded: Bool

	func path(in rect: CGRect) -> Path {
		if isRounded {
			RoundedRectangle(cornerRadius: min(12, min(rect.width, rect.height) / 4), style: .continuous).path(in: rect)
		} else {
			Rectangle().path(in: rect)
		}
	}
}
