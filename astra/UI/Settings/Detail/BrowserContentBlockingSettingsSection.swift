import SwiftUI
import UniformTypeIdentifiers

struct BrowserContentBlockingSettingsSection: View {
	let session: BrowserWebSession
	@State private var contentBlocking: BrowserContentBlocking
	@State private var extensions = BrowserExtensionManager.shared
	@State private var showsImporter = false
	@State private var confirmsRemoval = false

	private var enabledBinding: Binding<Bool> {
		Binding(
			get: { contentBlocking.isEnabled },
			set: { contentBlocking.setEnabled($0) }
		)
	}

	init(session: BrowserWebSession) {
		self.session = session
		_contentBlocking = State(initialValue: session.contentBlocking)
	}

	var body: some View {
		Section("Content Blocking") {
			if let source = contentBlocking.source {
				Toggle("Enable Imported Native Rules", isOn: enabledBinding)
					.disabled(contentBlocking.isBusy || contentBlocking.isReadOnly || contentBlocking.compiledRuleList == nil)
					.accessibilityIdentifier("native-content-blocking-enabled")
				LabeledContent("Imported List", value: contentBlocking.sourceFileName ?? "JSON rule list")
				LabeledContent("Revision", value: String(source.identifier.suffix(12)))
				LabeledContent("Rules in List", value: "\(source.ruleCount)")
				LabeledContent("Status", value: statusTitle)
				if let updatedAt = contentBlocking.updatedAt {
					LabeledContent("Imported") {
						Text(updatedAt, format: .dateTime.year().month().day().hour().minute())
					}
				}
			}

			Button(
				contentBlocking.source == nil ? "Import JSON Rule List" : "Update Imported Rules",
				systemImage: "doc.badge.plus"
			) {
				showsImporter = true
			}
			.disabled(contentBlocking.isBusy || contentBlocking.isReadOnly)
			.accessibilityIdentifier("import-native-content-rule-list")

			if contentBlocking.source != nil {
				Button("Reload Saved Rules", systemImage: "arrow.clockwise") {
					Task { await contentBlocking.refresh() }
				}
				.disabled(contentBlocking.isBusy || contentBlocking.compiledRuleList != nil)
				.accessibilityIdentifier("reload-native-content-rules")

				Button("Remove Imported Rules", systemImage: "trash", role: .destructive) {
					confirmsRemoval = true
				}
				.disabled(contentBlocking.isBusy || contentBlocking.isReadOnly)
				.accessibilityIdentifier("remove-native-content-rules")
			}

			if let error = contentBlocking.errorDescription {
				Text(error)
					.foregroundStyle(.red)
					.accessibilityIdentifier("native-content-blocking-error")
			}

			Text(session.isPrivate
				? "Private rules are off until you import a list. The source stays in this window’s memory. WebKit writes compiled rules to a session-owned temporary directory; Astra removes that directory when the window closes. A crash may leave temporary compiled data behind."
				: "Astra bundles uBlock Origin Lite as an independent extension blocker. Imported native rules are a separate opt-in and may run alongside it. Reimport an updated JSON file to refresh the native list. Rule changes apply to future requests; Astra does not reload pages automatically. Blocked-request counts and filter conflicts are unavailable.")
				.font(.caption)
				.foregroundStyle(.secondary)

			if session.isPrivate {
				LabeledContent("uBlock Origin Lite", value: "Unavailable in Private Browsing")
			} else {
				LabeledContent("uBlock Origin Lite", value: extensionStatus)
				if contentBlocking.isActive && extensions.isLoaded("ublock-origin-lite-safari") {
					Text("Both the native list and uBlock Origin Lite can apply to this page.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
			guard case let .success(url) = result else { return }
			Task { await contentBlocking.importRules(from: url) }
		}
		.confirmationDialog("Remove the imported native rule list?", isPresented: $confirmsRemoval) {
			Button("Remove Imported Rules", systemImage: "trash", role: .confirm) {
				Task { await contentBlocking.removeRules() }
			}
			.buttonStyle(.glassProminent)
			Button(role: .cancel) {}
		} message: {
			Text("This removes Astra’s imported source and compiled list. uBlock Origin Lite settings are unchanged.")
		}
		.task {
			await contentBlocking.prepare()
		}
	}

	private var statusTitle: String {
		if contentBlocking.isBusy { "Compiling" }
		else if contentBlocking.isEnabled && contentBlocking.compiledRuleList != nil { "Enabled" }
		else if contentBlocking.compiledRuleList == nil { "Unavailable" }
		else { "Disabled" }
	}

	private var extensionStatus: String {
		guard extensions.isEnabled("ublock-origin-lite-safari") else { return "Disabled" }
		return extensions.isLoaded("ublock-origin-lite-safari") ? "Enabled" : "Enabled, not loaded"
	}
}
