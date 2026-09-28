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
						ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle")
							.frame(maxWidth: .infinity)
					} else {
						ForEach(manager.items) { item in
							row(item)
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

	private func row(_ item: BrowserDownload) -> some View {
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
								progressBar(segment.completed ? 1 : Double(segment.received) / size)
							}
						} else {
							progressBar(item.progress)
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

	private func progressBar(_ progress: Double) -> some View {
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
