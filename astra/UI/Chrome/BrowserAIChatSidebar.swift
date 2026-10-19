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
	@State private var historySelection = UUID()
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
		BrowserAIChatTranscript(
			browser: browser,
			chat: chat,
			retry: { send() },
			hover: { url, previous, size, shift in
				if url != nil || hoveredURL == previous {
					hoveredURL = url
					hoveredLinkSize = size
					hoveredLinkShiftPressed = shift
				}
			}
		)
		.safeAreaBar(edge: .top) {
			VStack(spacing: 12) {
				HStack(spacing: 8) {
					Text(chat.title)
						.font(.headline)
						.contentTransition(.opacity)
						.animation(.easeInOut(duration: 0.3), value: chat.title)
						.lineLimit(1)
						.accessibilityIdentifier("ai-chat-title")
					Spacer(minLength: 0)
					Button("Recent Chats", systemImage: "clock.arrow.circlepath") { showsHistory.toggle() }
						.labelStyle(.iconOnly)
						.frame(width: 28, height: 28)
						.contentShape(RoundedRectangle(cornerRadius: 8))
						.foregroundStyle(.secondary)
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
											let token = UUID()
											historySelection = token
											Task { @MainActor in
												let currentID = chat.id
												let draft = chat.draft
												if let saved = await history.conversation(conversation.id), !chat.isResponding, !chat.isImporting, chat.id == currentID, chat.draft == draft, historySelection == token {
													chat.select(saved)
												}
											}
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
							}
							.listStyle(.sidebar)
							.scrollContentBackground(.hidden)
							.frame(width: 320, height: 360)
						}
					Button("New Chat", systemImage: "square.and.pencil", action: chat.clear)
						.labelStyle(.iconOnly)
						.frame(width: 28, height: 28)
						.contentShape(RoundedRectangle(cornerRadius: 8))
						.foregroundStyle(.secondary)
						.disabled(chat.isResponding || chat.isImporting)
						.accessibilityIdentifier("ai-chat-new")
				}
				.buttonStyle(.plain)
				.padding([.top, .horizontal], 12)
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
				if chat.messages.isEmpty, !chat.isResponding, chat.error == nil {
					Button("Summarise", systemImage: "text.alignleft") {
						chat.includeCurrentTab(in: browser)
						chat.draft = "Summarise the current page."
						send()
					}
					.buttonStyle(.plain)
					.foregroundStyle(.secondary)
					.disabled(chat.isResponding || !chat.draft.isEmpty)
					.accessibilityIdentifier("ai-chat-summarise")
				}
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
				if !chat.linkedTabIDs.isEmpty || !chat.pendingPages.isEmpty {
					VStack(spacing: 6) {
						ForEach(chat.linkedTabIDs, id: \.self) { id in
							let tab = chat.availableTabs(in: browser).first { $0.id == id }
							pageContextRow(title: tab?.title ?? "Closed Page", subtitle: tab?.currentURL?.host(), identifier: "ai-chat-unlink-\(id.uuidString)") {
								chat.linkedTabIDs.removeAll { $0 == id }
							}
						}
						ForEach(chat.pendingPages) { page in
							pageContextRow(title: page.title, subtitle: page.url.host(), identifier: "ai-chat-remove-preview-context") {
								chat.pendingPages.removeAll { $0.id == page.id }
							}
						}
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
					.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
					.onSubmit { send() }
					.disabled(chat.isResponding)
					.accessibilityLabel("Message AI. Type at to link a page.")
					.accessibilityIdentifier("ai-chat-input")
				HStack {
					Button("Attach Images or Files", systemImage: "paperclip") { showsFileImporter = true }
						.labelStyle(.iconOnly)
						.buttonStyle(.plain)
						.frame(width: 28, height: 28)
						.foregroundStyle(.secondary)
						.disabled(chat.isResponding || chat.isImporting)
						.accessibilityIdentifier("ai-chat-attach")
					if isVisible, BrowserAICLI.isProviderDetected(provider) {
						BrowserAIModelControls(
							selectedProvider: $chat.selectedProvider,
							selectedModelID: $chat.selectedModelID,
							selectedReasoning: $chat.selectedReasoning,
							provider: provider,
							isDisabled: chat.isResponding,
							initialModelID: provider == "codex" ? Defaults[.aiCodexModel] : Defaults[.aiClaudeModel],
							initialReasoning: provider == "codex" ? Defaults[.aiCodexReasoning] : Defaults[.aiClaudeReasoning]
						)
						.layoutPriority(-1)
					}
					Spacer()
					if chat.isResponding {
						Button("Stop Answer", systemImage: "stop.fill") { requestID = nil }
							.labelStyle(.iconOnly)
							.buttonStyle(.plain)
							.frame(width: 28, height: 28)
							.background(Color.primary.opacity(0.08), in: Circle())
							.accessibilityIdentifier("ai-chat-stop")
					} else {
						Button("Send Message", systemImage: "arrow.up", role: .confirm, action: send)
							.labelStyle(.iconOnly)
							.buttonStyle(.plain)
							.frame(width: 28, height: 28)
							.background(browser.theme.tabColor.opacity(canSend ? 0.25 : 0.08), in: Circle())
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
		.onChange(of: chat.error) { _, error in
			if let error {
				browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: error)
			}
		}
		.onChange(of: history.error) { _, error in
			if let error {
				browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: error)
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

	private func pageContextRow(title: String, subtitle: String?, identifier: String, remove: @escaping () -> Void) -> some View {
		HStack(spacing: 9) {
			Image(systemName: "globe").foregroundStyle(.secondary)
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(.caption.weight(.medium)).lineLimit(1)
				if let subtitle {
					Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
				}
			}
			Spacer(minLength: 4)
			Button("Remove Page Context", systemImage: "xmark", action: remove)
				.labelStyle(.iconOnly)
				.font(.caption2)
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
				.disabled(chat.isResponding)
				.accessibilityIdentifier(identifier)
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
	}

	private func attachmentRow(_ attachments: [BrowserAIAttachment], removable: Bool) -> some View {
		ScrollView(.horizontal) {
			HStack(alignment: .top, spacing: 8) {
				ForEach(attachments) { attachment in
					VStack(spacing: 4) {
						Group {
							if let data = attachment.image?.data {
								#if os(macOS)
									if let image = BrowserAIThumbnailCache.image(id: attachment.id, data: data) {
										Image(nsImage: image).resizable().scaledToFit()
									}
								#else
									if let image = BrowserAIThumbnailCache.image(id: attachment.id, data: data) {
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

extension BrowserAIAction {
	var chatSystemImage: String {
		switch self {
			case .createSpaceFolder, .createBookmarkFolder: "folder.badge.plus"
			case .createBookmark: "bookmark"
			case .deleteBookmark: "bookmark.slash"
			case .openTab: "plus.rectangle.on.rectangle"
			case .closeTab: "xmark.rectangle"
			case .pinTab: "pin"
			case .favouriteTab: "star"
			case .moveTabToFolder: "folder"
			case .renameTab: "pencil"
			case .selectTab: "rectangle.on.rectangle"
			case .listTabs: "list.bullet.rectangle"
			case .githubAccount: "person.crop.circle"
			case .moveTabsToSpace: "arrow.left.arrow.right"
			case .readPage: "doc.text"
			case .webSearch: "magnifyingglass"
			case .listTools: "wrench.and.screwdriver"
			case .getPageStructure: "list.bullet.indent"
			case .augmentWebsite: "wand.and.stars"
		}
	}
}

#if os(macOS)
	final class ChatMarkdownView: MarkdownStreamView {
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
			if unsafe window != nil {
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
				? unsafe window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? event.locationInWindow
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
			let eventWindow = unsafe event.window ?? (event.type == .flagsChanged ? activeView?.window : nil)
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
				hit = unsafe view.superview
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
						} else if error != nil {
							Label("Preview Unavailable", systemImage: "exclamationmark.triangle")
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
								browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: error.localizedDescription)
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

/// Reuse the same native image object across transcript/composer reflows. Image
/// bytes and display dimensions are unchanged, preserving existing sampling.
@MainActor enum BrowserAIThumbnailCache {
	#if os(macOS)
		typealias NativeImage = NSImage
	#else
		typealias NativeImage = UIImage
	#endif
	private static let cache: NSCache<NSString, NativeImage> = {
		let value = NSCache<NSString, NativeImage>()
		value.countLimit = 32
		value.totalCostLimit = 64 * 1024 * 1024
		return value
	}()

	static func image(id: UUID, data: Data) -> NativeImage? {
		let key = id.uuidString as NSString
		if let cached = cache.object(forKey: key) {
			return cached
		}
		guard let image = NativeImage(data: data) else { return nil }
		let pixels = Double(image.size.width) * Double(image.size.height) * 4
		let cost = pixels.isFinite ? Int(min(max(pixels, Double(data.count)), Double(Int.max / 2))) : data.count
		cache.setObject(image, forKey: key, cost: cost)
		return image
	}
}
