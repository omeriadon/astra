import Defaults
import SwiftUI
import WebKit

#if os(macOS)
	import AppKit

	struct BrowserAIHoverPreview: View {
		let browser: Browser
		let controller: BrowserController
		@Default(.aiLinkPreviews) private var enabled
		@Default(.aiLinkPreviewMode) private var previewMode
		@Default(.aiLinkPreviewShiftOverride) private var shiftOverride
		@Default(.browserSearchConfiguration) private var searchConfiguration
		@Default(.aiLinkPreviewDelay) private var previewDelay
		@Default(.aiFeaturesEnabled) private var allFeatures
		@State private var summary: BrowserLinkSummaryFeature.Summary?
		@State private var page: BrowserAIPageText?
		@State private var error: String?
		@State private var visible = false
		@State private var hovered = false
		@State private var previewRect = CGRect.zero
		@State private var requestTask: Task<Void, Never>?
		@State private var activeKey: String?
		@State private var dismissedKey: String?
		@Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
		@Environment(\.accessibilityReduceMotion) private var reduceMotion

		private var requestKey: String {
			"\(controller.navigationIdentifier)|\(controller.hoveredLinkURL?.absoluteString ?? "")|\(controller.hoveredLinkID)|\(enabled)|\(allFeatures)|\(previewDelay)|\(previewMode)|\(shiftOverride)|\(controller.hoveredLinkShiftPressed)|\(controller.hoveredLinkRect)|\(searchConfiguration)"
		}

		var body: some View {
			GeometryReader { _ in
				Color.clear
					.frame(width: max(1, previewRect.width), height: max(1, previewRect.height))
					.popover(isPresented: Binding(get: { visible }, set: {
						if !$0 {
							dismiss()
						}
					}), arrowEdge: .bottom) {
						previewContent
							.allowsHitTesting(true)
					}
					.position(x: previewRect.midX, y: previewRect.midY)
					.allowsHitTesting(false)
			}
			.onChange(of: controller.navigationIdentifier) { _, _ in dismiss() }
			.onChange(of: enabled) { _, _ in dismiss() }
			.onChange(of: allFeatures) { _, _ in dismiss() }
			.onChange(of: previewMode) { _, _ in dismiss() }
			.onChange(of: shiftOverride) { _, _ in dismiss() }
			.onChange(of: controller.aiPreviewDismissal) { _, _ in dismiss() }
			.task(id: requestKey) { startPreview() }
			.onDisappear { dismiss() }
		}

		private var previewContent: some View {
			VStack(alignment: .leading, spacing: 10) {
				if let summary {
					Text(verbatim: summary.title)
						.font(.title3.weight(.semibold))
						.textSelection(.enabled)
					Text(verbatim: summary.header)
						.bold()
						.textSelection(.enabled)
					ForEach(Array(summary.bullets.enumerated()), id: \.offset) { _, point in
						HStack(alignment: .top, spacing: 8) {
							Image(systemName: point.symbol)
								.frame(width: 20)
								.accessibilityHidden(true)
							Text(verbatim: point.text).textSelection(.enabled)
						}
					}
					if hovered || voiceOver {
						HStack {
							Button("Copy Preview", systemImage: "doc.on.doc") {
								NSPasteboard.general.clearContents()
								NSPasteboard.general.setString(summary.title + "\n\n" + summary.header + "\n\n" + summary.bullets.map { "• " + $0.text }.joined(separator: "\n"), forType: .string)
							}
							.labelStyle(.iconOnly)
							.help("Copy preview text")
							.accessibilityIdentifier("ai-preview-copy")
							if let page {
								Button("Copy Website Link", systemImage: "link") {
									NSPasteboard.general.clearContents()
									NSPasteboard.general.setString(page.url.absoluteString, forType: .string)
								}
								.labelStyle(.iconOnly)
								.help("Copy website link")
								.accessibilityIdentifier("ai-preview-copy-link")
							}
							if browser.showsAISidebar, let page {
								Button("Add to Chat", systemImage: "bubble.left.and.text.bubble.right") { browser.aiChat.addPage(page) }
									.labelStyle(.iconOnly)
									.help("Add full page to chat context")
									.disabled(browser.aiChat.isResponding)
									.accessibilityIdentifier("ai-preview-add-context")
							}
							Spacer(minLength: 0)
						}
						.buttonStyle(.glass)
					}
				} else if let error {
					Label("Preview Unavailable", systemImage: "exclamationmark.bubble")
					Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
				} else {
					ProgressView("Summarizing Page")
				}
			}
			.padding(16)
			.frame(width: 340, alignment: .leading)
			.fixedSize(horizontal: false, vertical: true)
			.onHover { hovered = $0 }
			.accessibilityIdentifier("ai-link-summary")
		}

		private func startPreview() {
			// Moving into the popover clears the page hover; keep its request alive until dismissal.
			if controller.hoveredLinkID.isEmpty, visible {
				return
			}
			requestTask?.cancel()
			activeKey = nil
			controller.updateAIHoverHighlight()
			guard allFeatures, !controller.session.isPrivate, !controller.hoveredLinkID.isEmpty,
			      let sourceURL = controller.url,
			      let url = controller.hoveredLinkURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "")
			else {
				visible = false
				return
			}
			let zoom = controller.webViewIfLoaded?.pageZoom ?? 1
			let rect = controller.hoveredLinkRect.applying(CGAffineTransform(scaleX: zoom, y: zoom))
			guard BrowserLinkPreviewPolicy.allows(mode: previewMode, enabled: enabled, shiftOverride: shiftOverride,
			                                      shiftPressed: controller.hoveredLinkShiftPressed, size: rect.size,
			                                      sourceURL: sourceURL, configuration: .decode(searchConfiguration))
			else {
				visible = false
				return
			}
			let key = requestKey
			guard dismissedKey != key else {
				visible = false
				return
			}
			visible = false
			summary = nil
			page = nil
			error = nil
			activeKey = key
			previewRect = rect
			controller.updateAIHoverHighlight(enabled: true)
			requestTask = Task { @MainActor in
				do {
					try await Task.sleep(for: .seconds(BrowserAISettings.linkPreviewDelay))
					try await BrowserAI.shared.checkAccess(for: BrowserAIFeatureID.linkPreview.model, feature: "Link Previews")
					try Task.checkCancellation()
					previewRect = rect
					visible = true
					controller.updateAIHoverHighlight(enabled: true, thinking: true)
					let model = BrowserAISettings.effectiveModel(BrowserAIFeatureID.linkPreview.model)
					let budget = model == .appleIntelligence ? 1000 : 26000
					let extracted = try await BrowserAIPageLoader().page(at: url)
					let context = try await extracted.limited(to: budget)
					try Task.checkCancellation()
					page = extracted
					let result = try await BrowserAI.shared.performStreaming(BrowserLinkSummaryFeature(), input: .init(sourceURL: sourceURL, destinationURL: url, page: context)) { snapshot in
						guard !Task.isCancelled, activeKey == key else { return }
						let title = BrowserAIOutput.streamedString("title", in: snapshot)
						if summary == nil, title?.isEmpty == false || BrowserAIOutput.streamedString("header", in: snapshot)?.isEmpty == false {
							controller.updateAIHoverHighlight(enabled: true)
						}
						if let partial = BrowserLinkSummaryFeature.streamingSummary(snapshot, title: extracted.title) {
							withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { summary = partial }
						} else if let title, !title.isEmpty {
							summary = .init(title: title, header: "", bullets: [])
						} else if !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
						          !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"), !snapshot.contains("```")
						{
							if summary == nil {
								controller.updateAIHoverHighlight(enabled: true)
							}
							summary = .init(title: extracted.title, header: snapshot, bullets: [])
						}
					}
					try Task.checkCancellation()
					guard activeKey == key else { return }
					controller.updateAIHoverHighlight(enabled: true)
					withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { summary = result }
				} catch {
					if !Task.isCancelled, activeKey == key {
						controller.updateAIHoverHighlight()
						previewRect = rect
						visible = true
						self.error = error.localizedDescription
					}
				}
			}
		}

		private func dismiss() {
			dismissedKey = activeKey ?? requestKey
			requestTask?.cancel()
			requestTask = nil
			activeKey = nil
			controller.updateAIHoverHighlight()
			visible = false
			summary = nil
			page = nil
			error = nil
			hovered = false
		}
	}
#endif
