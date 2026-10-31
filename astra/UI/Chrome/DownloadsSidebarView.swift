import QuickLook
import SwiftUI

/// Observation stays at the SwiftUI boundary; cells, selection, scrolling, and
/// menus are entirely native. The manager is shared with the browser chrome.
struct DownloadsSidebarView: View {
	let manager: BrowserDownloadManager
	let theme: BrowserTheme
	@State private var previewURL: URL?
	@State private var scopedPreviewURL: URL?

	var body: some View {
		NativeDownloadsList(
			manager: manager,
			items: manager.items,
			suggestedNames: manager.aiSuggestedNames,
			theme: theme,
			onPreview: preview
		)
		.quickLookPreview($previewURL)
		.onChange(of: previewURL) { previous, current in
			#if os(macOS)
				if let previous, previous != current, scopedPreviewURL == previous {
					manager.endPreview(at: previous)
					scopedPreviewURL = nil
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

	private func preview(_ id: UUID) {
		guard let item = manager.items.first(where: { $0.id == id && $0.status == .completed }),
		      previewURL != item.fileURL else { return }
		#if os(macOS)
			guard manager.beginPreview(id) else { return }
			if let scopedPreviewURL {
				manager.endPreview(at: scopedPreviewURL)
			}
			scopedPreviewURL = item.fileURL
		#endif
		previewURL = item.fileURL
	}
}

#if os(macOS)
	import AppKit
	import UniformTypeIdentifiers

	/// NSTableView requires NSPasteboardWriting rather than SwiftUI's NSItemProvider.
	/// This adapter fulfills native file promises through the existing async,
	/// security-scope-aware download drag provider. A userInfo strong reference
	/// keeps the delegate alive if the sidebar closes before the drop completes.
	/// NSItemProvider's callback is @Sendable, while AppKit's promise completion
	/// is not. This immutable box forwards the single terminal result safely.
	nonisolated private final class DownloadFilePromiseCompletion: @unchecked Sendable {
		private let handler: ((any Error)?) -> Void

		init(_ handler: @escaping ((any Error)?) -> Void) {
			self.handler = handler
		}

		func finish(_ error: (any Error)?) {
			handler(error)
		}
	}

	private final class DownloadNativeFilePromise: NSObject, NSFilePromiseProviderDelegate {
		let source: NSItemProvider
		let name: String
		let type: String
		private let worker = OperationQueue()

		init(source: NSItemProvider, name: String, type: String) {
			self.source = source
			self.name = name
			self.type = type
			super.init()
			worker.maxConcurrentOperationCount = 1
			worker.qualityOfService = .userInitiated
		}

		func operationQueue(for _: NSFilePromiseProvider) -> OperationQueue {
			worker
		}

		func filePromiseProvider(_: NSFilePromiseProvider, fileNameForType _: String) -> String {
			name
		}

		func filePromiseProvider(_: NSFilePromiseProvider,
		                         writePromiseTo url: URL, completionHandler: @escaping ((any Error)?) -> Void)
		{
			let completion = DownloadFilePromiseCompletion(completionHandler)
			source.loadFileRepresentation(forTypeIdentifier: type) { sourceURL, error in
				guard let sourceURL else {
					completion.finish(error ?? CocoaError(.fileNoSuchFile))
					return
				}
				do {
					try FileManager.default.copyItem(at: sourceURL, to: url)
					completion.finish(nil)
				} catch {
					completion.finish(error)
				}
			}
		}
	}

	private final class DownloadActionButton: NSButton {
		var run: (() -> Void)?
		init(symbol: String, label: String, run: @escaping () -> Void) {
			super.init(frame: .zero)
			self.run = run
			image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
			imagePosition = .imageOnly
			isBordered = false
			bezelStyle = .inline
			setAccessibilityLabel(label)
			target = self
			action = #selector(activate)
		}

		required init?(coder _: NSCoder) {
			nil
		}

		@objc private func activate() {
			run?()
		}
	}

	nonisolated private final class DownloadMenuItem: NSMenuItem {
		var run: (() -> Void)?
		init(_ title: String, symbol: String, run: @escaping () -> Void) {
			super.init(title: title, action: nil, keyEquivalent: "")
			self.run = run
			image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
			target = self
			action = #selector(activate)
		}

		@available(*, unavailable)
		required init(coder _: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		@objc private func activate() {
			run?()
		}
	}

	private final class DownloadProgressSegments: NSView {
		var fractions: [Double] = [] {
			didSet { needsDisplay = true }
		}

		var foreground: NSColor = .controlTextColor {
			didSet { needsDisplay = true }
		}

		var tint: NSColor = .controlAccentColor {
			didSet { needsDisplay = true }
		}

		override var isFlipped: Bool {
			true
		}

		override func draw(_ dirtyRect: NSRect) {
			super.draw(dirtyRect)
			guard !fractions.isEmpty else { return }
			let gap: CGFloat = 3
			let width = max(0, (bounds.width - gap * CGFloat(fractions.count - 1)) / CGFloat(fractions.count))
			for (index, fraction) in fractions.enumerated() {
				let x = CGFloat(index) * (width + gap)
				let segment = NSRect(x: x, y: 0, width: width, height: bounds.height)
				foreground.withAlphaComponent(0.18).setFill()
				NSBezierPath(roundedRect: segment, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
				let progress = min(max(fraction.isFinite ? fraction : 0, 0), 1)
				tint.setFill()
				NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: width * progress, height: bounds.height),
				             xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
			}
		}
	}

	private final class DownloadNativeCell: NSTableCellView {
		private let glyph = NSImageView()
		private let titleLabel = NSTextField(wrappingLabelWithString: "")
		private let hostLabel = NSTextField(labelWithString: "")
		private let summaryLabel = NSTextField(wrappingLabelWithString: "")
		private let finishLabel = NSTextField(labelWithString: "")
		private let progress = DownloadProgressSegments()
		private let controls = NSStackView()
		private let details = NSStackView()
		private var name = ""

		override init(frame frameRect: NSRect) {
			super.init(frame: frameRect)
			wantsLayer = true
			glyph.imageScaling = .scaleProportionallyDown
			glyph.setContentHuggingPriority(.required, for: .horizontal)
			titleLabel.font = .systemFont(ofSize: 13)
			titleLabel.maximumNumberOfLines = 2
			titleLabel.lineBreakMode = .byTruncatingTail
			hostLabel.font = .systemFont(ofSize: 11)
			hostLabel.textColor = .secondaryLabelColor
			hostLabel.lineBreakMode = .byTruncatingTail
			summaryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
			summaryLabel.textColor = .secondaryLabelColor
			finishLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
			finishLabel.textColor = .secondaryLabelColor
			controls.orientation = .horizontal
			controls.spacing = 8
			details.orientation = .vertical
			details.alignment = .leading
			details.spacing = 3
			for element in [titleLabel, hostLabel, summaryLabel, finishLabel, progress, controls] {
				details.addArrangedSubview(element)
			}
			progress.translatesAutoresizingMaskIntoConstraints = false
			progress.heightAnchor.constraint(equalToConstant: 7).isActive = true
			progress.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true
			let row = NSStackView(views: [glyph, details])
			row.orientation = .horizontal
			row.alignment = .top
			row.spacing = 9
			row.translatesAutoresizingMaskIntoConstraints = false
			addSubview(row)
			NSLayoutConstraint.activate([
				row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
				row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
				row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
				row.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
				glyph.widthAnchor.constraint(equalToConstant: 18),
				glyph.heightAnchor.constraint(equalToConstant: 18),
			])
		}

		required init?(coder _: NSCoder) {
			nil
		}

		func configure(_ item: BrowserDownload, suggestedName: String?, manager: BrowserDownloadManager, theme: BrowserTheme) {
			let title = suggestedName ?? item.name
			name = title
			let ink = NSColor(theme.foregroundColor)
			titleLabel.textColor = ink
			hostLabel.textColor = ink.withAlphaComponent(0.65)
			summaryLabel.textColor = ink.withAlphaComponent(0.65)
			finishLabel.textColor = ink.withAlphaComponent(0.65)
			glyph.contentTintColor = ink
			titleLabel.stringValue = title
			glyph.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
			hostLabel.stringValue = item.sourceURL?.host ?? ""
			hostLabel.isHidden = item.sourceURL?.host == nil
			summaryLabel.stringValue = item.statusSummary
			let active = [.downloading, .paused, .finalizing].contains(item.status)
			finishLabel.isHidden = !active || item.estimatedFinish == nil
			if let finish = item.estimatedFinish {
				finishLabel.stringValue = "Estimated finish: " + finish.formatted(date: .omitted, time: .shortened)
			}
			progress.isHidden = !active
			progress.foreground = NSColor(theme.foregroundColor)
			progress.tint = NSColor(theme.progressColor)
			progress.fractions = item.segments?.isEmpty == false
				? item.segments!.map {
					let size = max(1, $0.end - $0.start + 1)
					return $0.completed ? 1 : Double($0.received) / Double(size)
				}
				: [item.progress]
			progress.setAccessibilityLabel("Download progress")
			progress.setAccessibilityValue("\(Int(min(max(item.progress, 0), 1) * 100)) percent")
			for view in controls.arrangedSubviews {
				controls.removeArrangedSubview(view)
				view.removeFromSuperview()
			}
			func button(_ label: String, _ image: String, _ action: @escaping () -> Void) {
				let control = DownloadActionButton(symbol: image, label: label, run: action)
				control.identifier = NSUserInterfaceItemIdentifier("download-\(label.lowercased())-\(item.id.uuidString)")
				control.contentTintColor = ink
				controls.addArrangedSubview(control)
			}
			if item.status == .downloading {
				button("Pause", "pause.fill") { manager.pause(item.id) }
			} else if item.canResume {
				button("Resume", "play.fill") { manager.resume(item.id) }
			} else if item.canRetry {
				button("Restart", "arrow.clockwise") { manager.retry(item.id) }
			}
			if active {
				button("Cancel", "xmark.circle") { manager.cancel(item.id) }
			}
			controls.isHidden = controls.arrangedSubviews.isEmpty
			setAccessibilityElement(true)
			setAccessibilityLabel("\(item.name), \(item.sourceURL?.host ?? "unknown website"), \(item.statusSummary)")
			setAccessibilityIdentifier("download-\(item.id.uuidString)")
		}
	}

	private final class DownloadNativeRow: NSTableRowView {
		override func drawSelection(in _: NSRect) {
			NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
			NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 6, yRadius: 6).fill()
		}
	}

	private final class DownloadNativeTable: NSTableView {
		var contextMenu: ((Int) -> NSMenu?)?
		var previewSelection: (() -> Void)?
		var deleteSelection: (() -> Void)?
		override func menu(for event: NSEvent) -> NSMenu? {
			let index = row(at: convert(event.locationInWindow, from: nil))
			return contextMenu?(index) ?? super.menu(for: event)
		}

		override func keyDown(with event: NSEvent) {
			if event.charactersIgnoringModifiers == " ", !selectedRowIndexes.isEmpty {
				previewSelection?()
			} else if event.keyCode == 51 || event.keyCode == 117, !selectedRowIndexes.isEmpty {
				deleteSelection?()
			} else {
				super.keyDown(with: event)
			}
		}
	}

	private struct NativeDownloadsList: NSViewRepresentable {
		let manager: BrowserDownloadManager
		let items: [BrowserDownload]
		let suggestedNames: [UUID: String]
		let theme: BrowserTheme
		let onPreview: (UUID) -> Void

		func makeCoordinator() -> Coordinator {
			Coordinator()
		}

		func makeNSView(context: Context) -> NSScrollView {
			let scroll = NSScrollView()
			scroll.drawsBackground = false
			scroll.contentView.drawsBackground = false
			scroll.hasVerticalScroller = true
			scroll.hasHorizontalScroller = false
			scroll.scrollerStyle = .overlay
			scroll.autohidesScrollers = true
			scroll.automaticallyAdjustsContentInsets = false
			scroll.contentInsets = NSEdgeInsets(top: 35, left: 0, bottom: 48, right: 0)
			let table = DownloadNativeTable()
			table.backgroundColor = .clear
			table.frame = scroll.contentView.bounds
			table.autoresizingMask = [.width]
			table.headerView = nil
			table.intercellSpacing = NSSize(width: 0, height: 6)
			table.allowsMultipleSelection = true
			table.selectionHighlightStyle = .regular
			table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
			let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("download"))
			column.resizingMask = .autoresizingMask
			table.addTableColumn(column)
			table.delegate = context.coordinator
			table.dataSource = context.coordinator
			table.target = context.coordinator
			table.doubleAction = #selector(Coordinator.openSelected)
			table.contextMenu = { [weak coordinator = context.coordinator] index in coordinator?.menu(row: index) }
			table.previewSelection = { [weak coordinator = context.coordinator] in coordinator?.previewSelected() }
			table.deleteSelection = { [weak coordinator = context.coordinator] in coordinator?.deleteSelected() }
			scroll.documentView = table
			context.coordinator.table = table
			context.coordinator.scroll = scroll
			let empty = NSStackView()
			empty.orientation = .vertical
			empty.alignment = .centerX
			empty.spacing = 8
			let image = NSImageView(image: NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) ?? NSImage())
			image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
			let title = NSTextField(labelWithString: "No Downloads")
			title.font = .systemFont(ofSize: 15, weight: .semibold)
			title.textColor = .secondaryLabelColor
			empty.addArrangedSubview(image)
			empty.addArrangedSubview(title)
			empty.translatesAutoresizingMaskIntoConstraints = false
			scroll.addSubview(empty)
			NSLayoutConstraint.activate([
				empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
				empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
			])
			context.coordinator.empty = empty
			return scroll
		}

		func updateNSView(_: NSScrollView, context: Context) {
			context.coordinator.update(self)
		}

		static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
			coordinator.table?.delegate = nil
			coordinator.table?.dataSource = nil
			coordinator.table = nil
			coordinator.scroll = nil
			coordinator.empty = nil
			view.documentView = nil
		}

		@MainActor
		final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
			weak var table: DownloadNativeTable?
			weak var scroll: NSScrollView?
			weak var empty: NSStackView?
			private var model: NativeDownloadsList?
			private var selectedIDs: Set<UUID> = []

			func update(_ new: NativeDownloadsList) {
				guard let table else { return }
				let oldItems = model?.items
				let oldIDs = oldItems?.map(\.id)
				let changed = model?.items != new.items || model?.suggestedNames != new.suggestedNames || model?.theme != new.theme
				model = new
				empty?.isHidden = !new.items.isEmpty
				guard changed else { return }
				if oldIDs != new.items.map(\.id) {
					let selected = selectedIDs
					table.reloadData()
					let indexes = IndexSet(new.items.indices.filter { selected.contains(new.items[$0].id) })
					table.selectRowIndexes(indexes, byExtendingSelection: false)
				} else {
					let visible = table.rows(in: table.visibleRect)
					if visible.length > 0 {
						for row in visible.location ..< (visible.location + visible.length) {
							guard new.items.indices.contains(row) else { continue }
							if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? DownloadNativeCell {
								cell.configure(new.items[row], suggestedName: new.suggestedNames[new.items[row].id],
								               manager: new.manager, theme: new.theme)
							}
						}
					}
					let old = oldItems
					let resized = IndexSet(new.items.indices.filter { index in
						guard let previous = old?[safe: index] else { return true }
						let current = new.items[index]
						return previous.status != current.status
							|| (previous.estimatedFinish != nil) != (current.estimatedFinish != nil)
							|| previous.statusSummary.components(separatedBy: "\n").count
							!= current.statusSummary.components(separatedBy: "\n").count
					})
					if !resized.isEmpty {
						table.noteHeightOfRows(withIndexesChanged: resized)
					}
				}
				if let scroll {
					scroll.documentView?.needsDisplay = true
				}
			}

			func numberOfRows(in _: NSTableView) -> Int {
				model?.items.count ?? 0
			}

			func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
				guard let item = model?.items[safe: row] else { return 75 }
				let active = [.downloading, .paused, .finalizing].contains(item.status)
				let hasActions = active || item.canResume || item.canRetry
				let host = item.sourceURL?.host == nil ? 0 : 16
				let summary = item.statusSummary.components(separatedBy: "\n").count
				return CGFloat(8 + 19 + host + max(16, min(summary, 4) * 14)
					+ (active ? 13 : 0) + (item.estimatedFinish == nil ? 0 : 16)
					+ (hasActions ? 22 : 0) + 8)
			}

			func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
				DownloadNativeRow()
			}

			func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
				guard let model, model.items.indices.contains(row) else { return nil }
				let id = NSUserInterfaceItemIdentifier("native-download-row")
				let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? DownloadNativeCell) ?? DownloadNativeCell(frame: .zero)
				cell.identifier = id
				let item = model.items[row]
				cell.configure(item, suggestedName: model.suggestedNames[item.id], manager: model.manager, theme: model.theme)
				return cell
			}

			func tableViewSelectionDidChange(_: Notification) {
				guard let table, let model else { return }
				selectedIDs = Set(table.selectedRowIndexes.compactMap { model.items[safe: $0]?.id })
			}

			@objc func openSelected() {
				guard let model, let row = table?.clickedRow, let item = model.items[safe: row], item.status == .completed else { return }
				model.manager.open(item.id)
			}

			func previewSelected() {
				guard let model, let item = model.items.first(where: { selectedIDs.contains($0.id) && $0.status == .completed }) else { return }
				model.onPreview(item.id)
			}

			func deleteSelected() {
				guard let model else { return }
				for id in selectedIDs {
					model.manager.moveToTrash(id)
				}
				selectedIDs.removeAll()
			}

			func menu(row: Int) -> NSMenu? {
				guard let model, let item = model.items[safe: row] else { return nil }
				let manager = model.manager
				let menu = NSMenu()
				func add(_ title: String, _ symbol: String, _ act: @escaping () -> Void) {
					menu.addItem(DownloadMenuItem(title, symbol: symbol, run: act))
				}
				add("Show in Folder", "folder") { manager.revealInFolder(item.id) }
				if item.status == .completed {
					add("Open", "arrow.up.right.square") { manager.open(item.id) }
					if item.destinationIsFileScoped != true || item.fileAccessBookmark != nil {
						add("Quick Look", "eye") { model.onPreview(item.id) }
					}
					if item.renamedByAppleIntelligence {
						add("Revert Name", "arrow.uturn.backward") { manager.revertName(item.id) }
					}
					add("Move to Bin", "trash") { manager.moveToTrash(item.id) }
					add("Remove from Downloads", "trash") { manager.delete(item.id) }
				} else {
					if item.canResume {
						add("Resume", "arrow.clockwise") { manager.resume(item.id) }
					} else if item.canRetry {
						add("Retry", "arrow.clockwise") { manager.retry(item.id) }
					}
					if item.status == .downloading {
						add("Pause", "pause.fill") { manager.pause(item.id) }
					}
					if item.status == .downloading || item.status == .paused {
						add("Cancel Download", "xmark.circle") { manager.cancel(item.id) }
					} else {
						add("Delete", "trash") { manager.delete(item.id) }
					}
				}
				return menu
			}

			func tableView(_: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
				guard edge == .trailing, let model, let item = model.items[safe: row] else { return [] }
				let manager = model.manager
				let active = [.downloading, .paused, .finalizing].contains(item.status)
				return [NSTableViewRowAction(style: .destructive,
				                             title: active ? "Cancel" : (item.status == .completed ? "Move to Bin" : "Remove Download"))
				{ _, _ in
					if active {
						manager.cancel(item.id)
					} else if item.status == .completed {
						manager.moveToTrash(item.id)
					} else {
						manager.delete(item.id)
					}
					}]
			}

			func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
				guard let model, let item = model.items[safe: row], item.status == .completed, let source = model.manager.dragProvider(item.id) else { return nil }
				let type = (UTType(filenameExtension: item.fileURL.pathExtension) ?? .data).identifier
				let delegate = DownloadNativeFilePromise(source: source, name: item.name, type: type)
				let promise = NSFilePromiseProvider(fileType: type, delegate: delegate)
				promise.userInfo = delegate
				return promise
			}
		}
	}

	private extension Array {
		subscript(safe index: Int) -> Element? {
			indices.contains(index) ? self[index] : nil
		}
	}

#elseif os(iOS)
	import UIKit

	private final class DownloadUIKitCell: UITableViewCell {
		private let glyph = UIImageView()
		private let titleLabel = UILabel()
		private let hostLabel = UILabel()
		private let summaryLabel = UILabel()
		private let finishLabel = UILabel()
		private let bars = UIStackView()
		private let buttons = UIStackView()
		private let details = UIStackView()

		override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
			super.init(style: style, reuseIdentifier: reuseIdentifier)
			backgroundColor = .clear
			contentView.backgroundColor = .clear
			let selected = UIView()
			selected.backgroundColor = UIColor.tintColor.withAlphaComponent(0.15)
			selectedBackgroundView = selected
			titleLabel.font = .preferredFont(forTextStyle: .subheadline)
			titleLabel.numberOfLines = 2
			hostLabel.font = .preferredFont(forTextStyle: .caption1)
			hostLabel.textColor = .secondaryLabel
			summaryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
			summaryLabel.textColor = .secondaryLabel
			summaryLabel.numberOfLines = 0
			finishLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
			finishLabel.textColor = .secondaryLabel
			glyph.contentMode = .scaleAspectFit
			glyph.tintColor = .label
			details.axis = .vertical
			details.alignment = .fill
			details.spacing = 3
			bars.axis = .horizontal
			bars.distribution = .fillEqually
			bars.spacing = 3
			buttons.axis = .horizontal
			buttons.alignment = .leading
			buttons.spacing = 8
			for subview in [titleLabel, hostLabel, summaryLabel, finishLabel, bars, buttons] {
				details.addArrangedSubview(subview)
			}
			let line = UIStackView(arrangedSubviews: [glyph, details])
			line.axis = .horizontal
			line.alignment = .top
			line.spacing = 9
			line.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(line)
			NSLayoutConstraint.activate([
				line.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
				line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
				line.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
				line.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
				glyph.widthAnchor.constraint(equalToConstant: 18),
				glyph.heightAnchor.constraint(equalToConstant: 18),
				bars.heightAnchor.constraint(equalToConstant: 7),
			])
		}

		required init?(coder _: NSCoder) {
			nil
		}

		func configure(_ item: BrowserDownload, name: String?, manager: BrowserDownloadManager, theme: BrowserTheme) {
			let ink = UIColor(theme.foregroundColor)
			glyph.image = UIImage(systemName: item.symbol)
			glyph.tintColor = ink
			titleLabel.textColor = ink
			hostLabel.textColor = ink.withAlphaComponent(0.65)
			summaryLabel.textColor = ink.withAlphaComponent(0.65)
			finishLabel.textColor = ink.withAlphaComponent(0.65)
			titleLabel.text = name ?? item.name
			hostLabel.text = item.sourceURL?.host
			hostLabel.isHidden = item.sourceURL?.host == nil
			summaryLabel.text = item.statusSummary
			let active = [.downloading, .paused, .finalizing].contains(item.status)
			finishLabel.isHidden = !active || item.estimatedFinish == nil
			if let finish = item.estimatedFinish {
				finishLabel.text = "Estimated finish: " + finish.formatted(date: .omitted, time: .shortened)
			}
			for bar in bars.arrangedSubviews {
				bars.removeArrangedSubview(bar); bar.removeFromSuperview()
			}
			if active {
				let fractions: [Double] = item.segments?.isEmpty == false
					? item.segments!.map { segment in
						let total = max(1, segment.end - segment.start + 1)
						return segment.completed ? 1 : Double(segment.received) / Double(total)
					}
					: [item.progress]
				for fraction in fractions {
					let bar = UIProgressView(progressViewStyle: .default)
					bar.progress = Float(min(max(fraction.isFinite ? fraction : 0, 0), 1))
					bar.progressTintColor = UIColor(theme.progressColor)
					bar.trackTintColor = UIColor(theme.foregroundColor).withAlphaComponent(0.18)
					bars.addArrangedSubview(bar)
				}
			}
			bars.isHidden = !active
			for button in buttons.arrangedSubviews {
				buttons.removeArrangedSubview(button); button.removeFromSuperview()
			}
			func add(_ label: String, _ symbol: String, _ operation: @escaping () -> Void) {
				let button = UIButton(type: .system)
				button.setImage(UIImage(systemName: symbol), for: .normal)
				button.tintColor = ink
				button.accessibilityLabel = label
				button.accessibilityIdentifier = "download-\(label.lowercased())-\(item.id.uuidString)"
				button.addAction(UIAction { _ in operation() }, for: .touchUpInside)
				buttons.addArrangedSubview(button)
			}
			if item.status == .downloading {
				add("Pause", "pause.fill") { manager.pause(item.id) }
			} else if item.canResume {
				add("Resume", "play.fill") { manager.resume(item.id) }
			} else if item.canRetry {
				add("Restart", "arrow.clockwise") { manager.retry(item.id) }
			}
			if active {
				add("Cancel", "xmark.circle") { manager.cancel(item.id) }
			}
			buttons.isHidden = buttons.arrangedSubviews.isEmpty
			accessibilityLabel = "\(item.name), \(item.sourceURL?.host ?? "unknown website"), \(item.statusSummary)"
			accessibilityIdentifier = "download-\(item.id.uuidString)"
		}
	}

	private struct NativeDownloadsList: UIViewRepresentable {
		let manager: BrowserDownloadManager
		let items: [BrowserDownload]
		let suggestedNames: [UUID: String]
		let theme: BrowserTheme
		let onPreview: (UUID) -> Void

		func makeCoordinator() -> Coordinator {
			Coordinator()
		}

		func makeUIView(context: Context) -> UITableView {
			let table = UITableView(frame: .zero, style: .plain)
			table.backgroundColor = .clear
			table.separatorStyle = .none
			table.rowHeight = UITableView.automaticDimension
			table.estimatedRowHeight = 110
			table.register(DownloadUIKitCell.self, forCellReuseIdentifier: "download")
			table.delegate = context.coordinator
			table.dataSource = context.coordinator
			context.coordinator.table = table
			return table
		}

		func updateUIView(_: UITableView, context: Context) {
			context.coordinator.update(self)
		}

		static func dismantleUIView(_ table: UITableView, coordinator: Coordinator) {
			table.delegate = nil
			table.dataSource = nil
			coordinator.table = nil
		}

		@MainActor
		final class Coordinator: NSObject, UITableViewDelegate, UITableViewDataSource {
			weak var table: UITableView?
			private var model: NativeDownloadsList?
			func update(_ next: NativeDownloadsList) {
				let previous = model
				model = next
				guard previous?.items != next.items || previous?.suggestedNames != next.suggestedNames || previous?.theme != next.theme else { return }
				if previous?.items.map(\.id) != next.items.map(\.id) {
					table?.reloadData()
				} else if let table {
					for cell in table.visibleCells {
						guard let path = table.indexPath(for: cell), let item = next.items[safe: path.row] else { continue }
						(cell as? DownloadUIKitCell)?.configure(item, name: next.suggestedNames[item.id], manager: next.manager, theme: next.theme)
					}
				}
				table?.backgroundView = next.items.isEmpty ? emptyView : nil
			}

			private var emptyView: UIView {
				let label = UILabel()
				label.text = "No Downloads"
				label.textAlignment = .center
				label.textColor = .secondaryLabel
				let icon = UIImageView(image: UIImage(systemName: "arrow.down.circle"))
				icon.tintColor = .secondaryLabel
				icon.contentMode = .scaleAspectFit
				let stack = UIStackView(arrangedSubviews: [icon, label])
				stack.axis = .vertical
				stack.alignment = .center
				stack.spacing = 8
				let container = UIView()
				stack.translatesAutoresizingMaskIntoConstraints = false
				container.addSubview(stack)
				NSLayoutConstraint.activate([
					icon.heightAnchor.constraint(equalToConstant: 44),
					icon.widthAnchor.constraint(equalToConstant: 44),
					stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
					stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
				])
				return container
			}

			func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
				model?.items.count ?? 0
			}

			func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
				let cell = tableView.dequeueReusableCell(withIdentifier: "download", for: indexPath) as! DownloadUIKitCell
				if let model, let item = model.items[safe: indexPath.row] {
					cell.configure(item, name: model.suggestedNames[item.id], manager: model.manager, theme: model.theme)
				}
				return cell
			}

			func tableView(_: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
				guard let model, let item = model.items[safe: indexPath.row] else { return nil }
				let active = [.downloading, .paused, .finalizing].contains(item.status)
				let action = UIContextualAction(style: .destructive, title: active ? "Cancel" : "Remove Download") { _, _, finish in
					if active {
						model.manager.cancel(item.id)
					} else {
						model.manager.delete(item.id)
					}
					finish(true)
				}
				return UISwipeActionsConfiguration(actions: [action])
			}

			func tableView(_: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
				guard let model, let item = model.items[safe: indexPath.row] else { return nil }
				let manager = model.manager
				return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
					var actions: [UIMenuElement] = []
					func add(_ title: String, _ symbol: String, _ action: @escaping () -> Void) {
						actions.append(UIAction(title: title, image: UIImage(systemName: symbol)) { _ in action() })
					}
					if item.status == .completed {
						if item.destinationIsFileScoped != true || item.fileAccessBookmark != nil {
							add("Quick Look", "eye") { model.onPreview(item.id) }
						}
						if item.renamedByAppleIntelligence {
							add("Revert Name", "arrow.uturn.backward") { manager.revertName(item.id) }
						}
					} else if item.canResume {
						add("Resume", "arrow.clockwise") { manager.resume(item.id) }
					} else if item.canRetry {
						add("Retry", "arrow.clockwise") { manager.retry(item.id) }
					}
					if item.status == .downloading {
						add("Pause", "pause.fill") { manager.pause(item.id) }
					}
					if item.status == .downloading || item.status == .paused {
						add("Cancel Download", "xmark.circle") { manager.cancel(item.id) }
					} else {
						add(item.status == .completed ? "Remove from Downloads" : "Delete", "trash") { manager.delete(item.id) }
					}
					return UIMenu(children: actions)
				}
			}
		}
	}

	private extension Array {
		subscript(safe index: Int) -> Element? {
			indices.contains(index) ? self[index] : nil
		}
	}
#endif
