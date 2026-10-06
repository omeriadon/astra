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
				BrowserAIModelControls(chat: chat, provider: provider)
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
									MarkdownView(message.text)
								}
							}
							.id(message.id)
						}
						if chat.isResponding {
							if chat.preview.isEmpty {
								ProgressView("Reading and Answering")
							} else {
								MarkdownView(chat.preview)
							}
						}
						if let error = chat.error {
							Text(error)
								.foregroundStyle(.secondary)
								.accessibilityIdentifier("ai-chat-error")
						}
						Color.clear.frame(height: 1).id("chat-bottom")
					}
					.padding(.horizontal, 12)
				}
				.onChange(of: chat.messages.count) { _, _ in reader.scrollTo("chat-bottom", anchor: .bottom) }
				.onChange(of: chat.preview) { _, _ in reader.scrollTo("chat-bottom", anchor: .bottom) }
			}
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
			if visible {
				chat.includeCurrentTab(in: browser)
			}
		}
		.task { await history.load() }
		.fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.image, .pdf, .text, .data], allowsMultipleSelection: true) { result in
			switch result {
				case let .success(urls): Task { await chat.importFiles(urls) }
				case let .failure(error): chat.reportImportError(error)
			}
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
