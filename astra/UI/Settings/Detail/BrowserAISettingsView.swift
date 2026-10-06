import Defaults
import SwiftUI
#if os(macOS)
	import AppKit
#endif

struct BrowserAISettingsView: View {
	@Default(.aiFeaturesEnabled) private var allFeatures
	@Default(.renameDownloadsWithAppleIntelligence) private var downloads
	@Default(.aiLinkPreviews) private var previews
	@Default(.aiTabGroups) private var groups
	@Default(.aiFind) private var find
	@Default(.aiFindContextLimit) private var contextLimit
	@Default(.aiSidebar) private var sidebar
	@Default(.aiTabTitles) private var titles
	@Default(.aiProvider) private var provider
	@Default(.aiBrowserActionPermissions) private var permissions
	@Default(.aiBookmarkTitles) private var bookmarkTitles
	@Default(.aiWebsiteMonitoring) private var monitoring
	@State private var websiteMonitors = BrowserWebsiteMonitoring.shared
	@State private var usageLog = BrowserAIUsageLog.shared

	var body: some View {
		List {
			Toggle("All AI Features", isOn: $allFeatures)
				.accessibilityLabel("All AI Features")
				.accessibilityIdentifier("ai-all-features")
				.id("All AI Features")
			Section("Features") {
				Toggle("Rename Downloads", isOn: $downloads)
					.accessibilityIdentifier("rename-downloads-with-apple-intelligence")
					.id("Rename Downloads")
				Toggle("Link Previews", isOn: $previews)
					.accessibilityIdentifier("ai-link-previews")
				Text("Hold over a link for two seconds to summarize its destination. Preview pages load separately and may differ from signed-in pages.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Toggle("Tidy Today Tabs", isOn: $groups)
					.accessibilityIdentifier("ai-tab-groups")
				Toggle("Clean Tab Titles", isOn: $titles)
					.accessibilityIdentifier("ai-tab-titles")
				Toggle("Clean Bookmark Titles", isOn: $bookmarkTitles)
					.accessibilityIdentifier("ai-bookmark-titles")
				Toggle("Monitor Websites", isOn: $monitoring)
					.accessibilityIdentifier("ai-website-monitoring")
				Toggle("Ask in Find", isOn: $find)
					.accessibilityIdentifier("ai-find")
				Toggle("Limit Large Pages to 30,000 Tokens", isOn: $contextLimit)
					.disabled(!find)
					.padding(.leading, 16)
					.accessibilityIdentifier("ai-find-context-limit")
				Text("When extracted page text exceeds 40,000 tokens, Find uses its first 30,000. Turning this off sends the full text; the provider’s context limit still applies.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Toggle("AI Sidebar", isOn: $sidebar)
					.accessibilityIdentifier("ai-sidebar-enabled")
			}
			.disabled(!allFeatures)
			Section("Browser Actions") {
				ForEach(BrowserAIAction.allCases) { action in
					Toggle(action.title, isOn: Binding(get: { action.enabled }, set: { action.enabled = $0 }))
						.accessibilityIdentifier("ai-action-\(action.rawValue)")
				}
				Text("Closing tabs and deleting bookmarks are disabled by default. Disabled actions are checked again before execution.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.disabled(!allFeatures)
			Section("Monitored Websites") {
				ForEach(websiteMonitors.monitors) { monitor in
					HStack {
						VStack(alignment: .leading, spacing: 4) {
							Text(monitor.title).lineLimit(1)
							Text(monitor.criterion).font(.caption).foregroundStyle(.secondary)
							Text(monitor.matchedAt != nil ? "Condition fulfilled" : monitor.enabled ? "Monitoring" : "Paused").font(.caption)
							if let error = monitor.lastError {
								Text(error).font(.caption).foregroundStyle(.secondary)
							}
						}
						Spacer()
						Button("Delete Website Monitor", systemImage: "trash", role: .destructive) { Task { await websiteMonitors.remove(monitor.id) } }
							.labelStyle(.iconOnly)
							.accessibilityIdentifier("delete-monitor-\(monitor.id.uuidString)")
					}
				}
				if let error = websiteMonitors.error {
					Text(error).font(.caption).foregroundStyle(.secondary)
				}
			}
			#if os(macOS)
				Section("Requests") {
					Picker("Use AI With", selection: $provider) {
						Label("Default", systemImage: "sparkles").tag("presets")
						Label("Codex", systemImage: "terminal").tag("codex")
						Label("Claude", systemImage: "terminal").tag("claude")
					}
					.accessibilityIdentifier("ai-request-provider")
					Text("Codex or Claude applies to every AI feature and uses your installed command and its signed-in account. Page text, linked pages, titles, or download names are sent to the selected service. AI features do not run in private windows.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(10)
				}
			#endif
			Section("Usage Log") {
				Text("Every AI request is logged locally with its feature, provider, timing, and outcome. Page text, messages, attachments, and credentials are not copied into the log.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
				#if os(macOS)
					Button("Show Usage Log", systemImage: "doc.text.magnifyingglass") {
						Task {
							if let url = await usageLog.location() {
								NSWorkspace.shared.activateFileViewerSelecting([url])
							}
						}
					}
					.accessibilityIdentifier("ai-show-usage-log")
					.id("Show Usage Log")
				#endif
				if let error = usageLog.errorDescription {
					Text(error)
						.font(.caption)
						.foregroundStyle(.secondary)
						.accessibilityIdentifier("ai-usage-log-error")
				}
			}
			.id("Usage Log")
			Text("AI processes extracted page text for previews, Find, and explicitly linked chat pages. Chat sends the full linked text. Tab organization sends titles and URLs. Responses can be inaccurate.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(10)
		}
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
		.task { await websiteMonitors.refresh() }
		.onChange(of: allFeatures) { _, enabled in Task { await websiteMonitors.setEnabled(enabled && monitoring) } }
		.onChange(of: monitoring) { _, enabled in Task { await websiteMonitors.setEnabled(enabled && allFeatures) } }
	}
}

#if DEBUG
	struct BrowserAIPresetSettings: View {
		@Default(.aiFeaturePresets) private var presets
		@Default(.aiCodexModel) private var codexModel
		@Default(.aiClaudeModel) private var claudeModel
		@State private var feature: BrowserAIFeatureID?
		@State private var provider: String?

		var body: some View {
			Section("AI Feature Presets") {
				ForEach(BrowserAIFeatureID.allCases) { item in
					Button(item.title, systemImage: "cpu") { feature = item }
						.accessibilityIdentifier("ai-preset-\(item.rawValue)")
				}
				Button("Codex Model", systemImage: "terminal") { provider = "codex" }
					.accessibilityIdentifier("ai-codex-model")
				Button("Claude Model", systemImage: "terminal") { provider = "claude" }
					.accessibilityIdentifier("ai-claude-model")
				Text("Developer controls. Production settings show feature toggles and the provider override only. Model catalogs refresh whenever these menus open. All requests use low reasoning where supported.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.popover(item: $feature) { item in
				BrowserAIModelChooser(initialProvider: "openrouter", includesApple: item != .chat) { model in
					var values = BrowserAISettings.presets
					values[item.rawValue] = model.identifier
					BrowserAISettings.presets = values
					feature = nil
				}
			}
			.popover(isPresented: Binding(get: { provider != nil }, set: {
				if !$0 {
					provider = nil
				}
			})) {
				if let provider {
					BrowserAIModelChooser(initialProvider: provider, includesApple: false) { model in
						switch model {
							case let .codex(id): codexModel = id
							case let .claude(id): claudeModel = id
							default: break
						}
						self.provider = nil
					}
				}
			}
		}
	}

	private struct BrowserAIModelChooser: View {
		let initialProvider: String
		let includesApple: Bool
		let select: (BrowserAIModel) -> Void
		@State private var provider = ""
		@State private var models: [BrowserAIModelOption] = []
		@State private var error: String?
		@State private var loading = true

		var body: some View {
			List {
				if includesApple {
					Button("On-Device Foundation Model", systemImage: "apple.intelligence") { select(.appleIntelligence) }
						.accessibilityIdentifier("ai-model-apple")
					Button("Private Cloud Compute", systemImage: "cloud") { select(.privateCloudCompute) }
						.accessibilityIdentifier("ai-model-pcc")
					Picker("Catalog", selection: $provider) {
						Text("OpenRouter").tag("openrouter")
						Text("Codex").tag("codex")
						Text("Claude").tag("claude")
					}
					.accessibilityIdentifier("ai-model-catalog")
				}
				if loading {
					ProgressView("Retrieving Models")
				}
				if let error {
					Text(error).foregroundStyle(.secondary)
				}
				ForEach(models) { model in
					Button(model.title, systemImage: "cpu") {
						switch provider {
							case "codex": select(.codex(modelID: model.id))
							case "claude": select(.claude(modelID: model.id))
							default: select(.openRouter(modelID: model.id))
						}
					}
					.accessibilityIdentifier("ai-model-\(model.id)")
				}
			}
			.listStyle(.sidebar)
			.scrollContentBackground(.hidden)
			.frame(width: 380, height: 450)
			.onAppear { provider = initialProvider }
			.task(id: provider) {
				guard !provider.isEmpty else { return }
				models = []
				error = nil
				loading = true
				defer {
					if !Task.isCancelled {
						loading = false
					}
				}
				do {
					let result: [BrowserAIModelOption]
					if provider == "openrouter" {
						let (data, response) = try await URLSession.shared.data(from: URL(string: "https://openrouter.ai/api/v1/models")!)
						guard (response as? HTTPURLResponse)?.statusCode == 200,
						      let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BrowserAIError.cliUnavailable }
						result = (body["data"] as? [[String: Any]] ?? []).compactMap { item in
							guard let id = item["id"] as? String else { return nil }
							return BrowserAIModelOption(id: id, title: item["name"] as? String ?? id)
						}
					} else {
						result = try await BrowserAICLI.models(provider: provider)
					}
					try Task.checkCancellation()
					models = result
					if result.isEmpty {
						error = "No models were returned by this command."
					}
				} catch {
					if !Task.isCancelled {
						self.error = error.localizedDescription
					}
				}
			}
		}
	}
#endif
