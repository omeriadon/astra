import SwiftUI

#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif

/// Value snapshots keep the native tables independent of Browser observation and
/// prevent each table cell from acquiring its own SwiftUI observation tree.
struct BrowserNativeLibrarySection: Equatable {
	let title: String
	let rows: [BrowserNativeLibraryRow]
	var emptyMessage: String?
}

struct BrowserNativeLibraryRow: Identifiable, Equatable {
	enum Kind: Equatable {
		case bookmark, readingList, history
	}

	let id: String
	let recordID: UUID
	let kind: Kind
	let title: String
	let detail: String
	let url: URL
	let symbol: String
	var isFavorite = false
	var isRead = false
	var canAddToReadingList = false
}

enum BrowserNativeLibraryAction: Int, CaseIterable {
	case editBookmark, toggleFavorite, addToReadingList, deleteBookmark
	case openOffline, toggleRead, removeReadingList
	case removePageHistory, removeHistoryVisit

	var title: String {
		switch self {
			case .editBookmark: "Edit Bookmark"
			case .toggleFavorite: "Toggle Favorite"
			case .addToReadingList: "Add to Reading List"
			case .deleteBookmark: "Delete Bookmark"
			case .openOffline: "Open Offline Copy"
			case .toggleRead: "Toggle Read"
			case .removeReadingList: "Remove from Reading List"
			case .removePageHistory: "Remove This Page from History"
			case .removeHistoryVisit: "Remove from History"
		}
	}

	var symbol: String {
		switch self {
			case .editBookmark: "pencil"
			case .toggleFavorite: "star"
			case .addToReadingList: "text.badge.plus"
			case .deleteBookmark, .removeReadingList, .removePageHistory, .removeHistoryVisit: "trash"
			case .openOffline: "arrow.down.circle"
			case .toggleRead: "checkmark.circle"
		}
	}

	var isDestructive: Bool {
		switch self {
			case .deleteBookmark, .removeReadingList, .removePageHistory, .removeHistoryVisit: true
			default: false
		}
	}

	static func available(for row: BrowserNativeLibraryRow) -> [Self] {
		switch row.kind {
			case .bookmark: [.editBookmark, .toggleFavorite, .addToReadingList, .deleteBookmark]
			case .readingList: [.openOffline, .toggleRead, .removeReadingList]
			case .history: [.removePageHistory, .removeHistoryVisit]
		}
	}

	func label(for row: BrowserNativeLibraryRow) -> String {
		switch self {
			case .toggleFavorite: row.isFavorite ? "Remove from Favorites" : "Add to Favorites"
			case .toggleRead: row.isRead ? "Mark as Unread" : "Mark as Read"
			default: title
		}
	}

	func icon(for row: BrowserNativeLibraryRow) -> String {
		switch self {
			case .toggleFavorite: row.isFavorite ? "star.slash" : "star"
			case .toggleRead: row.isRead ? "circle" : "checkmark.circle"
			default: symbol
		}
	}
}

#if os(macOS)
	/// Native AppKit scrolling, section headers, reusable rows, hover affordances
	/// and context menus. The outer SwiftUI page still owns its existing top bar,
	/// sheets, confirmation dialogs and asynchronous search/indexing.
	struct BrowserNativeLibraryList: NSViewRepresentable {
		let sections: [BrowserNativeLibrarySection]
		let canReorder: Bool
		var isReordering = false
		let open: (BrowserNativeLibraryRow, Bool) -> Void
		let action: (BrowserNativeLibraryRow, BrowserNativeLibraryAction) -> Void
		let reorder: (String, [UUID]) -> Void

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
			let table = NSTableView()
			table.headerView = nil
			table.backgroundColor = .clear
			table.usesAlternatingRowBackgroundColors = false
			table.selectionHighlightStyle = .none
			table.rowSizeStyle = .custom
			table.intercellSpacing = .zero
			table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
			let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library-content"))
			column.resizingMask = .autoresizingMask
			table.addTableColumn(column)
			table.delegate = context.coordinator
			table.dataSource = context.coordinator
			table.registerForDraggedTypes([Coordinator.dragType])
			table.setDraggingSourceOperationMask(.move, forLocal: true)
			scroll.documentView = table
			context.coordinator.table = table
			return scroll
		}

		func updateNSView(_: NSScrollView, context: Context) {
			context.coordinator.update(self)
		}

		static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
			coordinator.table?.dataSource = nil
			coordinator.table?.delegate = nil
			coordinator.table = nil
			coordinator.parent = nil
			scroll.documentView = nil
		}

		@MainActor
		final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
			enum Entry: Equatable {
				case header(String)
				case empty(String)
				case item(section: String, row: BrowserNativeLibraryRow)
			}

			static let dragType = NSPasteboard.PasteboardType("com.omeriadon.astra.library-bookmark")
			weak var table: NSTableView?
			var parent: BrowserNativeLibraryList?
			var entries: [Entry] = []

			func update(_ new: BrowserNativeLibraryList) {
				let newEntries: [Entry] = new.sections.flatMap { section in
					[.header(section.title)] +
						(section.rows.isEmpty ? section.emptyMessage.map { [.empty($0)] } ?? [] :
							section.rows.map { .item(section: section.title, row: $0) })
				}
				parent = new
				guard newEntries != entries else { return }
				// Keep the scroll position stable when search results or sync change.
				let origin = table?.enclosingScrollView?.contentView.bounds.origin ?? .zero
				entries = newEntries
				table?.reloadData()
				if let scroll = table?.enclosingScrollView {
					scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, origin.y)))
					scroll.reflectScrolledClipView(scroll.contentView)
				}
			}

			func numberOfRows(in _: NSTableView) -> Int {
				entries.count
			}

			func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
				guard entries.indices.contains(row) else { return 0 }
				return switch entries[row] {
					case .header: 34
					case .empty: 32
					case .item: 46
				}
			}

			func tableView(_: NSTableView, shouldSelectRow _: Int) -> Bool {
				false
			}

			func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row index: Int) -> NSView? {
				guard entries.indices.contains(index) else { return nil }
				switch entries[index] {
					case let .header(title):
						let view = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("section"), owner: self) as? BrowserNativeLibraryMacLabel)
							?? BrowserNativeLibraryMacLabel(frame: .zero)
						view.identifier = NSUserInterfaceItemIdentifier("section")
						view.setText(title, isHeader: true)
						return view
					case let .empty(message):
						let view = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("empty"), owner: self) as? BrowserNativeLibraryMacLabel)
							?? BrowserNativeLibraryMacLabel()
						view.identifier = NSUserInterfaceItemIdentifier("empty")
						view.setText(message, isHeader: false)
						return view
					case let .item(_, row):
						let view = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("library-row"), owner: self) as? BrowserNativeLibraryMacRow)
							?? BrowserNativeLibraryMacRow(frame: .zero)
						view.identifier = NSUserInterfaceItemIdentifier("library-row")
						view.configure(row: row, open: { [weak self] background in self?.parent?.open(row, background) },
						               action: { [weak self] selected in self?.parent?.action(row, selected) })
						return view
				}
			}

			func tableView(_: NSTableView, pasteboardWriterForRow index: Int) -> (any NSPasteboardWriting)? {
				guard parent?.canReorder == true, entries.indices.contains(index),
				      case let .item(_, row) = entries[index], row.kind == .bookmark else { return nil }
				let item = NSPasteboardItem()
				item.setString(row.recordID.uuidString, forType: Self.dragType)
				return item
			}

			func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo,
			               proposedRow index: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation
			{
				guard parent?.canReorder == true, (info.draggingSource as? NSTableView) === tableView, operation == .above,
				      let idString = info.draggingPasteboard.string(forType: Self.dragType),
				      let id = UUID(uuidString: idString),
				      let source = entries.first(where: {
					if case let .item(_, row) = $0 {
						return row.recordID == id && row.kind == .bookmark
					}
					return false
				      }),
				      case let .item(folder, _) = source else { return [] }
				if index == entries.count {
					return .move
				}
				if index > 0, case let .item(previousFolder, _) = entries[index - 1], previousFolder == folder {
					return .move // Includes the gap before the next section header.
				}
				guard entries.indices.contains(index) else { return [] }
				if case let .item(destinationFolder, row) = entries[index],
				   destinationFolder == folder, row.kind == .bookmark
				{
					return .move
				}
				return []
			}

			func tableView(_: NSTableView, acceptDrop info: any NSDraggingInfo,
			               row index: Int, dropOperation _: NSTableView.DropOperation) -> Bool
			{
				guard parent?.canReorder == true,
				      let idString = info.draggingPasteboard.string(forType: Self.dragType),
				      let id = UUID(uuidString: idString),
				      let section = parent?.sections.first(where: { $0.rows.contains { $0.recordID == id && $0.kind == .bookmark } }) else { return false }
				var ids = section.rows.map(\.recordID)
				guard ids.contains(id) else { return false }
				ids.removeAll { $0 == id }
				if entries.indices.contains(index), case let .item(folder, destination) = entries[index],
				   folder == section.title, let insertion = ids.firstIndex(of: destination.recordID)
				{
					ids.insert(id, at: insertion)
				} else {
					ids.append(id)
				}
				parent?.reorder(section.title, ids)
				return true
			}
		}
	}

	private final class BrowserNativeLibraryMacLabel: NSView {
		private let label = NSTextField(labelWithString: "")
		override var isFlipped: Bool {
			true
		}

		override init(frame: NSRect) {
			super.init(frame: frame)
			label.isSelectable = false
			label.lineBreakMode = .byTruncatingTail
			addSubview(label)
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		func setText(_ text: String, isHeader: Bool) {
			label.stringValue = text
			label.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 12)
			label.textColor = .secondaryLabelColor
			needsLayout = true
		}

		override func layout() {
			super.layout()
			label.frame = NSRect(x: 24, y: 9, width: max(0, bounds.width - 48), height: 19)
		}
	}

	private final class BrowserNativeLibraryMacRow: NSView {
		private let icon = NSImageView()
		private let title = NSTextField(labelWithString: "")
		private let detail = NSTextField(labelWithString: "")
		private let openButton = NSButton()
		private let backgroundButton = NSButton()
		private var tracking: NSTrackingArea?
		private var onOpen: ((Bool) -> Void)?
		private var onAction: ((BrowserNativeLibraryAction) -> Void)?
		private var current: BrowserNativeLibraryRow?
		private var hovered = false
		override var isFlipped: Bool {
			true
		}

		override init(frame: NSRect) {
			super.init(frame: frame)
			for label in [title, detail] {
				label.isSelectable = false
				label.maximumNumberOfLines = 1
				label.lineBreakMode = .byTruncatingTail
			}
			title.font = .systemFont(ofSize: 13)
			detail.font = .systemFont(ofSize: 11)
			detail.textColor = .secondaryLabelColor
			icon.imageScaling = .scaleProportionallyUpOrDown
			openButton.isBordered = false
			openButton.title = ""
			openButton.target = self
			openButton.action = #selector(openNormally)
			backgroundButton.isBordered = false
			backgroundButton.image = NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: "Open in Background")
			backgroundButton.imagePosition = .imageOnly
			backgroundButton.target = self
			backgroundButton.action = #selector(openInBackground)
			for view in [icon, title, detail, openButton, backgroundButton] {
				addSubview(view)
			}
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		func configure(row: BrowserNativeLibraryRow, open: @escaping (Bool) -> Void,
		               action: @escaping (BrowserNativeLibraryAction) -> Void)
		{
			if current?.id != row.id {
				hovered = false
			}
			current = row
			onOpen = open
			onAction = action
			title.stringValue = row.title
			detail.stringValue = row.detail
			icon.image = FaviconStore.shared.nativeImage(for: row.url)
				?? NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil)
			openButton.setAccessibilityLabel("Open \(row.title)")
			openButton.identifier = NSUserInterfaceItemIdentifier(row.id)
			backgroundButton.setAccessibilityLabel("Open \(row.title) in background")
			backgroundButton.identifier = NSUserInterfaceItemIdentifier("\(row.id)-background")
			backgroundButton.isHidden = !hovered
			needsLayout = true
		}

		override func layout() {
			super.layout()
			let accessoryWidth: CGFloat = hovered ? 35 : 0
			icon.frame = NSRect(x: 25, y: 15, width: 16, height: 16)
			let textWidth = max(0, bounds.width - 60 - accessoryWidth)
			title.frame = NSRect(x: 49, y: 5, width: textWidth, height: 20)
			detail.frame = NSRect(x: 49, y: 25, width: textWidth, height: 16)
			openButton.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - accessoryWidth), height: bounds.height)
			backgroundButton.frame = NSRect(x: max(0, bounds.width - 39), y: 8, width: 31, height: 30)
		}

		override func updateTrackingAreas() {
			super.updateTrackingAreas()
			if let tracking {
				removeTrackingArea(tracking)
			}
			let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeInKeyWindow],
			                          owner: self, userInfo: nil)
			addTrackingArea(area)
			tracking = area
		}

		override func mouseEntered(with _: NSEvent) {
			hovered = true; backgroundButton.isHidden = false; needsLayout = true
		}

		override func mouseExited(with _: NSEvent) {
			hovered = false; backgroundButton.isHidden = true; needsLayout = true
		}

		@objc private func openNormally() {
			onOpen?(false)
		}

		@objc private func openInBackground() {
			onOpen?(true)
		}

		override func menu(for _: NSEvent) -> NSMenu? {
			guard let current else { return nil }
			let menu = NSMenu()
			menu.autoenablesItems = false
			for action in BrowserNativeLibraryAction.available(for: current) {
				let item = NSMenuItem(title: action.label(for: current), action: #selector(performMenuAction(_:)), keyEquivalent: "")
				item.tag = action.rawValue
				item.target = self
				item.image = NSImage(systemSymbolName: action.icon(for: current), accessibilityDescription: nil)
				if action == .addToReadingList {
					item.isEnabled = current.canAddToReadingList
				}
				if action == .addToReadingList {
					item.identifier = NSUserInterfaceItemIdentifier("bookmark-add-reading-list-\(current.recordID.uuidString)")
				}
				if action == .openOffline {
					item.identifier = NSUserInterfaceItemIdentifier("reading-open-offline-\(current.recordID.uuidString)")
				}
				if action == .toggleRead {
					item.identifier = NSUserInterfaceItemIdentifier("reading-toggle-read-\(current.recordID.uuidString)")
				}
				if action == .removeReadingList {
					item.identifier = NSUserInterfaceItemIdentifier("reading-remove-\(current.recordID.uuidString)")
				}
				menu.addItem(item)
			}
			return menu
		}

		@objc private func performMenuAction(_ sender: NSMenuItem) {
			guard let action = BrowserNativeLibraryAction(rawValue: sender.tag) else { return }
			onAction?(action)
		}
	}
#endif

#if os(iOS)
	/// UIKit owns list layout, reuse, context menus, swipes and drag reordering.
	/// Insets and headers use UITableView's native inset-grouped style.
	struct BrowserNativeLibraryList: UIViewRepresentable {
		let sections: [BrowserNativeLibrarySection]
		let canReorder: Bool
		var isReordering = false
		let open: (BrowserNativeLibraryRow, Bool) -> Void
		let action: (BrowserNativeLibraryRow, BrowserNativeLibraryAction) -> Void
		let reorder: (String, [UUID]) -> Void

		func makeCoordinator() -> Coordinator {
			Coordinator()
		}

		func makeUIView(context: Context) -> UITableView {
			let table = UITableView(frame: .zero, style: .insetGrouped)
			table.backgroundColor = .clear
			table.separatorStyle = .singleLine
			table.register(UITableViewCell.self, forCellReuseIdentifier: "library-row")
			table.dataSource = context.coordinator
			table.delegate = context.coordinator
			return table
		}

		func updateUIView(_ table: UITableView, context: Context) {
			context.coordinator.parent = self
			if context.coordinator.sections != sections {
				context.coordinator.sections = sections
				// Do not destroy the user's scroll position on sync or incremental search.
				let offset = table.contentOffset
				table.reloadData()
				table.layoutIfNeeded()
				if !sections.isEmpty {
					table.setContentOffset(CGPoint(x: 0, y: max(-table.adjustedContentInset.top, min(offset.y, max(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.height)))), animated: false)
				}
			}
			if table.isEditing != isReordering {
				table.setEditing(isReordering, animated: false)
				table.reloadData() // Replace background buttons with the native reorder handles.
			}
		}

		static func dismantleUIView(_ table: UITableView, coordinator: Coordinator) {
			table.dataSource = nil
			table.delegate = nil
			coordinator.parent = nil
		}

		@MainActor
		final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
			var parent: BrowserNativeLibraryList?
			var sections: [BrowserNativeLibrarySection] = []

			func numberOfSections(in _: UITableView) -> Int {
				sections.count
			}

			func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
				max(1, sections[section].rows.count)
			}

			func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
				sections[section].title
			}

			private func row(at path: IndexPath) -> BrowserNativeLibraryRow? {
				sections[path.section].rows.indices.contains(path.row) ? sections[path.section].rows[path.row] : nil
			}

			func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
				let cell = tableView.dequeueReusableCell(withIdentifier: "library-row", for: path)
				guard let row = row(at: path) else {
					var config = UIListContentConfiguration.cell()
					config.text = sections[path.section].emptyMessage ?? ""
					config.textProperties.color = .secondaryLabel
					cell.contentConfiguration = config
					cell.accessoryView = nil
					cell.selectionStyle = .none
					return cell
				}
				var content = UIListContentConfiguration.subtitleCell()
				content.text = row.title
				content.secondaryText = row.detail
				content.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .caption1)
				content.secondaryTextProperties.color = .secondaryLabel
				content.image = FaviconStore.shared.nativeImage(for: row.url)
					?? UIImage(systemName: row.symbol)
				content.imageProperties.maximumSize = CGSize(width: 16, height: 16)
				content.textToSecondaryTextVerticalPadding = 2
				cell.contentConfiguration = content
				cell.selectionStyle = .none
				cell.accessibilityIdentifier = row.id
				cell.accessibilityLabel = "Open \(row.title)"
				let button = UIButton(type: .system)
				button.setImage(UIImage(systemName: "plus.square.on.square"), for: .normal)
				button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
				button.accessibilityLabel = "Open \(row.title) in background"
				button.accessibilityIdentifier = "\(row.id)-background"
				button.addAction(UIAction { [weak self] _ in self?.parent?.open(row, true) }, for: .touchUpInside)
				cell.accessoryView = tableView.isEditing ? nil : button
				return cell
			}

			func tableView(_: UITableView, didSelectRowAt path: IndexPath) {
				guard let row = row(at: path) else { return }
				parent?.open(row, false)
			}

			func tableView(_: UITableView, contextMenuConfigurationForRowAt path: IndexPath,
			               point _: CGPoint) -> UIContextMenuConfiguration?
			{
				guard let row = row(at: path) else { return nil }
				return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
					UIMenu(children: BrowserNativeLibraryAction.available(for: row).map { action in
						UIAction(title: action.label(for: row),
						         image: UIImage(systemName: action.icon(for: row)),
						         attributes: action == .addToReadingList && !row.canAddToReadingList ? [.disabled] : (action.isDestructive ? [.destructive] : []))
						{ _ in
							self?.parent?.action(row, action)
						}
					})
				}
			}

			func tableView(_: UITableView, trailingSwipeActionsConfigurationForRowAt path: IndexPath) -> UISwipeActionsConfiguration? {
				guard let row = row(at: path) else { return nil }
				let action: BrowserNativeLibraryAction = switch row.kind {
					case .bookmark: .deleteBookmark
					case .readingList: .removeReadingList
					case .history: .removeHistoryVisit
				}
				let swipe = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, finish in
					self?.parent?.action(row, action)
					finish(true)
				}
				swipe.image = UIImage(systemName: "trash")
				let result = UISwipeActionsConfiguration(actions: [swipe])
				result.performsFirstActionWithFullSwipe = false
				return result
			}

			func tableView(_: UITableView, canMoveRowAt path: IndexPath) -> Bool {
				parent?.canReorder == true && row(at: path)?.kind == .bookmark
			}

			func tableView(_: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath,
			               toProposedIndexPath proposed: IndexPath) -> IndexPath
			{
				guard source.section == proposed.section else { return source }
				return proposed
			}

			func tableView(_: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
				guard parent?.canReorder == true, source.section == destination.section,
				      sections.indices.contains(source.section) else { return }
				let section = sections[source.section]
				var rows = section.rows
				guard rows.indices.contains(source.row), rows.indices.contains(destination.row) else { return }
				let moved = rows.remove(at: source.row)
				rows.insert(moved, at: destination.row)
				// UITableView must see its updated data source immediately after a
				// reorder, rather than waiting for the debounced library projection.
				sections[source.section] = BrowserNativeLibrarySection(
					title: section.title, rows: rows, emptyMessage: section.emptyMessage
				)
				parent?.reorder(section.title, rows.map(\.recordID))
			}
		}
	}
#endif
