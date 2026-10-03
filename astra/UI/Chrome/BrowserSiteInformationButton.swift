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
		.frame(width: 340, height: 340)
		.accessibilityIdentifier("website-information-panel")
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
