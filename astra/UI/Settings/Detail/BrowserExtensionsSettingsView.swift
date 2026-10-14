import SwiftUI
import UniformTypeIdentifiers

struct BrowserExtensionsSettingsView: View {
	let browser: Browser
	@State private var extensions = BrowserExtensionManager.shared
	@State private var showsImporter = false
	@State private var importSource: BrowserExtensionManager.Source = .chrome
	@State private var importedName: String?
	@State private var showsEnablePrompt = false
	@State private var importError: String?
	@State private var pendingRecommendation: BrowserExtensionManager.RecommendedExtension?
	@Environment(\.openURL) private var openURL
	@Environment(\.scenePhase) private var scenePhase

	var body: some View {
		NavigationStack {
			List {
				Section("Optional Extensions") {
				Text("Astra does not ship with third-party extensions. Install only the ones you want.")
					.foregroundStyle(.secondary)
				ForEach(BrowserExtensionManager.RecommendedExtension.allCases, id: \.self) { recommendation in
					if let name = extensions.installedName(for: recommendation) {
						NavigationLink {
							BrowserExtensionDetailView(name: name, browser: browser)
						} label: {
							LabeledContent(recommendation.displayName, value: extensions.isEnabled(name) ? "On" : "Off")
						}
					} else {
						HStack {
							VStack(alignment: .leading, spacing: 3) {
								Text(recommendation.displayName)
								Text(recommendation.detail)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							Spacer()
							if extensions.installingRecommendedExtensions.contains(recommendation) {
							ProgressView().controlSize(.small)
						} else {
							Button("Install") { pendingRecommendation = recommendation }
								.accessibilityIdentifier("install-recommended-\(recommendation.rawValue)")
						}
						}
					}
				}
				Text("Downloads are checked against the publisher's SHA-256 checksum. Permission review is required to enable an extension.")
					.font(.caption)
					.foregroundStyle(.secondary)
				}
				Section("Chrome Extensions") {
					Button("Browse Chrome Web Store", systemImage: "globe") {
						if let url = URL(string: "https://chromewebstore.google.com/") {
							browser.openHistoryURL(url, inBackground: false)
						}
					}
					.accessibilityIdentifier("browse-chrome-web-store")
					Text("Open an extension listing, then use Install Extension beside the address bar.")
						.foregroundStyle(.secondary)
					extensionRows(source: .chrome)
				}
				Section("Safari Extensions") {
					Button("Browse Safari Extensions in App Store", systemImage: "safari") {
						if let url = URL(string: "macappstore://apps.apple.com/story/id1377753262") {
							openURL(url)
						}
					}
					.accessibilityIdentifier("browse-safari-app-store")
					Button("Find Installed Safari Extensions", systemImage: "arrow.clockwise") {
						Task { await extensions.refreshSafariExtensions() }
					}
					.accessibilityIdentifier("refresh-safari-extensions")
					extensionRows(source: .safari)
					ForEach(extensions.safariAppExtensions) { candidate in
						Button("Install \(candidate.name)", systemImage: "plus.circle") {
							Task { await extensions.installSafariExtension(candidate) }
						}
						.accessibilityIdentifier("install-safari-\(candidate.id)")
					}
					Text("Get the extension’s app from the App Store, then install its Safari WebExtension here.")
						.foregroundStyle(.secondary)
				}
				Section {
					Text("Reload open pages after enabling or disabling an extension.")
						.foregroundStyle(.secondary)
				}
			}
			.scrollContentBackground(.hidden)
			.listStyle(.sidebar)
		}
		.task {
			await extensions.prepareAllContexts()
			await extensions.refreshSafariExtensions()
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .active {
				Task { await extensions.refreshSafariExtensions() }
			}
		}
		.fileImporter(isPresented: $showsImporter, allowedContentTypes: [.zip]) { result in
			guard case let .success(url) = result else { return }
			let source = importSource
			Task {
				do {
					importedName = try await extensions.installArchive(from: url, source: source)
					showsEnablePrompt = true
				} catch {
					importError = error.localizedDescription
				}
			}
		}
		.confirmationDialog(
			"Download \(pendingRecommendation?.displayName ?? "Extension")?",
			isPresented: Binding(
				get: { pendingRecommendation != nil },
				set: { if !$0 { pendingRecommendation = nil } }
			)
		) {
			Button("Download and Install") {
				guard let recommendation = pendingRecommendation else { return }
				pendingRecommendation = nil
				Task {
					do {
						try await extensions.installRecommended(recommendation)
					} catch {
						importError = error.localizedDescription
					}
				}
			}
			Button("Cancel", role: .cancel) { pendingRecommendation = nil }
		} message: {
			Text("Astra will download this extension from its publisher and verify its integrity. You will review permissions before enabling it.")
		}
		.confirmationDialog("Enable \(importedName.map(extensions.title(for:)) ?? "Extension")?", isPresented: $showsEnablePrompt) {
			Button("Enable", systemImage: "checkmark", role: .confirm) {
				if let importedName {
					extensions.approveRequestedPermissions(for: importedName)
					extensions.setEnabled(true, for: importedName)
				}
			}
			Button(role: .cancel) {}
		} message: {
			Text(importedName.map(extensions.permissionSummary(for:)) ?? "")
		}
		.alert("Extension Import Failed", isPresented: Binding(
			get: { importError != nil },
			set: {
				if !$0 {
					importError = nil
				}
			}
		)) {
			Button(role: .cancel) {}
		} message: {
			Text(importError ?? "Unknown error")
		}
	}

	@ViewBuilder
	private func extensionRows(source: BrowserExtensionManager.Source) -> some View {
		ForEach(extensions.availableNames.filter { extensions.source(for: $0) == source }, id: \.self) { name in
			NavigationLink {
				BrowserExtensionDetailView(name: name, browser: browser)
			} label: {
				LabeledContent(extensions.title(for: name), value: extensions.isEnabled(name) ? "On" : "Off")
			}
			.accessibilityIdentifier("extension-\(name)")
			.contextMenu {
				if extensions.installedNames.contains(name) {
					Button("Remove Extension", systemImage: "trash", role: .destructive) {
						extensions.removeInstalled(name)
					}
				}
			}
			if let error = extensions.loadErrors[name] {
				Text(error)
					.foregroundStyle(.secondary)
			}
		}
		Button("Import Extension ZIP", systemImage: "square.and.arrow.down") {
			importSource = source
			showsImporter = true
		}
		.accessibilityIdentifier("import-\(source.rawValue)-extension")
	}
}
