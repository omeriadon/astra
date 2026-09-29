import QuickLook
import SwiftUI

struct DownloadsSidebarView: View {
	let manager: BrowserDownloadManager
	let theme: BrowserTheme
	@State private var previewURL: URL?

	var body: some View {
		GeometryReader { geometry in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 5) {
					Text("Downloads")
						.font(.headline)
						.padding(.horizontal, 8)
						.padding(.bottom, 6)

					if manager.items.isEmpty {
						DownloadsEmptyView()
					} else {
						ForEach(manager.items) { item in
							DownloadRowView(
								item: item,
								manager: manager,
								theme: theme,
								previewURL: $previewURL
							)
							.equatable()
						}
					}
				}
				.padding(.horizontal, BrowserChromeMetrics.shellEdgePadding)
				.padding(.top, 35)
				.frame(minHeight: geometry.size.height, alignment: .top)
				#if os(macOS)
					.background {
						WindowDragBackground()
					}
				#endif
			}
		}
		.quickLookPreview($previewURL)
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
	let item: BrowserDownload
	let manager: BrowserDownloadManager
	let theme: BrowserTheme
	@Binding var previewURL: URL?

	var body: some View {
		HStack(alignment: .top, spacing: 9) {
			Image(systemName: item.symbol)
				.frame(width: 18)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 3) {
				Text(item.name)
					.lineLimit(2)
					.font(.subheadline)
				if let host = item.sourceURL?.host {
					Text(host)
						.lineLimit(1)
						.font(.caption)
						.opacity(0.65)
				}
				if item.status == .downloading {
					HStack(spacing: 2) {
						if let segments = item.segments {
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
					.frame(height: 5)
					.accessibilityElement(children: .ignore)
					.accessibilityLabel("Download progress")
					.accessibilityValue("\(Int(item.progress * 100)) percent")
				} else if let error = item.errorMessage {
					Text(error)
						.font(.caption)
						.lineLimit(2)
						.opacity(0.65)
				}
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
			#endif
			if item.status == .completed {
				#if os(macOS)
					Button("Open", systemImage: "arrow.up.right.square") {
						manager.open(item.id)
					}
				#endif
				Button("Quick Look", systemImage: "eye") {
					previewURL = item.fileURL
				}
				if item.renamedByAppleIntelligence {
					Button("Revert Name", systemImage: "arrow.uturn.backward") {
						manager.revertName(item.id)
					}
				}
			} else if item.status == .paused, item.resumeData != nil {
				Button("Resume", systemImage: "arrow.clockwise") {
					manager.resume(item.id)
				}
			}
			Button("Delete", systemImage: "trash", role: .destructive) {
				manager.delete(item.id)
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(item.name), \(item.sourceURL?.host ?? "unknown website"), \(item.status.rawValue)")
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
	}
}
