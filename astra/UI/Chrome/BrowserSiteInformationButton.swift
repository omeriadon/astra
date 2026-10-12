import Defaults
import SwiftUI
import WebKit

struct BrowserSiteInformationButton: View {
	let controller: BrowserController
	@State private var isPresented = false

	var body: some View {
		Button {
			isPresented.toggle()
		} label: {
			AstraTopBarIcon(title: "Website Information", systemImage: controller.connectionSymbol)
		}
		.astraTopBarButton()
		.accessibilityValue(controller.connectionDescription)
		.accessibilityIdentifier("website-information")
		.popover(isPresented: $isPresented) {
			BrowserSiteInformationView(controller: controller)
		}
	}
}

private struct BrowserSiteInformationView: View {
	let controller: BrowserController
	@Default(.developerModeEnabled) private var developerModeEnabled
	@State private var showsCertificate = false

	var body: some View {
		List {
			if let url = controller.committedURL,
			   let origin = BrowserSitePermissions.origin(for: url),
			   let agent = controller.session.sitePreferences.customUserAgent(for: origin),
			   !agent.isEmpty
			{
				Section {
					LabeledContent("User Agent", value: "Custom")
						.help("A custom user agent is active for this website. Edit it from View > Custom User Agent.")
						.accessibilityIdentifier("site-custom-user-agent-status")
				}
			}
			Section("Connection") {
				Label(controller.connectionDescription, systemImage: controller.connectionSymbol)
					.accessibilityIdentifier("committed-page-security-state")
				if let committedURL = controller.committedURL {
					LabeledContent("Website", value: committedURL.host ?? (committedURL.isFileURL ? "Local File" : "Unknown"))
						.accessibilityIdentifier("committed-page-origin")
				}
				if let failure = controller.navigationFailure {
					Label("Navigation failed: \(failure.kind.title)", systemImage: failure.kind.systemImage)
						.accessibilityIdentifier("failed-navigation-state")
					if let origin = controller.securityPresentation.failedOrigin {
						Text("Failed destination: \(origin)")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				if controller.session.isPrivate {
					Label("Private Browsing", systemImage: "eye.slash")
				}
				if controller.securityPresentation.certificate != nil {
					Button("View Website Certificate…", systemImage: "checkmark.shield") {
						showsCertificate = true
					}
					.accessibilityIdentifier("view-site-certificate")
				}
			}
			if let url = controller.committedURL,
			   let origin = BrowserSitePermissions.origin(for: url)
			{
				BrowserSitePreferenceControls(controller: controller, origin: origin)
				Section("Content Blocking") {
					BrowserAdBlockingButton(controller: controller)
				}
			}
			Section("Developer Mode") {
				Button(
					developerModeEnabled ? "Disable Developer Mode" : "Enable Developer Mode",
					systemImage: developerModeEnabled ? "hammer.fill" : "hammer"
				) {
					developerModeEnabled.toggle()
				}
				.accessibilityLabel(developerModeEnabled ? "Disable Developer Mode" : "Enable Developer Mode")
				.accessibilityValue(developerModeEnabled ? "On" : "Off")
				.accessibilityIdentifier("website-developer-mode-toggle")
				Text("Applies to all websites. Localhost enters developer mode automatically.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Section("Active Access for Committed Page") {
				LabeledContent(
					"Camera",
					value: BrowserActiveCaptureStatus.current(
						isActive: controller.cameraCaptureState == .active,
						isMuted: controller.cameraCaptureState == .muted,
						sampledDocumentID: controller.mediaCaptureStateDocumentID,
						committedDocumentID: controller.committedSecurityNavigationID
					).title
				)
				.accessibilityIdentifier("active-camera-state")
				LabeledContent(
					"Microphone",
					value: BrowserActiveCaptureStatus.current(
						isActive: controller.microphoneCaptureState == .active,
						isMuted: controller.microphoneCaptureState == .muted,
						sampledDocumentID: controller.mediaCaptureStateDocumentID,
						committedDocumentID: controller.committedSecurityNavigationID
					).title
				)
				.accessibilityIdentifier("active-microphone-state")
				LabeledContent("Location", value: "Activity unavailable")
					.accessibilityIdentifier("active-location-state")
				LabeledContent("Display Sharing", value: "Activity unavailable")
					.accessibilityIdentifier("active-display-capture-state")
			}
			Section("Saved Website Permissions") {
				if controller.session.permissions.isSavedDataReadOnly {
					Text("Reset website permissions in Privacy and Security before saving changes.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				if let url = controller.committedURL,
				   let origin = BrowserSitePermissions.origin(for: url)
				{
					ForEach(BrowserSitePermissions.websiteCapabilities, id: \.self) { capability in
						BrowserSitePermissionPicker(
							permissions: controller.session.permissions,
							origin: origin,
							topOrigin: origin,
							capability: capability,
							controllerID: controller.id,
							documentID: controller.navigationIdentifier
						)
					}
					Text(controller.session.isPrivate
						? "Permission choices last only for this private window. Allow Once lasts for this page."
						: "Always Allow is stored on this device. Allow Once lasts for this page. Deny blocks this site until changed. Closing or canceling a prompt does not save a block.")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text("Audio and video require a click to play on every site.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
		.frame(width: 360, height: 520)
		.accessibilityIdentifier("website-information-panel")
		.sheet(isPresented: $showsCertificate) {
			NavigationStack {
				Form {
					if let certificate = controller.securityPresentation.certificate {
						Section("Certificate") {
							LabeledContent("Subject") {
								Text(verbatim: certificate.subject)
									.textSelection(.enabled)
							}
							if let start = certificate.notValidBefore {
								LabeledContent("Valid From") {
									Text(start, format: .dateTime.year().month().day())
								}
							}
							if let end = certificate.notValidAfter {
								LabeledContent("Valid Through") {
									Text(end, format: .dateTime.year().month().day())
								}
							}
						}
						Text("Certificate information reported by WebKit for the committed page.")
							.foregroundStyle(.secondary)
							.font(.caption)
					}
				}
				.formStyle(.grouped)
				.navigationTitle("Website Certificate")
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						Button("Done") { showsCertificate = false }
					}
				}
			}
			.frame(width: 430, height: 300)
		}
	}
}

private struct BrowserSitePreferenceControls: View {
	let controller: BrowserController
	let origin: String

	private var preferences: BrowserSitePreferences {
		controller.session.sitePreferences
	}

	private var contentModeSelection: Binding<BrowserSiteContentMode> {
		Binding {
			preferences.contentMode(for: origin) ?? .recommended
		} set: { mode in
			preferences.setContentMode(mode, for: origin)
		}
	}

	var body: some View {
		Section("Site Preferences") {
			Picker("Content Mode", selection: contentModeSelection) {
				ForEach(BrowserSiteContentMode.allCases) { mode in
					Text(mode.title).tag(mode)
				}
			}
			.disabled(preferences.isLocalDataReadOnly)
			.accessibilityIdentifier("site-content-mode-\(origin)")
			Button("Reset Site Preferences", systemImage: "arrow.counterclockwise") {
				preferences.resetZoom(for: origin)
				preferences.resetLocalPreferences(for: origin)
			}
			.disabled(!preferences.hasPreferences(for: origin) || (preferences.isZoomDataReadOnly && preferences.isLocalDataReadOnly))
			.accessibilityIdentifier("reset-site-preferences-\(origin)")
		}
	}
}

struct BrowserSitePermissionPicker: View {
	let permissions: BrowserSitePermissions
	let origin: String
	let topOrigin: String
	let capability: BrowserSitePermissions.Capability
	var controllerID: UUID?
	var documentID: Int?

	private var selection: Binding<String> {
		Binding {
			switch permissions.effectiveDecision(
				origin: origin,
				topOrigin: topOrigin,
				capability: capability,
				controllerID: controllerID,
				documentID: documentID
			) {
				case .allowOnce: "once"
				case .allowAlways: "allow"
				case .deny: "block"
				case nil: "ask"
			}
		} set: { value in
			if value == "once", let controllerID, let documentID {
				permissions.set(.allowOnce, origin: origin, topOrigin: topOrigin, capability: capability, controllerID: controllerID, documentID: documentID)
			} else if value == "ask" {
				let entry = BrowserSitePermissions.Entry(
					origin: origin,
					topOrigin: topOrigin,
					capability: capability,
					decision: .allowAlways
				)
				permissions.remove(entry)
			} else {
				permissions.set(value == "allow" ? .allowAlways : .deny, origin: origin, topOrigin: topOrigin, capability: capability)
			}
		}
	}

	var body: some View {
		Picker(capability.title, selection: selection) {
			Label("Ask", systemImage: "questionmark.circle").tag("ask")
			if controllerID != nil, documentID != nil {
				Label("Allow Once", systemImage: "checkmark.circle").tag("once")
			}
			Label("Always Allow", systemImage: "checkmark.circle").tag("allow")
			Label("Block", systemImage: "hand.raised").tag("block")
		}
		.accessibilityIdentifier("site-permission-\(capability.rawValue)-\(origin)")
	}
}
