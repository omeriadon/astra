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
				if let url = controller.committedURL,
				   let origin = BrowserSitePermissions.origin(for: url)
				{
					ForEach(BrowserSitePermissions.Capability.allCases, id: \.self) { capability in
						BrowserSitePermissionPicker(
							permissions: controller.session.permissions,
							origin: origin,
							topOrigin: origin,
							capability: capability,
							onChange: { controller.stopCapture(capability: capability) }
						)
					}
					Text("Changes apply to new requests. Existing camera and microphone capture stops when access is changed.")
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
	var onChange: () -> Void = {}

	private var selection: Binding<String> {
		Binding {
			switch permissions.decision(origin: origin, topOrigin: topOrigin, capability: capability) {
				case true: "allow"
				case false: "block"
				case nil: "ask"
			}
		} set: { value in
			let entry = BrowserSitePermissions.Entry(
				origin: origin,
				topOrigin: topOrigin,
				capability: capability,
				allowed: value == "allow"
			)
			if value == "ask" {
				permissions.remove(entry)
			} else {
				permissions.set(value == "allow", origin: origin, topOrigin: topOrigin, capability: capability)
			}
			onChange()
		}
	}

	var body: some View {
		Picker(capability.title, selection: selection) {
			Label("Ask", systemImage: "questionmark.circle").tag("ask")
			Label("Allow", systemImage: "checkmark.circle").tag("allow")
			Label("Block", systemImage: "hand.raised").tag("block")
		}
		.accessibilityIdentifier("site-permission-\(capability.rawValue)-\(origin)")
	}
}
