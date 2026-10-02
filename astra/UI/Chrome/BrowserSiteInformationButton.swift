import SwiftUI
import WebKit

struct BrowserSiteInformationButton: View {
	let controller: BrowserController
	@State private var isPresented = false

	var body: some View {
		Button("Website Information", systemImage: controller.connectionSymbol) {
			isPresented.toggle()
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.glass)
		.accessibilityValue(controller.connectionDescription)
		.accessibilityIdentifier("website-information")
		.popover(isPresented: $isPresented) {
			BrowserSiteInformationView(controller: controller)
		}
	}
}

private struct BrowserSiteInformationView: View {
	let controller: BrowserController

	var body: some View {
		List {
			Section("Connection") {
				Label(controller.connectionDescription, systemImage: controller.connectionSymbol)
				if let url = controller.committedURL,
				   let origin = BrowserSitePermissions.origin(for: url)
				{
					Text(verbatim: origin)
						.textSelection(.enabled)
				}
				if controller.session.isPrivate {
					Label("Private Browsing", systemImage: "eye.slash")
				}
			}
			if let url = controller.committedURL,
			   let origin = BrowserSitePermissions.origin(for: url)
			{
				BrowserSitePreferenceControls(controller: controller, origin: origin)
			}
			Section("Website Permissions") {
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
	}
}

private struct BrowserSitePreferenceControls: View {
	let controller: BrowserController
	let origin: String
	@State private var customUserAgent = ""

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

	private var pageZoom: Binding<Double> {
		Binding {
			controller.pageZoom
		} set: { zoom in
			controller.pageZoom = zoom
		}
	}

	var body: some View {
		Section("Site Preferences") {
			Text("Zoom is saved and synced for this origin. Desktop/mobile mode and custom user agent stay on this device and apply at the next navigation.")
				.font(.caption)
				.foregroundStyle(.secondary)
			if preferences.isZoomDataReadOnly || preferences.isLocalDataReadOnly {
				Text("Astra preserved saved preferences it cannot read and disabled changes to those preference types.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			HStack {
				Text("Page Zoom")
				Spacer()
				Text(controller.pageZoom, format: .percent.precision(.fractionLength(0)))
					.monospacedDigit()
			}
			Slider(value: pageZoom, in: BrowserZoomPolicy.range, step: 0.05)
				.accessibilityLabel("Page zoom for \(origin)")
				.accessibilityIdentifier("site-page-zoom-\(origin)")
				.disabled(preferences.isZoomDataReadOnly)
			Picker("Content Mode", selection: contentModeSelection) {
				ForEach(BrowserSiteContentMode.allCases) { mode in
					Text(mode.title).tag(mode)
				}
			}
			.disabled(preferences.isLocalDataReadOnly)
			.accessibilityIdentifier("site-content-mode-\(origin)")
			TextField("Custom User Agent", text: $customUserAgent)
				.textFieldStyle(.roundedBorder)
				.disabled(preferences.isLocalDataReadOnly)
				.accessibilityIdentifier("site-custom-user-agent-\(origin)")
			Button("Save Custom User Agent", systemImage: "checkmark") {
				preferences.setCustomUserAgent(customUserAgent, for: origin)
			}
			.disabled(preferences.isLocalDataReadOnly)
			.accessibilityIdentifier("save-site-user-agent-\(origin)")
			Text("Leave blank to use Astra's default and its existing Chrome Web Store compatibility behavior. Playback remains click-to-play for every site because WebKit exposes that choice per web view.")
				.font(.caption)
				.foregroundStyle(.secondary)
			Button("Reset Site Preferences", systemImage: "arrow.counterclockwise") {
				preferences.resetZoom(for: origin)
				preferences.resetLocalPreferences(for: origin)
				customUserAgent = ""
			}
			.disabled(!preferences.hasPreferences(for: origin) || (preferences.isZoomDataReadOnly && preferences.isLocalDataReadOnly))
			.accessibilityIdentifier("reset-site-preferences-\(origin)")
		}
		.task(id: origin) {
			customUserAgent = preferences.customUserAgent(for: origin) ?? ""
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
