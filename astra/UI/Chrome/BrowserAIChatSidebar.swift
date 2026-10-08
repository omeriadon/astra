import Defaults
import MarkdownView
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
	import AppKit
#else
	import UIKit
#endif

struct BrowserAIChatSidebar: View {
	@Bindable var browser: Browser
	@Bindable var chat: BrowserAIChat
	var isVisible = true
	@Environment(\.colorScheme) private var colorScheme
	@State private var hoveredURL: URL?
	@State private var hoveredLinkSize = CGSize.zero
	@State private var hoveredLinkShiftPressed = false
	@State private var requestID: UUID?
	@State private var showsHistory = false
	@State private var showsFileImporter = false
	@State private var history = BrowserAIChatHistory.shared
	@State private var sync = BrowserSync.shared
	@Default(.aiProvider) private var provider

	private var needsSignIn: Bool {
		if case .openRouter = BrowserAISettings.effectiveModel(BrowserAIFeatureID.chat.model) {
			return !sync.isSignedIn
		}
		return false
	}

	private var canSend: Bool {
		!chat.isImporting && (!chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chat.attachments.isEmpty || !chat.pendingPages.isEmpty)
	}

	@FocusState private var focused: Bool

	var body: some View {
		VStack(spacing: 12) {
			ScrollViewReader { reader in
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 16) {
						if chat.messages.isEmpty {
							Text("Ask a question. Type @ to link an open page. Suggestions come from this space; type an exact page title to link another space.")
								.foregroundStyle(.secondary)
						}
						ForEach(chat.messages) { message in
							VStack(alignment: .leading, spacing: 5) {
								Text(message.isUser ? "You" : "AI")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)
								if !message.attachments.isEmpty {
									attachmentRow(message.attachments, removable: false)
								}
								if message.isUser {
									Text(message.text).textSelection(.enabled)
								} else {
									chatMarkdown(message.text, streaming: false)
								}
							}
							.id(message.id)
						}
						// Streaming responses update many times per second. Keep
						// that observation in a leaf view so the entire sidebar,
						// toolbar, composer and historical Markdown views are not
						// invalidated for each generated token.
						BrowserAIChatStreamingResponse(
							chat: chat,
							browser: browser,
							hoveredURL: $hoveredURL,
							hoveredLinkSize: $hoveredLinkSize,
							hoveredLinkShiftPressed: $hoveredLinkShiftPressed,
							onPreviewChange: { reader.scrollTo("chat-bottom", anchor: .bottom) }
						)
						Color.clear.frame(height: 1).id("chat-bottom")
					}
					.padding(.horizontal, 12)
				}
				.onChange(of: chat.messages.count) { _, _ in reader.scrollTo("chat-bottom", anchor: .bottom) }
			}
		}
		.safeAreaBar(edge: .top) {
			VStack(spacing: 12) {
				HStack(spacing: 8) {
					Text(chat.title)
						.font(.headline)
						.lineLimit(1)
						.accessibilityIdentifier("ai-chat-title")
					Spacer(minLength: 0)
					Button("Recent Chats", systemImage: "clock.arrow.circlepath") { showsHistory.toggle() }
						.labelStyle(.iconOnly)
						.disabled(chat.isResponding || chat.isImporting)
						.accessibilityIdentifier("ai-chat-history")
						.popover(isPresented: $showsHistory) {
							List {
								Section("Chats") {
									if history.conversations.isEmpty {
										Text("No saved chats").foregroundStyle(.secondary)
									}
									ForEach(history.conversations) { conversation in
										Button {
											chat.select(conversation)
											showsHistory = false
										} label: {
											VStack(alignment: .leading, spacing: 4) {
												Label(conversation.title, systemImage: conversation.id == chat.id ? "bubble.left.fill" : "bubble.left")
													.lineLimit(2)
												Text(conversation.updatedAt, style: .relative)
													.font(.caption)
													.foregroundStyle(.secondary)
											}
										}
										.buttonStyle(.plain)
										.accessibilityIdentifier("ai-recent-chat-\(conversation.id.uuidString)")
									}
								}
								if let error = history.error {
									Text(error).font(.caption).foregroundStyle(.secondary)
								}
							}
							.listStyle(.sidebar)
							.scrollContentBackground(.hidden)
							.frame(width: 320, height: 360)
						}
					Button("New Chat", systemImage: "square.and.pencil", action: chat.clear)
						.labelStyle(.iconOnly)
						.disabled(chat.isResponding || chat.isImporting)
						.accessibilityIdentifier("ai-chat-new")
					Button("Close AI Sidebar", systemImage: "xmark") { browser.showsAISidebar = false }
						.labelStyle(.iconOnly)
						.accessibilityIdentifier("ai-chat-close")
				}
				.buttonStyle(.glass)
				.padding([.top, .horizontal], 12)
				if isVisible, ["codex", "claude"].contains(provider) {
					BrowserAIModelControls(
						selectedProvider: $chat.selectedProvider,
						selectedModelID: $chat.selectedModelID,
						selectedReasoning: $chat.selectedReasoning,
						provider: provider,
						isDisabled: chat.isResponding,
						initialModelID: provider == "codex" ? Defaults[.aiCodexModel] : Defaults[.aiClaudeModel],
						initialReasoning: provider == "codex" ? Defaults[.aiCodexReasoning] : Defaults[.aiClaudeReasoning]
					)
					.padding(.horizontal, 12)
				}
				if needsSignIn {
					VStack(alignment: .leading, spacing: 6) {
						Label("Sign in to Astra to use Default AI.", systemImage: "person.crop.circle.badge.exclamationmark")
						Text("Codex and Claude do not require an Astra account.").font(.caption).foregroundStyle(.secondary)
						Button("Account & Sync", systemImage: "person.crop.circle") {
							browser.settingsPage = .account
							browser.openInternalPage(.settings)
						}
						.accessibilityIdentifier("ai-chat-sign-in-settings")
					}
					.padding(.horizontal, 12)
					.accessibilityIdentifier("ai-chat-sign-in-required")
				}
			}
		}
		.safeAreaBar(edge: .bottom) {
			VStack(alignment: .leading, spacing: 8) {
				Button("Summarise", systemImage: "text.alignleft") {
					chat.includeCurrentTab(in: browser)
					chat.draft = "Summarise the current page."
					send()
				}
				.buttonStyle(.glass)
				.disabled(chat.isResponding || !chat.draft.isEmpty)
				.accessibilityIdentifier("ai-chat-summarise")
				if chat.mentionQuery != nil {
					ScrollView {
						VStack(alignment: .leading, spacing: 4) {
							ForEach(chat.suggestions(in: browser)) { tab in
								Button(tab.title, systemImage: "globe") { chat.link(tab) }
									.lineLimit(2)
									.disabled(chat.isResponding)
									.accessibilityIdentifier("ai-chat-mention-\(tab.id.uuidString)")
							}
						}
					}
					.frame(maxHeight: 160)
				}
				ForEach(chat.linkedTabIDs, id: \.self) { id in
					HStack {
						Label(chat.availableTabs(in: browser).first(where: { $0.id == id })?.title ?? "Closed Page", systemImage: "link")
							.lineLimit(1)
						Spacer()
						Button("Remove Linked Page", systemImage: "xmark") { chat.linkedTabIDs.removeAll { $0 == id } }
							.labelStyle(.iconOnly)
							.disabled(chat.isResponding)
							.accessibilityIdentifier("ai-chat-unlink-\(id.uuidString)")
					}
				}
				ForEach(chat.pendingPages) { page in
					HStack {
						Label(page.title, systemImage: "globe").lineLimit(1)
						Spacer()
						Button("Remove Page Context", systemImage: "xmark") { chat.pendingPages.removeAll { $0.id == page.id } }
							.labelStyle(.iconOnly)
							.disabled(chat.isResponding)
							.accessibilityIdentifier("ai-chat-remove-preview-context")
					}
				}
				if !chat.attachments.isEmpty {
					attachmentRow(chat.attachments, removable: true)
				}
				if chat.isImporting {
					ProgressView("Reading Files")
				}
				TextField("Message AI", text: $chat.draft, axis: .vertical)
					.lineLimit(1 ... 6)
					.textFieldStyle(.plain)
					.focused($focused)
					.padding(12)
					.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
					.onSubmit { send() }
					.disabled(chat.isResponding)
					.accessibilityLabel("Message AI. Type at to link a page.")
					.accessibilityIdentifier("ai-chat-input")
				HStack {
					Button("Attach Images or Files", systemImage: "paperclip") { showsFileImporter = true }
						.labelStyle(.iconOnly)
						.buttonStyle(.glass)
						.disabled(chat.isResponding || chat.isImporting)
						.accessibilityIdentifier("ai-chat-attach")
					Text("Pages and files are sent as context.")
						.font(.caption2)
						.foregroundStyle(.secondary)
					Spacer()
					if chat.isResponding {
						Button("Stop Answer", systemImage: "stop.fill") { requestID = nil }
							.labelStyle(.iconOnly)
							.accessibilityIdentifier("ai-chat-stop")
					} else {
						Button("Send Message", systemImage: "arrow.up", role: .confirm, action: send)
							.labelStyle(.iconOnly)
							.buttonStyle(.glassProminent)
							.disabled(!canSend)
							.accessibilityIdentifier("ai-chat-send")
					}
				}
			}
			.padding(12)
			.disabled(chat.isResponding && requestID == nil)
		}

		#if os(macOS)
		.overlay(alignment: .bottomLeading) {
			if isVisible, let hoveredURL {
				BrowserAIChatLinkPreview(browser: browser, url: hoveredURL, linkSize: hoveredLinkSize, shiftPressed: hoveredLinkShiftPressed)
					.id(hoveredURL)
					.padding(8)
			}
		}
		#endif

		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(browser.theme.contentShade(for: colorScheme))
		.clipShape(RoundedRectangle(cornerRadius: BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar))
		.onAppear {
			focused = isVisible
			if isVisible {
				chat.includeCurrentTab(in: browser)
			}
		}
		.onChange(of: isVisible) { _, visible in
			focused = visible
			if !visible {
				hoveredURL = nil
			}
			if visible {
				chat.includeCurrentTab(in: browser)
			}
		}
		.task { await history.load() }
		.fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
			switch result {
				case let .success(urls): Task { await chat.importFiles(urls) }
				case let .failure(error): chat.reportImportError(error)
			}
		}
		.dropDestination(for: URL.self) { urls, _ in
			guard !chat.isResponding, !chat.isImporting else { return false }
			let files = urls.filter(\.isFileURL)
			guard !files.isEmpty else { return false }
			Task { await chat.importFiles(files) }
			return true
		}
		.task(id: "\(requestID?.uuidString ?? "")|\(isVisible)") {
			guard isVisible, requestID != nil else { return }
			await chat.send(in: browser)
			if !Task.isCancelled {
				requestID = nil
			}
		}
		.accessibilityIdentifier("ai-chat-sidebar")
	}

	@ViewBuilder
	private func chatMarkdown(_ text: String, streaming: Bool) -> some View {
		#if os(macOS)
			BrowserAIChatMarkdown(text: text, streaming: streaming, open: { url in
				browser.openHistoryURL(url, inBackground: false)
			}, hover: { url, previous, size, shift in
				if url != nil || hoveredURL == previous {
					hoveredURL = url
					hoveredLinkSize = size
					hoveredLinkShiftPressed = shift
				}
			})
			.frame(maxWidth: .infinity, alignment: .leading)
		#else
			Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
				.textSelection(.enabled)
				.environment(\.openURL, OpenURLAction { url in
					browser.openHistoryURL(url, inBackground: false)
					return .handled
				})
		#endif
	}

	private func attachmentRow(_ attachments: [BrowserAIAttachment], removable: Bool) -> some View {
		ScrollView(.horizontal) {
			HStack(alignment: .top, spacing: 8) {
				ForEach(attachments) { attachment in
					VStack(spacing: 4) {
						Group {
							if let data = attachment.image?.data {
								#if os(macOS)
									if let image = NSImage(data: data) {
										Image(nsImage: image).resizable().scaledToFit()
									}
								#else
									if let image = UIImage(data: data) {
										Image(uiImage: image).resizable().scaledToFit()
									}
								#endif
							} else {
								Image(systemName: "doc.text").font(.title)
							}
						}
						.frame(width: 80, height: 64)
						.clipShape(RoundedRectangle(cornerRadius: 8))
						.accessibilityLabel(attachment.name)
						Text(attachment.name).font(.caption2).lineLimit(1).frame(width: 80)
					}
					.overlay(alignment: .topTrailing) {
						if removable {
							Button("Remove \(attachment.name)", systemImage: "xmark.circle.fill") { chat.attachments.removeAll { $0.id == attachment.id } }
								.labelStyle(.iconOnly)
								.buttonStyle(.plain)
								.disabled(chat.isResponding)
								.accessibilityIdentifier("ai-chat-remove-attachment-\(attachment.id.uuidString)")
						}
					}
					.accessibilityIdentifier("ai-chat-attachment-\(attachment.id.uuidString)")
				}
			}
		}
		.scrollIndicators(.hidden)
	}

	private func send() {
		guard !chat.isResponding, canSend else { return }
		requestID = UUID()
	}
}

/// Observation boundary for per-token chat streaming. The transcript
/// and composer never subscribe directly to preview text.
private struct BrowserAIChatStreamingResponse: View {
	let chat: BrowserAIChat
	let browser: Browser
	@Binding var hoveredURL: URL?
	@Binding var hoveredLinkSize: CGSize
	@Binding var hoveredLinkShiftPressed: Bool
	let onPreviewChange: () -> Void

	var body: some View {
		Group {
			if chat.isResponding {
				if chat.preview.isEmpty {
					ProgressView("Reading and Answering")
				} else {
					#if os(macOS)
						BrowserAIChatMarkdown(
							text: chat.preview,
							streaming: true,
							open: { browser.openHistoryURL($0, inBackground: false) },
							hover: { url, previous, size, shift in
								if url != nil || hoveredURL == previous {
									hoveredURL = url
									hoveredLinkSize = size
									hoveredLinkShiftPressed = shift
								}
							}
						)
						.frame(maxWidth: .infinity, alignment: .leading)
					#else
						Text((try? AttributedString(markdown: chat.preview)) ?? AttributedString(chat.preview))
							.textSelection(.enabled)
							.environment(\.openURL, OpenURLAction { url in
								browser.openHistoryURL(url, inBackground: false)
								return .handled
							})
					#endif
				}
			}
			if let error = chat.error {
				Text(error)
					.foregroundStyle(.secondary)
					.accessibilityIdentifier("ai-chat-error")
			}
		}
		.onChange(of: chat.preview) { _, _ in onPreviewChange() }
	}
}

#if os(macOS)
	private struct BrowserAIChatMarkdown: NSViewRepresentable {
		let text: String
		let streaming: Bool
		let open: (URL) -> Void
		let hover: (URL?, URL?, CGSize, Bool) -> Void

		func makeNSView(context _: Context) -> ChatMarkdownView {
			let view = ChatMarkdownView()
			view.setContentHuggingPriority(.required, for: .vertical)
			view.setContentCompressionResistancePriority(.required, for: .vertical)
			view.setContentHuggingPriority(.defaultLow, for: .horizontal)
			return view
		}

		func updateNSView(_ view: ChatMarkdownView, context _: Context) {
			view.isStreaming = streaming
			view.hover = hover
			view.linkHandler = { payload, _, _ in
				let url: URL? = switch payload {
					case let .url(url): url
					case let .string(value): URL(string: value)
				}
				if let url {
					open(url)
				}
			}
			if view.displayedText != text {
				view.displayedText = text
				view.setContent(MarkdownContent(markdown: text, theme: view.theme))
			}
		}

		func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChatMarkdownView, context _: Context) -> CGSize? {
			guard let width = proposal.width, width.isFinite else { return nil }
			guard width > 0 else { return .zero }
			return CGSize(width: width, height: ceil(nsView.boundingSize(for: width).height))
		}

		static func dismantleNSView(_ view: ChatMarkdownView, coordinator _: ()) {
			view.stopMonitoring()
		}
	}

	private final class ChatMarkdownView: MarkdownStreamView {
		var displayedText = ""
		var hover: ((URL?, URL?, CGSize, Bool) -> Void)?
		private var hoveredURL: URL?
		private var hoveredSize = CGSize.zero
		private var hoveredShiftPressed = false
		private var hoverTrackingArea: NSTrackingArea?

		override func updateTrackingAreas() {
			if let hoverTrackingArea {
				removeTrackingArea(hoverTrackingArea)
			}
			let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
			addTrackingArea(area)
			hoverTrackingArea = area
			super.updateTrackingAreas()
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			stopMonitoring()
			if window != nil {
				ChatMarkdownEventDispatcher.shared.register(self)
			}
		}

		/// A conversation can have hundreds of Markdown views. A single shared
		/// application-local event handler routes pointer events to just the
		/// view below the cursor instead of one handler per message.
		func stopMonitoring() {
			ChatMarkdownEventDispatcher.shared.unregister(self)
		}

		func updateTrackedHover(for event: NSEvent) {
			let location = event.type == .flagsChanged
				? window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? event.locationInWindow
				: event.locationInWindow
			let point = textLabelView.convert(location, from: nil)
			let region = textLabelView.highlightRegion(at: point)
			updateTrackedHover(
				url: region?.linkURL,
				size: region?.rects.reduce(CGRect.null) { $0.union($1) }.size ?? .zero,
				shift: event.modifierFlags.contains(.shift)
			)
		}

		func clearTrackedHover() {
			updateTrackedHover(url: nil, size: .zero, shift: false)
		}

		private func updateTrackedHover(url: URL?, size: CGSize, shift: Bool) {
			guard url != hoveredURL || size != hoveredSize || shift != hoveredShiftPressed else { return }
			let previous = hoveredURL
			hoveredURL = url
			hoveredSize = size
			hoveredShiftPressed = shift
			hover?(url, previous, size, shift)
		}
	}

	@MainActor
	private final class ChatMarkdownEventDispatcher {
		static let shared = ChatMarkdownEventDispatcher()

		private final class WeakView {
			weak var value: ChatMarkdownView?
			init(_ value: ChatMarkdownView) {
				self.value = value
			}
		}

		private var registered: [ObjectIdentifier: WeakView] = [:]
		private weak var activeView: ChatMarkdownView?
		private var monitor: Any?

		private init() {}

		func register(_ view: ChatMarkdownView) {
			registered = registered.filter { $0.value.value != nil }
			registered[ObjectIdentifier(view)] = WeakView(view)
			guard monitor == nil else { return }
			monitor = NSEvent.addLocalMonitorForEvents(
				matching: [.mouseMoved, .scrollWheel, .flagsChanged]
			) { [weak self] event in
				MainActor.assumeIsolated {
					self?.route(event)
				}
				return event
			}
		}

		func unregister(_ view: ChatMarkdownView) {
			registered.removeValue(forKey: ObjectIdentifier(view))
			if activeView === view {
				activeView?.clearTrackedHover()
				activeView = nil
			}
			if registered.isEmpty, let monitor {
				NSEvent.removeMonitor(monitor)
				self.monitor = nil
			}
		}

		private func route(_ event: NSEvent) {
			// A scroll ends link hover. Flag changes still use the actual
			// pointer position, as the event's window coordinates may be stale.
			let eventWindow = event.window ?? (event.type == .flagsChanged ? activeView?.window : nil)
			var hit: NSView?
			if event.type != .scrollWheel, let window = eventWindow,
			   let content = window.contentView
			{
				let pointInWindow = event.type == .flagsChanged
					? window.convertPoint(fromScreen: NSEvent.mouseLocation)
					: event.locationInWindow
				hit = content.hitTest(content.convert(pointInWindow, from: nil))
			}

			var target: ChatMarkdownView?
			while let view = hit {
				if let markdown = view as? ChatMarkdownView,
				   registered[ObjectIdentifier(markdown)]?.value === markdown
				{
					target = markdown
					break
				}
				hit = view.superview
			}
			if activeView !== target {
				activeView?.clearTrackedHover()
				activeView = target
			}
			target?.updateTrackedHover(for: event)
		}
	}

	private struct BrowserAIChatLinkPreview: View {
		let browser: Browser
		let url: URL
		let linkSize: CGSize
		let shiftPressed: Bool
		@Default(.aiLinkPreviewMode) private var previewMode
		@Default(.aiLinkPreviewShiftOverride) private var shiftOverride
		@Default(.browserSearchConfiguration) private var searchConfiguration
		@Default(.aiLinkPreviews) private var enabled
		@Default(.aiLinkPreviewDelay) private var previewDelay
		@Default(.aiFeaturesEnabled) private var allFeatures
		@State private var summary: BrowserLinkSummaryFeature.Summary?
		@State private var streamedText = ""
		@State private var error: String?
		@State private var visible = false

		private var allowed: Bool {
			allFeatures && !browser.isPrivate && ["https", "http"].contains(url.scheme?.lowercased() ?? "")
				&& BrowserLinkPreviewPolicy.allows(mode: previewMode, enabled: enabled, shiftOverride: shiftOverride,
				                                   shiftPressed: shiftPressed, size: linkSize, sourceURL: nil,
				                                   configuration: .decode(searchConfiguration))
		}

		var body: some View {
			BrowserLinkPreview(url: url, isPrivate: browser.isPrivate)
				.popover(isPresented: $visible) {
					VStack(alignment: .leading, spacing: 8) {
						if let summary {
							Text(summary.title).font(.headline)
							Text(summary.header).bold()
							ForEach(Array(summary.bullets.enumerated()), id: \.offset) { _, bullet in
								Label(bullet.text, systemImage: bullet.symbol)
							}
						} else if !streamedText.isEmpty {
							Text(streamedText)
						} else if let error {
							Text(error).font(.caption).foregroundStyle(.secondary)
						} else {
							ProgressView("Summarizing Page")
						}
					}
					.padding(16)
					.frame(width: 340, alignment: .leading)
					.accessibilityIdentifier("ai-chat-link-preview")
					.task {
						do {
							let result = try await BrowserLinkSummaryFeature.preview(sourceURL: url, destinationURL: url) { snapshot, _ in
								guard !Task.isCancelled else { return }
								streamedText = ["title", "header"].compactMap { BrowserAIOutput.streamedString($0, in: snapshot) }.joined(separator: "\n\n")
							}
							try Task.checkCancellation()
							summary = result.summary
						} catch {
							if !Task.isCancelled {
								self.error = error.localizedDescription
							}
						}
					}
				}
				.task(id: "\(url)|\(previewDelay)|\(allowed)|\(previewMode)|\(shiftOverride)") {
					visible = false
					summary = nil
					streamedText = ""
					error = nil
					guard allowed else { return }
					do {
						try await Task.sleep(for: .seconds(BrowserAISettings.linkPreviewDelay))
						try Task.checkCancellation()
						visible = true
					} catch {}
				}
		}
	}
#endif
