import SwiftUI

struct PrivateBrowserSidebar: View {
	let browser: Browser
	var topMargin: CGFloat = 0

	var body: some View {
		let tabs = browser.tabs
		let items = [BrowserSidebarItem(id: "private-header", kind: .privateHeader, height: 48)]
			+ tabs.map { BrowserSidebarItem(id: $0.id.uuidString, height: 34, tabID: $0.id) }
			+ [BrowserSidebarItem(id: "private-new-tab", kind: .newTab, height: 34)]
		BrowserSidebarScrollView(items: items, revision: browser.selectedTabID, top: topMargin) { item in
			switch item.kind {
				case .privateHeader:
					Label("Private Browsing", systemImage: "eye.slash")
						.font(.headline)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.vertical, 12)
				case .tab:
					if let tab = item.tabID.flatMap({ browser.tabsByID[$0] }) {
						PrivateBrowserTabRow(tab: tab, browser: browser)
					}
				case .newTab:
					Button("New Tab", systemImage: "plus") { browser.requestNewTab() }
						.buttonStyle(.plain)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(8)
						.accessibilityIdentifier("private-new-tab")
				default:
					EmptyView()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityIdentifier("private-sidebar")
	}
}

/// Private tabs retain their existing 8-point padding and SwiftUI glass surface,
/// while their interactive row and layout are native platform controls.
private struct PrivateBrowserTabRow: View {
	let tab: BrowserTab
	let browser: Browser

	var body: some View {
		NativePrivateTabRow(
			id: tab.id,
			title: tab.title,
			selected: browser.selectedTabID == tab.id,
			onSelect: { browser.selectTab(tab.id) },
			onClose: { browser.closeTab(tab.id) }
		)
		.padding(8)
		.background {
			if browser.selectedTabID == tab.id {
				Color.clear.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10))
			}
		}
	}
}

#if os(macOS)
	import AppKit

	private struct NativePrivateTabRow: NSViewRepresentable {
		let id: UUID
		let title: String
		let selected: Bool
		let onSelect: () -> Void
		let onClose: () -> Void

		func makeNSView(context _: Context) -> NativePrivateTabControl {
			NativePrivateTabControl(frame: .zero)
		}

		func updateNSView(_ view: NativePrivateTabControl, context _: Context) {
			view.configure(id: id, title: title, selected: selected, onSelect: onSelect, onClose: onClose)
		}
	}

	@MainActor
	private final class NativePrivateTabControl: NSView {
		private let titleButton = NSButton()
		private let closeButton = NSButton()
		private var selectAction: (() -> Void)?
		private var closeAction: (() -> Void)?

		override init(frame: NSRect) {
			super.init(frame: frame)
			titleButton.isBordered = false
			titleButton.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
			titleButton.imagePosition = .imageLeading
			titleButton.alignment = .left
			titleButton.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
			titleButton.cell?.lineBreakMode = .byTruncatingTail
			titleButton.target = self
			titleButton.action = #selector(selectTab)
			closeButton.isBordered = false
			closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
			closeButton.imagePosition = .imageOnly
			closeButton.target = self
			closeButton.action = #selector(closeTab)
			for child in [titleButton, closeButton] {
				child.translatesAutoresizingMaskIntoConstraints = false
				addSubview(child)
			}
			titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
			NSLayoutConstraint.activate([
				titleButton.leadingAnchor.constraint(equalTo: leadingAnchor),
				titleButton.topAnchor.constraint(equalTo: topAnchor),
				titleButton.bottomAnchor.constraint(equalTo: bottomAnchor),
				titleButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
				closeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
				closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
				closeButton.widthAnchor.constraint(equalToConstant: 18),
				closeButton.heightAnchor.constraint(equalToConstant: 18),
			])
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: NSSize {
			NSSize(width: NSView.noIntrinsicMetric, height: 18)
		}

		func configure(id: UUID, title: String, selected: Bool, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
			titleButton.title = title
			selectAction = onSelect
			closeAction = onClose
			titleButton.setAccessibilityIdentifier("private-select-tab-\(id)")
			titleButton.setAccessibilityLabel(title)
			titleButton.setAccessibilitySelected(selected)
			closeButton.setAccessibilityIdentifier("private-close-tab-\(id)")
			closeButton.setAccessibilityLabel("Close Tab")
		}

		@objc private func selectTab() {
			selectAction?()
		}

		@objc private func closeTab() {
			closeAction?()
		}
	}
#elseif os(iOS)
	import UIKit

	private struct NativePrivateTabRow: UIViewRepresentable {
		let id: UUID
		let title: String
		let selected: Bool
		let onSelect: () -> Void
		let onClose: () -> Void

		func makeUIView(context _: Context) -> NativePrivateTabControl {
			NativePrivateTabControl(frame: .zero)
		}

		func updateUIView(_ view: NativePrivateTabControl, context _: Context) {
			view.configure(id: id, title: title, selected: selected, onSelect: onSelect, onClose: onClose)
		}
	}

	@MainActor
	private final class NativePrivateTabControl: UIView {
		private let titleButton = UIButton(type: .custom)
		private let closeButton = UIButton(type: .custom)
		private var selectAction: (() -> Void)?
		private var closeAction: (() -> Void)?

		override init(frame: CGRect) {
			super.init(frame: frame)
			var configuration = UIButton.Configuration.plain()
			configuration.image = UIImage(systemName: "globe")
			configuration.imagePlacement = .leading
			configuration.imagePadding = 6
			configuration.contentInsets = .zero
			titleButton.configuration = configuration
			titleButton.contentHorizontalAlignment = .leading
			titleButton.titleLabel?.lineBreakMode = .byTruncatingTail
			titleButton.addTarget(self, action: #selector(selectTab), for: .touchUpInside)
			closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
			closeButton.addTarget(self, action: #selector(closeTab), for: .touchUpInside)
			let stack = UIStackView(arrangedSubviews: [titleButton, closeButton])
			stack.axis = .horizontal
			stack.alignment = .center
			stack.spacing = 6
			stack.translatesAutoresizingMaskIntoConstraints = false
			addSubview(stack)
			NSLayoutConstraint.activate([
				stack.leadingAnchor.constraint(equalTo: leadingAnchor),
				stack.trailingAnchor.constraint(equalTo: trailingAnchor),
				stack.topAnchor.constraint(equalTo: topAnchor),
				stack.bottomAnchor.constraint(equalTo: bottomAnchor),
				closeButton.widthAnchor.constraint(equalToConstant: 18),
				closeButton.heightAnchor.constraint(equalToConstant: 18),
			])
			titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: CGSize {
			CGSize(width: UIView.noIntrinsicMetric, height: 18)
		}

		func configure(id: UUID, title: String, selected: Bool, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
			titleButton.configuration?.title = title
			titleButton.accessibilityIdentifier = "private-select-tab-\(id)"
			titleButton.accessibilityLabel = title
			titleButton.accessibilityTraits = selected ? [.button, .selected] : .button
			selectAction = onSelect
			closeAction = onClose
			closeButton.accessibilityIdentifier = "private-close-tab-\(id)"
			closeButton.accessibilityLabel = "Close Tab"
		}

		@objc private func selectTab() {
			selectAction?()
		}

		@objc private func closeTab() {
			closeAction?()
		}
	}
#endif
