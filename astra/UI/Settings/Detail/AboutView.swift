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
	@Bindable private var updates = UpdateManager.shared

	var body: some View {
		HStack {
			Spacer()
			VStack(spacing: 30) {
				Spacer()

				Image("astra")
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 200)

				Text("astra")
					.font(.largeTitle)

				if let version = Bundle.main.releaseVersionNumber,
				   let build = Bundle.main.buildNumber
				{
					Text("\(version) \(Text("(\(build))").foregroundStyle(.secondary))")
				}

				CheckForUpdatesView(updater: updates.updater)

				Spacer()
			}
			Spacer()
		}
	}
}

#Preview {
	AboutView()
}
