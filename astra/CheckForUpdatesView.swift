//
//  CheckForUpdatesView.swift
//  astra
//
//  Created by Adon Omeri on 25/9/2026.
//

import Combine
import Sparkle
import SwiftUI

final class CheckForUpdatesViewModel: ObservableObject {
	@Published var canCheckForUpdates = false

	init(updater: SPUUpdater) {
		updater.publisher(for: \.canCheckForUpdates)
			.assign(to: &$canCheckForUpdates)
	}
}

struct CheckForUpdatesView: View {
	@ObservedObject private var viewModel: CheckForUpdatesViewModel

	private let updater: SPUUpdater

	init(updater: SPUUpdater) {
		self.updater = updater
		viewModel = CheckForUpdatesViewModel(updater: updater)
	}

	var body: some View {
		Button("Check for Updates…") {
			updater.checkForUpdates()
		}
		.disabled(!viewModel.canCheckForUpdates)
	}
}
