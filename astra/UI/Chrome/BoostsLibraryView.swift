#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME
import AppKit
import SwiftUI

/// AppKit owns the scroll view, boost cells, menus, actions, and footer.
/// SwiftUI only observes the shared store and forwards immutable snapshots.
struct BoostsLibraryView: View {
	let browser: Browser
	@State private var store = BrowserBoostStore.shared

	var body: some View {
		NativeBoostsList(
			browser: browser,
			store: store,
			boosts: store.boosts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
			currentDomain: browser.selectedTab?.currentURL?.host
		)
		.accessibilityIdentifier("boosts-library")
	}
}

private final class NativeBoostMenuItem: NSMenuItem {
	var run: (() -> Void)?
	init(_ title: String, symbol: String, action: @escaping () -> Void) {
		super.init(title: title, action: nil, keyEquivalent: "")
		image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
		run = action
		target = self
		self.action = #selector(activate)
	}
	required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
	@objc private func activate() { run?() }
}

private final class NativeBoostButton: NSButton {
	var run: (() -> Void)?
	init(symbol: String, label: String, action: @escaping () -> Void) {
		super.init(frame: .zero)
		title = label
		run = action
		image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
		imagePosition = .imageOnly
		isBordered = false
		bezelStyle = .inline
		setAccessibilityLabel(label)
		target = self
		self.action = #selector(activate)
	}
	required init?(coder: NSCoder) { nil }
	@objc private func activate() { run?() }
}

private final class NativeBoostCell: NSTableCellView {
	private let indicator = NativeBoostButton(symbol: "circle", label: "Toggle Boost", action: {})
	private let nameLabel = NSTextField(labelWithString: "")
	private let domainLabel = NSTextField(labelWithString: "")
	private let edit = NativeBoostButton(symbol: "square.and.pencil", label: "Edit Boost", action: {})

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		nameLabel.font = .systemFont(ofSize: 13)
		nameLabel.lineBreakMode = .byTruncatingTail
		domainLabel.font = .systemFont(ofSize: 11)
		domainLabel.textColor = .secondaryLabelColor
		domainLabel.lineBreakMode = .byTruncatingTail
		let texts = NSStackView(views: [nameLabel, domainLabel])
		texts.orientation = .vertical
		texts.alignment = .leading
		texts.spacing = 2
		let row = NSStackView(views: [indicator, texts, edit])
		row.orientation = .horizontal
		row.alignment = .centerY
		row.spacing = 10
		row.translatesAutoresizingMaskIntoConstraints = false
		addSubview(row)
		NSLayoutConstraint.activate([
			row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			row.topAnchor.constraint(equalTo: topAnchor, constant: 3),
			row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
			indicator.widthAnchor.constraint(equalToConstant: 20),
			edit.widthAnchor.constraint(equalToConstant: 20),
			texts.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
		])
	}
	required init?(coder: NSCoder) { nil }

	func configure(_ boost: BrowserBoost, store: BrowserBoostStore) {
		indicator.image = NSImage(systemSymbolName: boost.isEnabled ? "checkmark.circle.fill" : "circle",
		                          accessibilityDescription: "Toggle Boost")
		indicator.contentTintColor = boost.isEnabled ? .controlAccentColor : .secondaryLabelColor
		indicator.run = { store.toggle(boost.id) }
		indicator.setAccessibilityLabel("\(boost.name), \(boost.isEnabled ? "Enabled" : "Disabled")")
		indicator.setAccessibilityIdentifier("boost-toggle-\(boost.id)")
		nameLabel.stringValue = boost.name
		domainLabel.stringValue = boost.domain ?? "All websites"
		edit.run = { BrowserBoostEditorWindowController.open(boost.id) }
		edit.setAccessibilityIdentifier("boost-edit-\(boost.id)")
		setAccessibilityIdentifier("boost-row-\(boost.id)")
	}
}

private final class NativeBoostsTable: NSTableView {
	var menuForRow: ((Int) -> NSMenu?)?
	override func menu(for event: NSEvent) -> NSMenu? {
		menuForRow?(row(at: convert(event.locationInWindow, from: nil))) ?? super.menu(for: event)
	}
}

private final class NativeBoostsContainer: NSView {
	let scroll = NSScrollView()
	let table = NativeBoostsTable()
	let footer = NSVisualEffectView()
	let count = NSTextField(labelWithString: "0 Boosts")
	let create = NativeBoostButton(symbol: "plus", label: "New Boost", action: {})
	let empty = NSTextField(labelWithString: "No Boosts")

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		scroll.drawsBackground = false
		scroll.contentView.drawsBackground = false
		scroll.hasVerticalScroller = true
		scroll.hasHorizontalScroller = false
		scroll.autohidesScrollers = true
		table.backgroundColor = .clear
		table.headerView = nil
		table.intercellSpacing = NSSize(width: 0, height: 0)
		table.selectionHighlightStyle = .none
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("boost"))
		column.resizingMask = .autoresizingMask
		table.addTableColumn(column)
		scroll.documentView = table
		footer.material = .underWindowBackground
		footer.blendingMode = .withinWindow
		footer.state = .active
		count.textColor = .secondaryLabelColor
		count.font = .systemFont(ofSize: 12)
		let footerRow = NSStackView(views: [count, create])
		footerRow.orientation = .horizontal
		footerRow.alignment = .centerY
		footerRow.distribution = .fill
		footerRow.translatesAutoresizingMaskIntoConstraints = false
		footer.addSubview(footerRow)
		empty.font = .systemFont(ofSize: 15, weight: .semibold)
		empty.textColor = .secondaryLabelColor
		empty.alignment = .center
		for subview in [scroll, footer, empty] {
			subview.translatesAutoresizingMaskIntoConstraints = false
			addSubview(subview)
		}
		NSLayoutConstraint.activate([
			scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.topAnchor.constraint(equalTo: topAnchor),
			scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
			footer.leadingAnchor.constraint(equalTo: leadingAnchor),
			footer.trailingAnchor.constraint(equalTo: trailingAnchor),
			footer.bottomAnchor.constraint(equalTo: bottomAnchor),
			footerRow.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 10),
			footerRow.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -10),
			footerRow.topAnchor.constraint(equalTo: footer.topAnchor, constant: 10),
			footerRow.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -10),
			empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
			empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
		])
		empty.setAccessibilityIdentifier("boosts-library-empty")
		create.setAccessibilityIdentifier("boost-create-library")
	}
	required init?(coder: NSCoder) { nil }
}

private struct NativeBoostsList: NSViewRepresentable {
	let browser: Browser
	let store: BrowserBoostStore
	let boosts: [BrowserBoost]
	let currentDomain: String?

	func makeCoordinator() -> Coordinator { Coordinator() }

	func makeNSView(context: Context) -> NativeBoostsContainer {
		let view = NativeBoostsContainer()
		view.table.delegate = context.coordinator
		view.table.dataSource = context.coordinator
		view.table.menuForRow = { [weak coordinator = context.coordinator] row in coordinator?.menu(row: row) }
		context.coordinator.container = view
		return view
	}
	func updateNSView(_ view: NativeBoostsContainer, context: Context) { context.coordinator.update(self) }
	static func dismantleNSView(_ view: NativeBoostsContainer, coordinator: Coordinator) {
		view.table.delegate = nil
		view.table.dataSource = nil
		coordinator.container = nil
	}

	@MainActor
	final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
		weak var container: NativeBoostsContainer?
		private var model: NativeBoostsList?

		func update(_ next: NativeBoostsList) {
			let previous = model
			model = next
			guard let container else { return }
			if previous?.boosts != next.boosts { container.table.reloadData() }
			container.count.stringValue = "\(next.boosts.count) Boosts"
			container.empty.isHidden = !next.boosts.isEmpty
			container.create.run = { [weak self] in
				guard let model = self?.model else { return }
				let boost = model.store.create(domain: model.currentDomain)
				BrowserBoostEditorWindowController.open(boost.id)
			}
		}
		func numberOfRows(in tableView: NSTableView) -> Int { model?.boosts.count ?? 0 }
		func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 45 }
		func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
			guard let model, model.boosts.indices.contains(row) else { return nil }
			let id = NSUserInterfaceItemIdentifier("native-boost-row")
			let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NativeBoostCell)
				?? NativeBoostCell(frame: .zero)
			cell.identifier = id
			cell.configure(model.boosts[row], store: model.store)
			return cell
		}
		func menu(row: Int) -> NSMenu? {
			guard let model, model.boosts.indices.contains(row) else { return nil }
			let boost = model.boosts[row]
			let store = model.store
			let menu = NSMenu()
			menu.addItem(NativeBoostMenuItem("Edit Boost", symbol: "square.and.pencil") {
				BrowserBoostEditorWindowController.open(boost.id)
			})
			menu.addItem(NativeBoostMenuItem(boost.isEnabled ? "Disable Boost" : "Enable Boost",
			                                 symbol: boost.isEnabled ? "circle" : "checkmark.circle") {
				store.toggle(boost.id)
			})
			menu.addItem(.separator())
			menu.addItem(NativeBoostMenuItem("Delete Boost", symbol: "trash") {
				BrowserBoostEditorWindowController.close(boost.id)
				store.delete(boost.id)
			})
			return menu
		}
		func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
			guard edge == .trailing, let model, model.boosts.indices.contains(row) else { return [] }
			let id = model.boosts[row].id
			let store = model.store
			return [NSTableViewRowAction(style: .destructive, title: "Delete") { _, _ in
				BrowserBoostEditorWindowController.close(id)
				store.delete(id)
			}]
		}
	}
}
#endif
