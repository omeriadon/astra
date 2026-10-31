import AuthenticationServices
import Defaults
import SwiftUI

struct BrowserAccountSettingsView: View {
	@State private var sync = BrowserSync.shared
	@Default(.syncServerURL) private var syncServerURL

	var body: some View {
		List {
			Section("Account & Sync") {
				Text("Tabs, bookmarks, browsing history, spaces, and portable browser settings are sent to your sync server over HTTPS. Private windows, local files, sync credentials, and device settings are excluded. Sync data is not end-to-end encrypted.")
					.font(.caption)
					.foregroundStyle(.secondary)
				TextField("Sync Server URL", text: $syncServerURL)
					.textContentType(.URL)
					.autocorrectionDisabled()
					.disabled(sync.isSignedIn)
					.accessibilityIdentifier("sync-server-url")
					.id("Sync Server URL")

				if sync.isSignedIn {
					Label("Signed in with Apple", systemImage: "person.crop.circle.badge.checkmark")
						.accessibilityIdentifier("apple-account-status")
						.id("Signed in with Apple")

					Button(role: .destructive) {
						sync.signOut()
					} label: {
						Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
					}
					.accessibilityIdentifier("sign-out")
					.id("Sign Out")
				} else {
					SignInWithAppleButton(.signIn) { _ in
					} onCompletion: { result in
						Task { await sync.signIn(result: result) }
					}
					.frame(height: 44)
					.accessibilityLabel("Sign in with Apple")
					.accessibilityIdentifier("sign-in-with-apple")
					.id("Sign in with Apple")
				}

				Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
					Task { await sync.syncNow() }
				}
				.disabled(!sync.canSync || sync.isSyncing)
				.accessibilityIdentifier("sync-now")
				.accessibilityHint("Pull and merge changes from your other devices and send pending changes")
				.id("Sync Now")

				if sync.hasPendingChanges {
					Label("Changes pending sync", systemImage: "clock")
						.font(.caption)
						.foregroundStyle(.secondary)
						.accessibilityIdentifier("sync-pending")
				}

				if sync.isSyncing {
					ProgressView("Syncing")
				} else if let lastSync = sync.lastSync {
					LabeledContent("Last Synced") {
						Text(lastSync.formatted(date: .abbreviated, time: .shortened))
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
		.listStyle(.sidebar)
	}
}
