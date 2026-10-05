import SwiftUI
import UniformTypeIdentifiers

/// Shared by Settings and library sheets; can also be embedded in onboarding.
struct BrowserImportView: View {
	let browser: Browser
	var scope: BrowserImportScope = .all
	@State private var source: BrowserImportSource = .chrome
	@State private var profiles: [BrowserImportProfile] = []
	@State private var selectedProfile: URL?
	@State private var importsBookmarks = true
	@State private var importsHistory = true
	@State private var showsFilePicker = false
	@State private var showsFolderPicker = false
	@State private var isLoading = false
	@State private var preview: BrowserProfileImporter.Preview?
	@State private var message: String?
	@State private var folder: URL?
	@State private var discoveryID = UUID()

	private var selectedScope: BrowserImportScope {
		if scope != .all {
			return scope
		}
		if !importsBookmarks {
			return .history
		}
		if !importsHistory {
			return .bookmarks
		}
		return .all
	}

	private var canImport: Bool {
		!browser.isPrivate && !browser.isMini && !isLoading
			&& (scope != .all || importsBookmarks || importsHistory)
	}

	var body: some View {
		List {
			#if os(macOS)
				Section("From Another Browser") {
					Picker("Browser", selection: $source) {
						ForEach(BrowserImportSource.allCases) { source in
							Text(source.rawValue).tag(source)
						}
					}
					.accessibilityIdentifier("import-source-browser")
					.disabled(isLoading)
					if !profiles.isEmpty {
						Picker("Profile", selection: $selectedProfile) {
							ForEach(profiles) { profile in
								Text(profile.name).tag(Optional(profile.id))
							}
						}
						.accessibilityIdentifier("import-source-profile")
						.disabled(isLoading)
					}
					Text(source.folderHint)
						.font(.caption)
						.foregroundStyle(.secondary)
					Button("Choose Browser Data Folder", systemImage: "folder") {
						showsFolderPicker = true
					}
					.accessibilityIdentifier("choose-browser-import-folder")
					.disabled(!canImport)
					Button("Read Selected Profile", systemImage: "arrow.down.doc") {
						readProfile()
					}
					.accessibilityIdentifier("read-browser-import-profile")
					.disabled(!canImport || selectedProfile == nil)
				}
			#endif
			Section("Import from a File") {
				Button("Choose Import File", systemImage: "square.and.arrow.down") {
					showsFilePicker = true
				}
				.accessibilityIdentifier("choose-browsing-import-file")
				.disabled(!canImport)
				Text(scope == .history ? "Choose an Astra history or browsing-data JSON export." : "Choose a bookmarks HTML file or an Astra browsing-data JSON export.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			if scope == .all {
				Section("Data to Import") {
					Toggle("Bookmarks", isOn: $importsBookmarks)
						.accessibilityIdentifier("import-include-bookmarks")
					Toggle("History", isOn: $importsHistory)
						.accessibilityIdentifier("import-include-history")
				}
				.disabled(isLoading)
			}
			if isLoading {
				ProgressView("Reading browsing data…")
					.accessibilityIdentifier("browser-import-progress")
			}
			if let preview {
				Section("Ready to Import") {
					if selectedScope.includesBookmarks {
						LabeledContent("Bookmarks", value: preview.document.bookmarks.count.formatted())
					}
					if selectedScope.includesHistory {
						LabeledContent("History Visits", value: preview.document.history.count.formatted())
					}
					ForEach(preview.warnings, id: \.self) { warning in
						Label(warning, systemImage: "exclamationmark.triangle")
							.foregroundStyle(.secondary)
					}
					Text("Existing bookmarks are kept. Matching history visits are skipped. History follows your retention setting.")
						.font(.caption)
						.foregroundStyle(.secondary)
					Button("Import", systemImage: "square.and.arrow.down", role: .confirm) {
						apply(preview.document)
					}
					.buttonStyle(.glassProminent)
					.accessibilityIdentifier("confirm-browser-data-import")
					.disabled(!canImport || (preview.document.bookmarks.isEmpty && preview.document.history.isEmpty))
				}
			}
			if let message {
				Section {
					Text(message)
						.accessibilityIdentifier("browser-import-result")
				}
			}
		}
		.scrollContentBackground(.hidden)
		#if os(iOS)
			.listStyle(.insetGrouped)
		#else
			.listStyle(.sidebar)
		#endif
			.task(id: source) { await discoverProfiles() }
			.onChange(of: source) { _, _ in preview = nil }
			.onChange(of: selectedProfile) { _, _ in preview = nil }
			.onChange(of: importsBookmarks) { _, _ in preview = nil }
			.onChange(of: importsHistory) { _, _ in preview = nil }
			.fileImporter(isPresented: $showsFilePicker, allowedContentTypes: scope == .history ? [.json] : [.html, .json]) { result in
				switch result {
					case let .success(url): readFile(url)
					case let .failure(error): message = error.localizedDescription
				}
			}
		#if os(macOS)
			.fileImporter(isPresented: $showsFolderPicker, allowedContentTypes: [.folder]) { result in
				switch result {
					case let .success(url):
						folder?.stopAccessingSecurityScopedResource()
						_ = url.startAccessingSecurityScopedResource()
						folder = url
						Task { await discoverProfiles(in: url) }
					case let .failure(error): message = error.localizedDescription
				}
			}
		#endif
			.onDisappear {
				folder?.stopAccessingSecurityScopedResource()
			}
	}

	private func discoverProfiles(in directory: URL? = nil) async {
		#if os(macOS)
			let source = source
			let requestID = UUID()
			discoveryID = requestID
			profiles = []
			selectedProfile = nil
			preview = nil
			do {
				let found = try await Task.detached(priority: .userInitiated) {
					try BrowserProfileImporter.profiles(for: source, in: directory)
				}.value
				guard !Task.isCancelled, self.source == source, discoveryID == requestID else { return }
				profiles = found
				selectedProfile = found.first?.id
				message = found.isEmpty ? "No profiles found. Choose the browser’s data folder or an exported file." : nil
			} catch {
				guard !Task.isCancelled, self.source == source, discoveryID == requestID else { return }
				message = "The browser’s data folder could not be read. Choose its folder or an exported file. \(error.localizedDescription)"
			}
		#endif
	}

	private func readProfile() {
		guard canImport, let profile = profiles.first(where: { $0.id == selectedProfile }) else { return }
		let scope = selectedScope
		isLoading = true
		preview = nil
		message = nil
		Task {
			do {
				preview = try await Task.detached(priority: .userInitiated) {
					try BrowserProfileImporter.read(profile, scope: scope)
				}.value
			} catch {
				message = error.localizedDescription
			}
			isLoading = false
		}
	}

	private func readFile(_ url: URL) {
		guard canImport else { return }
		let scope = selectedScope
		isLoading = true
		preview = nil
		message = nil
		Task {
			do {
				let document = try await Task.detached(priority: .userInitiated) {
					let accessed = url.startAccessingSecurityScopedResource()
					defer {
						if accessed {
							url.stopAccessingSecurityScopedResource()
						}
					}
					let document = try BrowserUserData.decode(BrowserProfileImporter.readFile(url), isHTML: ["html", "htm"].contains(url.pathExtension.lowercased()))
					return scope.selecting(document)
				}.value
				preview = BrowserProfileImporter.Preview(document: document, warnings: [])
			} catch {
				message = error.localizedDescription
			}
			isLoading = false
		}
	}

	private func apply(_ document: BrowserUserData) {
		guard canImport else { return }
		let bookmarkCount = browser.bookmarks.count
		let historyCount = browser.historyVisits.count
		browser.importBookmarks(document.bookmarks)
		browser.importHistory(document.history)
		message = "Imported \(browser.bookmarks.count - bookmarkCount) bookmarks and \(max(0, browser.historyVisits.count - historyCount)) history visits."
		preview = nil
	}
}
