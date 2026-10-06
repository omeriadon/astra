import Defaults
import SwiftUI
import WebKit

#if os(macOS)
	import AppKit

	struct BrowserAIHoverPreview: View {
		let browser: Browser
		let controller: BrowserController
		@Default(.aiLinkPreviews) private var enabled
		@State private var summary: BrowserLinkSummaryFeature.Summary?
		@State private var page: BrowserAIPageText?
		@State private var error: String?
		@State private var visible = false
		@State private var hovered = false
		@State private var previewRect = CGRect.zero
		@State private var measuredSize = CGSize(width: 340, height: 100)
		@State private var dismissedKey: String?
		@State private var dismissalGeneration = 0
		@Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

		private var requestKey: String {
			"\(controller.navigationIdentifier)|\(controller.hoveredLinkURL?.absoluteString ?? "")|\(controller.hoveredLinkID)|\(enabled)"
		}

		var body: some View {
			GeometryReader { geometry in
				if visible {
					let width = min(340, max(0, geometry.size.width - 16))
					let x = min(max(8, previewRect.minX), max(8, geometry.size.width - width - 8))
					let desiredY = previewRect.maxY + 8
					let y = desiredY + measuredSize.height < geometry.size.height - 8
						? desiredY : max(8, previewRect.minY - measuredSize.height - 8)
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
					.frame(width: width, alignment: .leading)
					.fixedSize(horizontal: false, vertical: true)
					.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
					.onHover { hovered = $0 }
					.background { BrowserAIPreviewDismissMonitor(dismiss: dismiss) }
					.onGeometryChange(for: CGSize.self) { $0.size } action: { measuredSize = $0 }
					.offset(x: x, y: y)
					.accessibilityIdentifier("ai-link-summary")
				}
			}
			.onChange(of: controller.navigationIdentifier) { _, _ in dismiss() }
			.onChange(of: enabled) {
				_, value in if !value {
					dismiss()
				}
			}
			.onChange(of: controller.aiPreviewDismissal) { _, _ in dismiss() }
			.task(id: "\(requestKey)|\(dismissalGeneration)") {
				controller.updateAIHoverHighlight()
				guard enabled, !controller.session.isPrivate, !controller.hoveredLinkID.isEmpty,
				      let url = controller.hoveredLinkURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "")
				else {
					if summary == nil {
						visible = false
					}
					return
				}
				let key = requestKey
				guard dismissedKey != key else { return }
				do {
					try await Task.sleep(for: .seconds(2))
					try BrowserAI.shared.checkAccess(for: BrowserAIFeatureID.linkPreview.model)
					previewRect = controller.hoveredLinkRect.applying(CGAffineTransform(scaleX: controller.webViewIfLoaded?.pageZoom ?? 1, y: controller.webViewIfLoaded?.pageZoom ?? 1))
					summary = nil
					page = nil
					error = nil
					visible = true
					let model = BrowserAISettings.effectiveModel(BrowserAIFeatureID.linkPreview.model)
					let budget = model == .appleIntelligence ? 1000 : 26000
					let extracted = try await BrowserAIPageLoader().page(at: url)
					let context = try await extracted.limited(to: budget)
					let result = try await BrowserAI.shared.perform(BrowserLinkSummaryFeature(), input: context)
					if !Task.isCancelled, requestKey == key, dismissedKey != key {
						page = extracted
						summary = result
					}
				} catch {
					if !Task.isCancelled, requestKey == key, dismissedKey != key {
						previewRect = controller.hoveredLinkRect
						visible = true
						self.error = error.localizedDescription
					}
				}
			}
		}

		private func dismiss() {
			dismissedKey = requestKey
			dismissalGeneration += 1
			visible = false
			summary = nil
			page = nil
			error = nil
			hovered = false
		}
	}

	private struct BrowserAIPreviewDismissMonitor: NSViewRepresentable {
		let dismiss: () -> Void

		func makeNSView(context _: Context) -> PreviewDismissView {
			let view = PreviewDismissView()
			view.dismiss = dismiss
			return view
		}

		func updateNSView(_ view: PreviewDismissView, context _: Context) {
			view.dismiss = dismiss
		}

		static func dismantleNSView(_ view: PreviewDismissView, coordinator _: ()) {
			view.stop()
		}
	}

	private final class PreviewDismissView: NSView {
		var dismiss: (() -> Void)?
		private var monitor: Any?

		override func hitTest(_: NSPoint) -> NSView? {
			nil
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			stop()
			guard window != nil else { return }
			monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
				MainActor.assumeIsolated {
					guard let self else { return }
					if event.window !== self.window {
						self.dismiss?()
						return
					}
					let point = self.convert(event.locationInWindow, from: nil)
					if event.type == .scrollWheel || !self.bounds.contains(point) {
						self.dismiss?()
					}
				}
				return event
			}
		}

		func stop() {
			if let monitor {
				NSEvent.removeMonitor(monitor)
			}
			monitor = nil
		}
	}
#endif
