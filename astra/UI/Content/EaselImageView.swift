import SwiftUI
#if os(macOS)
	import AppKit
#else
	import UIKit
#endif

struct EaselImageView: View {
	let data: Data
	@State private var image: Image?

	var body: some View {
		Group {
			if let image {
				image.resizable().scaledToFit()
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
