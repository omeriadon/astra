//
//  AboutView.swift
//  astra
//
//  Created by Adon Omeri on 26/9/2026.
//

import SwiftUI

extension Bundle {
	var releaseVersionNumber: String? {
		infoDictionary?["CFBundleShortVersionString"] as? String
	}

	var buildNumber: String? {
		infoDictionary?["CFBundleVersion"] as? String
	}
}

struct AboutView: View {
	#if os(macOS)
		@Bindable private var updates = UpdateManager.shared
	#endif
	@State private var pointerLocation: CGPoint?

	var body: some View {
		ZStack {
			BrowserUpdateArtwork(isAboutView: true, pointerLocation: pointerLocation)

			HStack {
				Spacer()
				VStack(spacing: 30) {
					Spacer()

					Image("astra", bundle: BrowserResources.bundle)
						.resizable()
						.aspectRatio(contentMode: .fit)
						.frame(width: 200)
						.accessibilityHidden(true)

					Text("astra")
						.font(.largeTitle)
						.accessibilityAddTraits(.isHeader)

					if let version = Bundle.main.releaseVersionNumber,
					   let build = Bundle.main.buildNumber
					{
						Text("\(version) \(Text("(\(build))").foregroundStyle(.secondary))")
							.accessibilityLabel("Version \(version), build \(build)")
					}

					#if os(macOS)
						CheckForUpdatesView(updates: updates)
					#endif

					Spacer()
				}
				Spacer()
			}
		}
		.contentShape(Rectangle())
		#if os(macOS)
			.onContinuousHover { phase in
				switch phase {
					case let .active(location):
						pointerLocation = location
					case .ended:
						pointerLocation = nil
				}
			}
		#endif
	}
}

#Preview {
	AboutView()
}
