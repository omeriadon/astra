import SwiftUI

#if !ASTRA_WEBSITE_APP_RUNTIME

	/// The top-level switch remains a small SwiftUI observation/binding boundary.
	/// The segmented control and all three libraries have native platform views.
	struct LibrarySidebarView: View {
		let browser: Browser
		let manager: BrowserDownloadManager
		let theme: BrowserTheme
		var topMargin: CGFloat = BrowserChromeMetrics.topBarRegionHeight
		@Binding var selection: Int
		@Environment(\.accessibilityReduceMotion) private var reduceMotion

		var body: some View {
			VStack(spacing: 0) {
				NativeLibraryCategoryPicker(selection: $selection)
				#if os(macOS)
					.padding(.top, topMargin)
				#endif
					.padding(8)
					.accessibilityIdentifier("library-category")
				if selection == 0 {
					DownloadsSidebarView(manager: manager, theme: theme)
				} else if selection == 2 {
					#if os(macOS)
						BoostsLibraryView(browser: browser)
					#endif
				} else {
					NativeEaselLibrary(
						browser: browser,
						theme: theme,
						entries: easelEntries,
						hasEasels: browser.tabs.contains(where: { $0.internalPage == .easel })
					)
				}
			}
			.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: topMargin)
			.accessibilityIdentifier("library-sidebar")
		}

		/// Stable value snapshots: a title or pinned membership change invalidates
		/// only the native data source, not a tree of SwiftUI list rows.
		private var easelEntries: [NativeEaselEntry] {
			var entries: [NativeEaselEntry] = [.section("Favourites")]
			entries += browser.favouriteTabs.filter { $0.internalPage == .easel }
				.map { .easel(id: $0.id, title: $0.title) }
			for space in browser.workspace.spaces {
				let easels = space.pinnedTabIDs.compactMap { browser.tab(withID: $0) }
					.filter { $0.internalPage == .easel }
				if !easels.isEmpty {
					entries.append(.section(space.name))
					entries += easels.map { .easel(id: $0.id, title: $0.title) }
				}
			}
			return entries
		}
	}

	private enum NativeEaselEntry: Equatable {
		case section(String)
		case easel(id: UUID, title: String)

		var id: UUID? {
			if case let .easel(id, _) = self {
				return id
			}
			return nil
		}
	}

	#if os(macOS)
		import AppKit

		private struct NativeLibraryCategoryPicker: NSViewRepresentable {
			@Binding var selection: Int
			func makeCoordinator() -> Coordinator {
				Coordinator(selection: $selection)
			}

			func makeNSView(context: Context) -> NSSegmentedControl {
				let control = NSSegmentedControl(labels: ["Downloads", "Easels", "Boosts"], trackingMode: .selectOne,
				                                 target: context.coordinator, action: #selector(Coordinator.didSelect(_:)))
				control.segmentStyle = .rounded
				control.setAccessibilityIdentifier("library-category")
				return control
			}

			func updateNSView(_ control: NSSegmentedControl, context: Context) {
				context.coordinator.selection = $selection
				if control.selectedSegment != selection {
					control.selectedSegment = selection
				}
			}

			@MainActor final class Coordinator: NSObject {
				var selection: Binding<Int>
				init(selection: Binding<Int>) {
					self.selection = selection
				}

				@objc func didSelect(_ sender: NSSegmentedControl) {
					selection.wrappedValue = sender.selectedSegment
				}
			}
		}

		private final class EaselLibraryMenuItem: NSMenuItem {
			var performAction: (() -> Void)?
			init(_ title: String, image: String, enabled: Bool = true, action: @escaping () -> Void) {
				super.init(title: title, action: nil, keyEquivalent: "")
				performAction = action
				self.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
				isEnabled = enabled
				target = self
				self.action = #selector(performSelection)
			}

			@available(*, unavailable)
			required init(coder _: NSCoder) {
				fatalError("init(coder:) has not been implemented")
			}

			@objc private func performSelection() {
				performAction?()
			}
		}

		private final class EaselLibraryTable: NSTableView {
			var menuForRow: ((Int) -> NSMenu?)?
			override func menu(for event: NSEvent) -> NSMenu? {
				menuForRow?(row(at: convert(event.locationInWindow, from: nil))) ?? super.menu(for: event)
			}
		}

		private struct NativeEaselLibrary: NSViewRepresentable {
			let browser: Browser
			let theme: BrowserTheme
			let entries: [NativeEaselEntry]
			let hasEasels: Bool

			func makeCoordinator() -> Coordinator {
				Coordinator()
			}

			func makeNSView(context: Context) -> NSScrollView {
				let scroll = NSScrollView()
				scroll.drawsBackground = false
				scroll.contentView.drawsBackground = false
				scroll.hasVerticalScroller = true
				scroll.autohidesScrollers = true
				let table = EaselLibraryTable()
				table.backgroundColor = .clear
				table.frame = scroll.contentView.bounds
				table.autoresizingMask = [.width]
				table.headerView = nil
				table.intercellSpacing = NSSize(width: 0, height: 0)
				table.selectionHighlightStyle = .none
				let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("easel"))
				column.resizingMask = .autoresizingMask
				table.addTableColumn(column)
				table.delegate = context.coordinator
				table.dataSource = context.coordinator
				table.menuForRow = { [weak coordinator = context.coordinator] row in coordinator?.menu(row: row) }
				scroll.documentView = table
				context.coordinator.table = table
				context.coordinator.scroll = scroll
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
				view.documentView = nil
			}

			@MainActor
			final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
				weak var table: EaselLibraryTable?
				weak var scroll: NSScrollView?
				private var model: NativeEaselLibrary?
				private var emptyLabel: NSTextField?

				func update(_ next: NativeEaselLibrary) {
					let previous = model
					model = next
					if previous?.entries != next.entries {
						table?.reloadData()
					}
					let empty = !next.hasEasels
					if empty, emptyLabel == nil, let scroll {
						let label = NSTextField(labelWithString: "No Easels")
						label.font = .systemFont(ofSize: 15, weight: .semibold)
						label.alignment = .center
						label.textColor = .secondaryLabelColor
						label.translatesAutoresizingMaskIntoConstraints = false
						scroll.addSubview(label)
						NSLayoutConstraint.activate([
							label.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
							label.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
						])
						emptyLabel = label
					}
					emptyLabel?.isHidden = !empty
				}

				func numberOfRows(in _: NSTableView) -> Int {
					model?.entries.count ?? 0
				}

				func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
					guard let entry = model?.entries[safeEasel: row] else { return false }
					if case .section = entry {
						return true
					}
					return false
				}

				func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
					if case .section? = model?.entries[safeEasel: row] {
						return 29
					}
					return 29
				}

				func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
					guard let model, let entry = model.entries[safeEasel: row] else { return nil }
					switch entry {
						case let .section(name):
							let id = NSUserInterfaceItemIdentifier("easel-section")
							let label = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField)
								?? NSTextField(labelWithString: "")
							label.identifier = id
							label.stringValue = name
							label.font = .systemFont(ofSize: 11, weight: .semibold)
							label.textColor = NSColor(model.theme.foregroundColor).withAlphaComponent(0.65)
							return label
						case let .easel(id, name):
							let identifier = NSUserInterfaceItemIdentifier("easel-row")
							let button = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSButton) ?? NSButton()
							button.identifier = identifier
							button.title = name
							button.image = NSImage(systemSymbolName: "paintbrush.pointed", accessibilityDescription: nil)
							button.imagePosition = .imageLeading
							button.alignment = .left
							button.isBordered = false
							button.font = .systemFont(ofSize: 13)
							button.contentTintColor = NSColor(model.theme.foregroundColor)
							button.lineBreakMode = .byTruncatingTail
							button.target = self
							button.action = #selector(openEasel(_:))
							button.tag = row
							button.setAccessibilityIdentifier("library-easel-\(id.uuidString)")
							return button
					}
				}

				@objc private func openEasel(_ sender: NSButton) {
					guard let model, let id = model.entries[safeEasel: sender.tag]?.id else { return }
					model.browser.selectTab(id)
				}

				func menu(row: Int) -> NSMenu? {
					guard let model, let id = model.entries[safeEasel: row]?.id else { return nil }
					let browser = model.browser
					let menu = NSMenu()
					let canSplit = (browser.selectedTab?.canAppearInEaselSplit == true || browser.isShowingEaselSplit)
						&& browser.visibleTabs.contains(where: { $0.id == id }) && browser.selectedTabID != id
					menu.addItem(EaselLibraryMenuItem("Open Beside Current Page", image: "rectangle.split.2x1",
					                                  enabled: canSplit) { browser.openEaselInSplit(id) })
					menu.addItem(EaselLibraryMenuItem("Delete Easel", image: "trash") { [weak self] in
						self?.requestDelete(id)
					})
					return menu
				}

				private func requestDelete(_ id: UUID) {
					guard let model, let tab = model.browser.tab(withID: id) else { return }
					guard !tab.easelDocument.items.isEmpty else {
						model.browser.deleteEasel(id, confirmed: true)
						return
					}
					let alert = NSAlert()
					alert.messageText = "Delete this easel?"
					alert.informativeText = "Its contents will be permanently deleted from your devices and open peeks will close."
					alert.addButton(withTitle: "Delete Easel")
					alert.addButton(withTitle: "Cancel")
					if let window = table?.window {
						alert.beginSheetModal(for: window) { result in
							if result == .alertFirstButtonReturn {
								model?.browser.deleteEasel(id, confirmed: true)
							}
						}
					}
				}

				func tableView(_: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
					guard edge == .trailing, model?.entries[safeEasel: row]?.id != nil else { return [] }
					return [NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] _, _ in
						guard let id = self?.model?.entries[safeEasel: row]?.id else { return }
						self?.requestDelete(id)
					}]
				}
			}
		}

	#elseif os(iOS)
		import UIKit

		private struct NativeLibraryCategoryPicker: UIViewRepresentable {
			@Binding var selection: Int
			func makeCoordinator() -> Coordinator {
				Coordinator(selection: $selection)
			}

			func makeUIView(context: Context) -> UISegmentedControl {
				let control = UISegmentedControl(items: ["Downloads", "Easels"])
				control.addTarget(context.coordinator, action: #selector(Coordinator.didSelect(_:)), for: .valueChanged)
				control.accessibilityIdentifier = "library-category"
				return control
			}

			func updateUIView(_ control: UISegmentedControl, context: Context) {
				context.coordinator.selection = $selection
				if control.selectedSegmentIndex != selection {
					control.selectedSegmentIndex = selection
				}
			}

			@MainActor final class Coordinator: NSObject {
				var selection: Binding<Int>
				init(selection: Binding<Int>) {
					self.selection = selection
				}

				@objc func didSelect(_ sender: UISegmentedControl) {
					selection.wrappedValue = sender.selectedSegmentIndex
				}
			}
		}

		private struct NativeEaselLibrary: UIViewRepresentable {
			let browser: Browser
			let theme: BrowserTheme
			let entries: [NativeEaselEntry]
			let hasEasels: Bool

			func makeCoordinator() -> Coordinator {
				Coordinator()
			}

			func makeUIView(context: Context) -> UITableView {
				let table = UITableView(frame: .zero, style: .plain)
				table.backgroundColor = .clear
				table.separatorStyle = .none
				table.register(UITableViewCell.self, forCellReuseIdentifier: "easel")
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
			final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
				weak var table: UITableView?
				private var model: NativeEaselLibrary?
				func update(_ next: NativeEaselLibrary) {
					let previous = model
					model = next
					if previous?.entries != next.entries {
						table?.reloadData()
					}
					if !next.hasEasels {
						let label = UILabel()
						label.text = "No Easels"
						label.textColor = .secondaryLabel
						label.font = .preferredFont(forTextStyle: .headline)
						label.textAlignment = .center
						table?.backgroundView = label
					} else {
						table?.backgroundView = nil
					}
				}

				func numberOfSections(in _: UITableView) -> Int {
					1
				}

				func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
					model?.entries.count ?? 0
				}

				func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
					let cell = tableView.dequeueReusableCell(withIdentifier: "easel", for: indexPath)
					cell.backgroundColor = .clear
					guard let entry = model?.entries[safeEasel: indexPath.row] else { return cell }
					switch entry {
						case let .section(title):
							var configuration = UIListContentConfiguration.groupedHeader()
							configuration.text = title
							configuration.textProperties.color = UIColor(model?.theme.foregroundColor ?? .primary).withAlphaComponent(0.65)
							cell.contentConfiguration = configuration
							cell.selectionStyle = .none
						case let .easel(id, title):
							var configuration = UIListContentConfiguration.cell()
							configuration.text = title
							configuration.image = UIImage(systemName: "paintbrush.pointed")
							configuration.textProperties.color = UIColor(model?.theme.foregroundColor ?? .primary)
							configuration.imageProperties.tintColor = UIColor(model?.theme.foregroundColor ?? .primary)
							cell.contentConfiguration = configuration
							cell.selectionStyle = .default
							cell.accessibilityIdentifier = "library-easel-\(id.uuidString)"
					}
					return cell
				}

				func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
					if let id = model?.entries[safeEasel: indexPath.row]?.id {
						model?.browser.selectTab(id)
					}
					tableView.deselectRow(at: indexPath, animated: false)
				}

				func tableView(_: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
					guard let model, let id = model.entries[safeEasel: indexPath.row]?.id else { return nil }
					let browser = model.browser
					let canSplit = (browser.selectedTab?.canAppearInEaselSplit == true || browser.isShowingEaselSplit)
						&& browser.visibleTabs.contains(where: { $0.id == id }) && browser.selectedTabID != id
					return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
						UIMenu(children: [
							UIAction(title: "Open Beside Current Page", image: UIImage(systemName: "rectangle.split.2x1"),
							         attributes: canSplit ? [] : [.disabled]) { _ in browser.openEaselInSplit(id) },
							UIAction(title: "Delete Easel", image: UIImage(systemName: "trash"),
							         attributes: .destructive) { _ in self?.requestDelete(id) },
						])
					}
				}

				func tableView(_: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
					guard let id = model?.entries[safeEasel: indexPath.row]?.id else { return nil }
					return UISwipeActionsConfiguration(actions: [
						UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, finish in
							self?.requestDelete(id)
							finish(true)
						},
					])
				}

				private func requestDelete(_ id: UUID) {
					guard let model, let tab = model.browser.tab(withID: id) else { return }
					guard !tab.easelDocument.items.isEmpty else {
						model.browser.deleteEasel(id, confirmed: true)
						return
					}
					let alert = UIAlertController(title: "Delete this easel?",
					                              message: "Its contents will be permanently deleted from your devices and open peeks will close.",
					                              preferredStyle: .alert)
					alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
					alert.addAction(UIAlertAction(title: "Delete Easel", style: .destructive) { _ in
						model.browser.deleteEasel(id, confirmed: true)
					})
					var presenter = table?.window?.rootViewController
					while let presented = presenter?.presentedViewController {
						presenter = presented
					}
					presenter?.present(alert, animated: true)
				}
			}
		}
	#endif

	private extension Array {
		subscript(safeEasel index: Int) -> Element? {
			indices.contains(index) ? self[index] : nil
		}
	}
#endif
