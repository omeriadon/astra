import AuthenticationServices
import Defaults
import SwiftUI

struct BrowserAccountSettingsView: View {
	@State private var sync = BrowserSync.shared
	@Default(.syncServerURL) private var syncServerURL

	var body: some View {
		List {
			Section("Account & Sync") {
				TextField("Sync Server URL", text: $syncServerURL)
					.textContentType(.URL)
					.autocorrectionDisabled()
					.disabled(sync.isSignedIn)
					.accessibilityIdentifier("sync-server-url")

				if sync.isSignedIn {
					Label("Signed in with Apple", systemImage: "person.crop.circle.badge.checkmark")
						.accessibilityIdentifier("apple-account-status")

					Button(role: .destructive) {
						sync.signOut()
					} label: {
						Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
					}
					.accessibilityIdentifier("sign-out")
				} else {
					SignInWithAppleButton(.signIn) { _ in
					} onCompletion: { result in
						Task { await sync.signIn(result: result) }
					}
					.frame(height: 44)
					.accessibilityLabel("Sign in with Apple")
					.accessibilityIdentifier("sign-in-with-apple")
				}

				#if DEBUG
					Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
						Task { await sync.syncNow() }
					}
					.disabled(!sync.isSignedIn || sync.isSyncing)
					.accessibilityIdentifier("debug-sync-now")
				#endif

				if sync.isSyncing {
					ProgressView("Syncing")
				} else if let lastSync = sync.lastSync {
					LabeledContent("Last Sync") {
						Text(lastSync, style: .relative)
					}
				}

				if let error = sync.errorDescription {
					Text(error)
						.foregroundStyle(.red)
						.accessibilityIdentifier("sync-error")
				}
			}
		}
		.scrollContentBackground(.hidden)
	}
}
