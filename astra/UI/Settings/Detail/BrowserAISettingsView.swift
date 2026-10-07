import Defaults
import SwiftUI
#if os(macOS)
	import AppKit
#endif

struct BrowserAISettingsView: View {
	@Default(.aiFeaturesEnabled) private var allFeatures
	@Default(.renameDownloadsWithAppleIntelligence) private var downloads
	@Default(.aiLinkPreviews) private var previews
	@Default(.aiLinkPreviewMode) private var previewMode
	@Default(.aiLinkPreviewShiftOverride) private var previewShiftOverride
	@Default(.aiLinkPreviewDelay) private var previewDelay
	@Default(.aiTabGroups) private var groups
	@Default(.aiFind) private var find
	@Default(.aiFindContextLimit) private var contextLimit
	@Default(.aiSidebar) private var sidebar
	@Default(.aiTabTitles) private var titles
	@Default(.aiProvider) private var provider
	@Default(.aiCodexModel) private var codexModel
	@Default(.aiClaudeModel) private var claudeModel
	@Default(.aiCodexReasoning) private var codexReasoning
	@Default(.aiClaudeReasoning) private var claudeReasoning
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
			Text("Enable or disable all AI features below. AI features do not run in private windows.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(10)
			Section("Features") {
				Toggle("Rename Downloads", isOn: $downloads)
					.accessibilityIdentifier("rename-downloads-with-apple-intelligence")
					.id("Rename Downloads")
				Text("Automatically gives completed downloads descriptive filenames based on the original name, website, and file type. Keeps the file extension.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
				Picker("Link Previews", selection: Binding(get: { previews ? previewMode : "never" }, set: {
					previewMode = $0
					previews = true
				})) {
					Label("Always Show Previews", systemImage: "sparkles").tag("always")
					Label("Don’t Show Previews", systemImage: "eye.slash").tag("never")
					Label("Search Engines Only", systemImage: "magnifyingglass").tag("search")
				}
				.pickerStyle(.menu)
				.accessibilityLabel("When to show link previews")
				.accessibilityIdentifier("ai-link-previews")
				Text("Hover over a link smaller than 100 × 100 points to summarize its destination. Always showing previews may trigger frequently. Preview pages load separately and may differ from signed-in pages.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
				Toggle("Force a Preview While Holding Shift", isOn: $previewShiftOverride)
					.accessibilityLabel("Force a preview when holding Shift while hovering over a link")
					.accessibilityIdentifier("ai-link-preview-shift-override")
				Text("Hold Shift while hovering over a link to show its summary, even when previews are disabled for that page. The link size limit still applies.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
				HStack {
					Slider(value: $previewDelay, in: 0 ... 10, step: 0.25) {
						Text("Preview Delay")
							.lineLimit(10)
					}
					.accessibilityLabel("Link preview delay in seconds")
					.accessibilityIdentifier("ai-link-preview-delay")
					Text("\(previewDelay, format: .number.precision(.fractionLength(0 ... 2))) s")
						.lineLimit(10)
						.monospacedDigit()
						.frame(minWidth: 48, alignment: .trailing)
				}
				.disabled((!previews || previewMode == "never") && !previewShiftOverride)
				Text("How long to hover over a link before its AI preview appears, in seconds.")
					.lineLimit(10)
					.font(.caption)
					.foregroundStyle(.secondary)
				Toggle("Tidy Today Tabs", isOn: $groups)
					.accessibilityIdentifier("ai-tab-groups")
				Text("Enables the Tidy Today Tabs button above Today tabs when there are more than six. Use it to group those tabs into sections by topic.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
				Toggle("Clean Tab Titles", isOn: $titles)
					.accessibilityIdentifier("ai-tab-titles")
				Text("Enables the Clean Tab Titles button above Today tabs. Use it to shorten their titles and remove repeated site names, notification counts, and other clutter.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
				Toggle("Clean Bookmark Titles", isOn: $bookmarkTitles)
					.accessibilityIdentifier("ai-bookmark-titles")
				Text("Enables title cleanup in Bookmarks. Use it to shorten bookmark names and remove unnecessary wording while keeping their subject.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
				Toggle("Monitor Websites", isOn: $monitoring)
					.accessibilityIdentifier("ai-website-monitoring")
				Text("Use the Monitor Website bell button to set a condition, such as “this item is available to buy,” and a check interval. The server checks the public page even while Astra is closed. Requires an Astra account; results arrive when Astra reconnects, with a pinned tab and a notification if allowed.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
				Toggle("Ask in Find", isOn: $find)
					.accessibilityIdentifier("ai-find")
				Text("Type a question in Find in Page. If no matching text is found, AI reads the page and answers your question.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
				Toggle("Limit Large Pages to 30,000 Tokens", isOn: $contextLimit)
					.disabled(!find)
					.padding(.leading, 16)
					.accessibilityIdentifier("ai-find-context-limit")
				Text("When extracted page text exceeds 40,000 tokens, Find uses its first 30,000. Turning this off sends the full text; the provider’s context limit still applies.")
					.lineLimit(10)
					.font(.caption)
					.foregroundStyle(.secondary)
				Toggle("AI Sidebar", isOn: $sidebar)
					.accessibilityIdentifier("ai-sidebar-enabled")
				Text("Enables the AI chat sidebar for questions, linked pages, and attachments. The assistant can also perform the browser actions you allow below.")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(10)
			}
			.disabled(!allFeatures)
			Section("Browser Actions") {
				ForEach(BrowserAIAction.allCases) { action in
					Toggle(action.title, isOn: Binding(get: { action.enabled }, set: { action.enabled = $0 }))
						.accessibilityIdentifier("ai-action-\(action.rawValue)")
				}
				Text("Closing tabs and deleting bookmarks are disabled by default. Disabled actions are checked again before execution.")
					.lineLimit(10)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.disabled(!allFeatures)
			Section("Monitored Websites") {
				ForEach(websiteMonitors.monitors) { monitor in
					HStack {
						VStack(alignment: .leading, spacing: 4) {
							Text(monitor.title).lineLimit(10)
							Text(monitor.criterion).font(.caption).foregroundStyle(.secondary)
								.lineLimit(10)
							Text(monitor.matchedAt != nil ? "Condition fulfilled" : monitor.enabled ? "Monitoring" : "Paused").font(.caption)
								.lineLimit(10)
							if let error = monitor.lastError {
								Text(error).font(.caption).foregroundStyle(.secondary)
									.lineLimit(10)
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
						.lineLimit(10)
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
					if provider == "codex" || provider == "claude" {
						BrowserAIModelControls(
							selectedProvider: .constant(provider),
							selectedModelID: provider == "codex" ? $codexModel : $claudeModel,
							selectedReasoning: provider == "codex" ? $codexReasoning : $claudeReasoning,
							provider: provider,
							identifierPrefix: "ai-request"
						)
						.id(provider)
					}
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
						.lineLimit(10)
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
		.lineLimit(10)
		.listStyle(.sidebar)
		.scrollContentBackground(.hidden)
		.task { await websiteMonitors.refresh() }
		.onChange(of: allFeatures) { _, enabled in Task { await websiteMonitors.setEnabled(enabled && monitoring) } }
		.onChange(of: monitoring) { _, enabled in Task { await websiteMonitors.setEnabled(enabled && allFeatures) } }
	}
}
