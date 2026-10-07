import QuickLook
import SwiftUI

struct DownloadsSidebarView: View {
	let manager: BrowserDownloadManager
	let theme: BrowserTheme
	@State private var previewURL: URL?
	@State private var scopedPreviewURL: URL?

	var body: some View {
		GeometryReader { geometry in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 5) {
					#if os(macOS)
						Text("Downloads")
							.font(.headline)
							.padding(.horizontal, 8)
							.padding(.bottom, 6)
					#endif

					ForEach(manager.items) { item in
						DownloadRowView(
							item: item,
							manager: manager,
							theme: theme,
							previewURL: $previewURL,
							scopedPreviewURL: $scopedPreviewURL
						)
						.equatable()
					}
				}
				.padding(.horizontal, BrowserChromeMetrics.shellEdgePadding)
				#if os(macOS)
					.padding(.top, 35)
				#else
					.padding(.vertical, 16)
				#endif
					.frame(minHeight: geometry.size.height, alignment: .top)
				#if os(macOS)
					.background {
						WindowDragBackground()
					}
				#endif
			}
		}
		.overlay {
			if manager.items.isEmpty {
				DownloadsEmptyView()
			}
		}
		.quickLookPreview($previewURL)
		.onChange(of: previewURL) { previousURL, currentURL in
			#if os(macOS)
				if let previousURL, previousURL != currentURL {
					if scopedPreviewURL == previousURL {
						manager.endPreview(at: previousURL)
						scopedPreviewURL = nil
					}
				}
			#endif
		}
		.onDisappear {
			#if os(macOS)
				if let scopedPreviewURL {
					manager.endPreview(at: scopedPreviewURL)
					self.scopedPreviewURL = nil
				}
			#endif
		}
		.accessibilityIdentifier("downloads-list")
	}
}

private struct DownloadsEmptyView: View {
	var body: some View {
		ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle")
			.frame(maxWidth: .infinity)
	}
}

private struct DownloadRowView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let item: BrowserDownload
	let manager: BrowserDownloadManager
	let theme: BrowserTheme
	@Binding var previewURL: URL?
	@Binding var scopedPreviewURL: URL?

	var body: some View {
		HStack(alignment: .top, spacing: 9) {
			Image(systemName: item.symbol)
				.frame(width: 18)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 3) {
				Text(manager.aiSuggestedNames[item.id] ?? item.name)
					.contentTransition(.opacity)
					.animation(reduceMotion ? nil : .smooth(duration: 0.2), value: manager.aiSuggestedNames[item.id] ?? item.name)
					.lineLimit(2)
					.font(.subheadline)
				if let host = item.sourceURL?.host {
					Text(host)
						.lineLimit(1)
						.font(.caption)
						.opacity(0.65)
				}
				if item.status == .downloading || item.status == .paused {
					Text(item.statusSummary)
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
					if let finish = item.estimatedFinish {
						Text("Estimated finish: \(finish.formatted(date: .omitted, time: .shortened))")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
					}
					Text(item.segments.map { "\($0.count) download pieces" } ?? "Single connection")
						.font(.caption)
						.foregroundStyle(.secondary)
					HStack(spacing: 3) {
						if let segments = item.segments, !segments.isEmpty {
							ForEach(segments.indices, id: \.self) { index in
								let segment = segments[index]
								let size = Double(segment.end - segment.start + 1)
								SegmentProgressBar(
									progress: segment.completed ? 1 : Double(segment.received) / size,
									theme: theme
								)
							}
						} else {
							SegmentProgressBar(progress: item.progress, theme: theme)
						}
					}
					.frame(height: 7)
					.accessibilityElement(children: .ignore)
					.accessibilityLabel("Download progress")
					.accessibilityValue("\(Int(item.progress * 100)) percent")
				} else {
					Text(item.statusSummary)
						.font(.caption)
						.lineLimit(2)
						.opacity(0.65)
				}
				HStack(spacing: 8) {
					if item.status == .downloading {
						Button("Pause", systemImage: "pause.fill") {
							manager.pause(item.id)
						}
						.accessibilityIdentifier("download-pause-\(item.id.uuidString)")
					} else if item.canResume {
						Button("Resume", systemImage: "play.fill") {
							manager.resume(item.id)
						}
						.accessibilityIdentifier("download-resume-\(item.id.uuidString)")
					} else if item.canRetry {
						Button("Restart", systemImage: "arrow.clockwise") {
							manager.retry(item.id)
						}
						.accessibilityIdentifier("download-restart-\(item.id.uuidString)")
					}
					if item.status == .downloading || item.status == .paused {
						Button("Cancel", systemImage: "xmark.circle", role: .destructive) {
							manager.cancel(item.id)
						}
						.accessibilityIdentifier("download-cancel-\(item.id.uuidString)")
					}
				}
				.buttonStyle(.borderless)
				.font(.caption)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(8)
		.contentShape(Rectangle())
		.contextMenu {
			#if os(macOS)
				Button("Show in Folder", systemImage: "folder") {
					manager.revealInFolder(item.id)
				}
				.accessibilityIdentifier("download-reveal-\(item.id.uuidString)")
			#endif
			if item.status == .completed {
				#if os(macOS)
					Button("Open", systemImage: "arrow.up.right.square") {
						manager.open(item.id)
					}
					.accessibilityIdentifier("download-open-\(item.id.uuidString)")
				#endif
				if item.destinationIsFileScoped != true || item.fileAccessBookmark != nil {
					Button("Quick Look", systemImage: "eye") {
						guard previewURL != item.fileURL else { return }
						#if os(macOS)
							guard manager.beginPreview(item.id) else { return }
							if let scopedPreviewURL {
								manager.endPreview(at: scopedPreviewURL)
							}
							scopedPreviewURL = item.fileURL
						#endif
						previewURL = item.fileURL
					}
					.accessibilityIdentifier("download-preview-\(item.id.uuidString)")
				}
				if item.renamedByAppleIntelligence {
					Button("Revert Name", systemImage: "arrow.uturn.backward") {
						manager.revertName(item.id)
					}
					.accessibilityIdentifier("download-revert-name-\(item.id.uuidString)")
				}
			} else if item.canResume {
				Button("Resume", systemImage: "arrow.clockwise") {
					manager.resume(item.id)
				}
				.accessibilityIdentifier("download-resume-\(item.id.uuidString)")
			} else if item.canRetry {
				Button("Retry", systemImage: "arrow.clockwise") {
					manager.retry(item.id)
				}
				.accessibilityLabel("Retry download")
				.accessibilityIdentifier("download-retry-\(item.id.uuidString)")
			}
			if item.status == .downloading || item.status == .paused {
				if item.status == .downloading {
					Button("Pause", systemImage: "pause.fill") {
						manager.pause(item.id)
					}
					.accessibilityIdentifier("download-pause-menu-\(item.id.uuidString)")
				}
				Button("Cancel Download", systemImage: "xmark.circle", role: .destructive) {
					manager.cancel(item.id)
				}
				.accessibilityLabel("Cancel download")
				.accessibilityIdentifier("download-cancel-\(item.id.uuidString)")
			} else {
				Button(
					item.status == .completed ? "Remove from Downloads" : "Delete",
					systemImage: "trash",
					role: .destructive
				) {
					manager.delete(item.id)
				}
				.accessibilityIdentifier("download-remove-\(item.id.uuidString)")
			}
		}
		#if os(macOS)
		.onDrag {
			manager.dragProvider(item.id) ?? NSItemProvider()
		}
		.accessibilityHint(item.status == .completed ? "Drag to copy the completed file" : "")
		#endif
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(item.name), \(item.sourceURL?.host ?? "unknown website"), \(item.statusSummary)")
		.accessibilityIdentifier("download-\(item.id.uuidString)")
	}
}

private struct SegmentProgressBar: View {
	let progress: Double
	let theme: BrowserTheme

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .leading) {
				Capsule()
					.fill(theme.foregroundColor.opacity(0.18))
				Capsule()
					.fill(theme.progressColor)
					.frame(width: geometry.size.width * min(max(progress, 0), 1))
			}
		}
		.accessibilityHidden(true)
	}
}

extension DownloadRowView: Equatable {
	static func == (lhs: DownloadRowView, rhs: DownloadRowView) -> Bool {
		lhs.item == rhs.item
			&& lhs.manager === rhs.manager
			&& lhs.theme == rhs.theme
			&& lhs.previewURL == rhs.previewURL
			&& lhs.scopedPreviewURL == rhs.scopedPreviewURL
	}
}
