import SwiftUI

// The composer and title bar intentionally stay in SwiftUI. The transcript owns
// native, reusable rows and never republishes generated tokens through SwiftUI.
#if os(macOS)
import AppKit
import MarkdownView

struct BrowserAIChatTranscript: NSViewRepresentable {
    let browser: Browser
    let chat: BrowserAIChat
    let retry: () -> Void
    let hover: (URL?, URL?, CGSize, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ai-transcript"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.scroll = scroll
        context.coordinator.update(self)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.stop()
        coordinator.table?.delegate = nil
        coordinator.table?.dataSource = nil
        scroll.documentView = nil
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: NSTableView?
        weak var scroll: NSScrollView?
        private var parent: BrowserAIChatTranscript?
        private var messageIDs: [UUID] = []
        private var conversationID: UUID?
        private var lastWidth: CGFloat = 0
        private var sizingCache: [UUID: CGFloat] = [:]
        private var streamingRevision = ""
        private var poller: Task<Void, Never>?
        private var lastStreaming = false

        private var entries: [Entry] {
            guard let parent else { return [] }
            return (parent.chat.messages.isEmpty ? [.welcome] : []) +
                parent.chat.messages.map { Entry.message($0) } + [.stream]
        }

        func update(_ new: BrowserAIChatTranscript) {
            let old = parent
            parent = new
            guard let table else { return }
            let ids = new.chat.messages.map(\.id)
            let width = max(1, table.bounds.width - 24)
            let changed = conversationID != new.chat.id || ids != messageIDs ||
                (old == nil)
            let widthChanged = abs(lastWidth - width) > 1
            let streamChanged = lastStreaming != new.chat.isResponding
            conversationID = new.chat.id
            messageIDs = ids
            lastWidth = width
            lastStreaming = new.chat.isResponding
            if changed || widthChanged {
                if changed { sizingCache.removeAll(keepingCapacity: true) }
                table.reloadData()
                if changed { scrollToBottom() }
            } else if streamChanged {
                reloadStream()
            }
            if new.chat.isResponding {
                startPolling()
            } else {
                poller?.cancel()
                poller = nil
                refreshStreaming(force: true)
            }
        }

        func numberOfRows(in _: NSTableView) -> Int { entries.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            let entry = entries[row]
            let width = max(1, tableView.bounds.width - 24)
            if case .message(let message) = entry,
               let height = sizingCache[message.id] { return height }
            let view = TranscriptNativeRow()
            configure(view, entry: entry, width: width)
            let height = view.measuredHeight
            if case .message(let message) = entry { sizingCache[message.id] = height }
            return height
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("ai-native-row")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? TranscriptNativeRow) ?? TranscriptNativeRow()
            cell.identifier = identifier
            configure(cell, entry: entries[row], width: max(1, tableView.bounds.width - 24))
            return cell
        }

        private func configure(_ view: TranscriptNativeRow, entry: Entry, width: CGFloat) {
            guard let parent else { return }
            view.configure(entry, width: width, tint: NSColor(parent.browser.theme.tabColor),
                open: { [weak browser = parent.browser] url in browser?.openHistoryURL(url, inBackground: false) },
                hover: parent.hover, retry: parent.retry,
                artifact: { [weak browser = parent.browser] item in
                    guard let browser else { return }
                    do { try BrowserWebsiteAugment.open(item, in: browser) }
                    catch { browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: error.localizedDescription) }
                })
        }

        private func startPolling() {
            guard poller == nil else { return }
            poller = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    self?.refreshStreaming(force: false)
                }
            }
        }

        private func refreshStreaming(force: Bool) {
            guard let parent else { return }
            let chat = parent.chat
            let revision = String(chat.isResponding) + chat.preview + chat.activity +
                String(chat.canRetry) + (chat.error ?? "") +
                chat.toolCalls.map { $0.id.uuidString + $0.status + $0.name }.joined()
            guard force || revision != streamingRevision else { return }
            streamingRevision = revision
            reloadStream()
        }

        private func reloadStream() {
            guard let table, !entries.isEmpty else { return }
            let atBottom = isNearBottom
            table.reloadData(forRowIndexes: IndexSet(integer: entries.count - 1),
                             columnIndexes: IndexSet(integer: 0))
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: entries.count - 1))
            if atBottom { scrollToBottom() }
        }

        private var isNearBottom: Bool {
            guard let scroll else { return true }
            let documentHeight = scroll.documentView?.bounds.height ?? 0
            return scroll.contentView.bounds.maxY >= documentHeight - 48
        }

        private func scrollToBottom() {
            guard let table, let scroll, table.numberOfRows > 0 else { return }
            table.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, table.bounds.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        func stop() {
            poller?.cancel()
            poller = nil
            parent = nil
            sizingCache.removeAll()
        }

        enum Entry {
            case welcome
            case message(BrowserAIChat.Message)
            case stream
        }
    }
}

// AppKit coordinates the layout directly; each NSTableView row is recycled.
// No NSHostingView or SwiftUI-generated text/controls live in the scroll region.
@MainActor private final class TranscriptNativeRow: NSView {
    private struct Piece {
        let view: NSView
        let height: CGFloat
        let width: CGFloat?
        let trailing: Bool
    }
    private var pieces: [Piece] = []
    private var rowWidth: CGFloat = 1
    private(set) var measuredHeight: CGFloat = 1

    override var isFlipped: Bool { true }

    func configure(_ entry: BrowserAIChatTranscript.Coordinator.Entry, width: CGFloat, tint: NSColor,
                   open: @escaping (URL) -> Void, hover: @escaping (URL?, URL?, CGSize, Bool) -> Void,
                   retry: @escaping () -> Void, artifact: @escaping (BrowserWebsiteAugmentArtifact) -> Void) {
        subviews.forEach { child in
            if let markdown = child as? ChatMarkdownView { markdown.stopMonitoring() }
            child.removeFromSuperview()
        }
        pieces.removeAll(keepingCapacity: true)
        rowWidth = width
        switch entry {
        case .welcome:
            add(label("Work with this page", size: 19, weight: .medium), height: 27)
            add(label("Ask a question, summarise, or change what’s shown. Use @ to add another tab.",
                      size: 13, secondary: true), height: textHeight("Ask a question, summarise, or change what’s shown. Use @ to add another tab.", width: width, size: 13))
        case .message(let message):
            if !message.attachments.isEmpty { add(attachments(message.attachments), height: 90) }
            if message.isUser {
                let body = label(message.text, size: 13)
                body.textColor = NSColor.labelColor.blended(withFraction: 0.3, of: tint)
                let maxBodyWidth = max(40, width - 24)
                let naturalWidth = ceil((message.text as NSString).boundingRect(
                    with: NSSize(width: maxBodyWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: NSFont.systemFont(ofSize: 13)]
                ).width)
                let bubbleWidth = min(maxBodyWidth + 24, naturalWidth + 28)
                let h = textHeight(message.text, width: bubbleWidth - 24, size: 13) + 24
                let bubble = NSVisualEffectView()
                bubble.material = .hudWindow
                bubble.blendingMode = .withinWindow
                bubble.state = .active
                bubble.wantsLayer = true
                bubble.layer?.cornerRadius = 16
                body.frame = NSRect(x: 12, y: 12, width: bubbleWidth - 24, height: h - 24)
                bubble.addSubview(body)
                add(bubble, height: h, width: bubbleWidth, trailing: true)
            } else {
                if let calls = message.toolCalls, !calls.isEmpty { add(tools(calls), height: CGFloat(calls.count) * 24) }
                if !message.text.isEmpty { addMarkdown(message.text, width: width, open: open, hover: hover) }
                for item in message.augmentArtifacts ?? [] { add(artifactButton(item, tint: tint, action: artifact), height: 78) }
            }
        case .stream:
            // Live content is supplied by configureStream.
        }
        if pieces.isEmpty { measuredHeight = 1 }
        else { measuredHeight = pieces.reduce(0) { $0 + $1.height } + CGFloat(pieces.count - 1) * 10 + 16 }
        needsLayout = true
    }

    func configureStream(chat: BrowserAIChat, width: CGFloat, tint: NSColor,
                         open: @escaping (URL) -> Void,
                         hover: @escaping (URL?, URL?, CGSize, Bool) -> Void,
                         retry: @escaping () -> Void) {
        pieces.forEach { if let markdown = $0.view as? ChatMarkdownView { markdown.stopMonitoring() } }
        subviews.forEach { $0.removeFromSuperview() }
        pieces.removeAll()
        rowWidth = width
        if chat.isResponding {
            if !chat.toolCalls.isEmpty { add(tools(chat.toolCalls), height: CGFloat(chat.toolCalls.count) * 24) }
            if chat.preview.isEmpty {
                add(label("✧  " + chat.activity, size: 12, secondary: true), height: 24)
            } else {
                addMarkdown(chat.preview, width: width, open: open, hover: hover, streaming: true)
            }
        } else if chat.error != nil, !chat.toolCalls.isEmpty,
                  chat.messages.last?.toolCalls?.last?.id != chat.toolCalls.last?.id {
            add(tools(chat.toolCalls), height: CGFloat(chat.toolCalls.count) * 24)
        }
        if chat.canRetry {
            let button = TranscriptActionButton(title: "Retry Message", symbol: "arrow.clockwise", action: retry)
            button.accessibilityIdentifier = "ai-chat-retry"
            add(button, height: 28)
        }
        measuredHeight = pieces.isEmpty ? 1 : pieces.reduce(0) { $0 + $1.height } + CGFloat(pieces.count - 1) * 10 + 16
        needsLayout = true
    }

    private func addMarkdown(_ text: String, width: CGFloat, open: @escaping (URL) -> Void,
                             hover: @escaping (URL?, URL?, CGSize, Bool) -> Void, streaming: Bool = false) {
        let markdown = ChatMarkdownView()
        markdown.isStreaming = streaming
        markdown.displayedText = text
        markdown.hover = hover
        markdown.linkHandler = { payload, _, _ in
            let url: URL? = switch payload {
            case .url(let value): value
            case .string(let value): URL(string: value)
            }
            if let url { open(url) }
        }
        markdown.setContent(MarkdownContent(markdown: text, theme: markdown.theme))
        add(markdown, height: max(1, ceil(markdown.boundingSize(for: width).height)))
    }

    private func add(_ view: NSView, height: CGFloat, width: CGFloat? = nil, trailing: Bool = false) {
        addSubview(view)
        pieces.append(Piece(view: view, height: height, width: width, trailing: trailing))
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 8
        for part in pieces {
            let w = min(rowWidth, part.width ?? rowWidth)
            part.view.frame = NSRect(x: 12 + (part.trailing ? rowWidth - w : 0),
                                     y: y, width: w, height: part.height)
            y += part.height + 10
        }
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       secondary: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text)
        view.font = NSFont.systemFont(ofSize: size, weight: weight)
        view.textColor = secondary ? .secondaryLabelColor : .labelColor
        view.isSelectable = true
        view.lineBreakMode = .byWordWrapping
        view.maximumNumberOfLines = 0
        return view
    }

    private func textHeight(_ text: String, width: CGFloat, size: CGFloat) -> CGFloat {
        max(ceil(NSFont.systemFont(ofSize: size).boundingRectForFont.height),
            ceil((text as NSString).boundingRect(with: NSSize(width: width, height: 100000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: NSFont.systemFont(ofSize: size)]).height))
    }

    private func tools(_ calls: [BrowserAIChat.ToolActivity]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        for call in calls {
            let line = NSStackView()
            line.orientation = .horizontal
            line.alignment = .centerY
            line.spacing = 5
            let action = BrowserAIAction(rawValue: call.name)
            let symbol = action?.chatSystemImage ?? "wrench.and.screwdriver"
            let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
            image.contentTintColor = .secondaryLabelColor
            image.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 14), image.heightAnchor.constraint(equalToConstant: 14)])
            line.addArrangedSubview(image)
            let name = action?.title ?? call.name.replacingOccurrences(of: "_", with: " ").capitalized
            let text = label(name, size: 12, secondary: true)
            text.lineBreakMode = .byTruncatingTail
            text.maximumNumberOfLines = 1
            line.addArrangedSubview(text)
            line.setAccessibilityIdentifier("ai-chat-tool-\(call.id)")
            stack.addArrangedSubview(line)
        }
        stack.setAccessibilityIdentifier("ai-chat-tool-activity")
        return stack
    }

    private func attachments(_ attachments: [BrowserAIAttachment]) -> NSView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        let document = NSView(frame: NSRect(x: 0, y: 0, width: CGFloat(attachments.count) * 88, height: 88))
        for (index, attachment) in attachments.enumerated() {
            let x = CGFloat(index) * 88
            if let data = attachment.image?.data,
               let image = BrowserAIThumbnailCache.image(id: attachment.id, data: data) {
                let view = NSImageView(image: image)
                view.imageScaling = .scaleProportionallyUpOrDown
                view.frame = NSRect(x: x, y: 20, width: 80, height: 64)
                document.addSubview(view)
            } else {
                let icon = NSImageView(image: NSImage(systemSymbolName: "doc.text", accessibilityDescription: attachment.name) ?? NSImage())
                icon.frame = NSRect(x: x + 24, y: 42, width: 32, height: 32)
                document.addSubview(icon)
            }
            let name = label(attachment.name, size: 10)
            name.lineBreakMode = .byTruncatingTail
            name.maximumNumberOfLines = 1
            name.frame = NSRect(x: x, y: 0, width: 80, height: 16)
            document.addSubview(name)
        }
        scroll.documentView = document
        return scroll
    }

    private func artifactButton(_ item: BrowserWebsiteAugmentArtifact, tint: NSColor,
                                action: @escaping (BrowserWebsiteAugmentArtifact) -> Void) -> NSView {
        let button = TranscriptActionButton(title: item.title, symbol: "rectangle.3.group") { action(item) }
        button.accessibilityIdentifier = "ai-chat-artifact-\(item.id)"
        button.setAccessibilityLabel("Open \(item.title)")
        button.contentTintColor = tint
        return button
    }
}

@MainActor private final class TranscriptActionButton: NSButton {
    private let handler: () -> Void
    init(title: String, symbol: String, action: @escaping () -> Void) {
        self.handler = action
        super.init(frame: .zero)
        self.title = title
        self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        self.imagePosition = .imageLeading
        self.bezelStyle = .rounded
        self.target = self
        self.action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}

#else
import UIKit

// UIKit owns the full transcript on iPhone and iPad; SwiftUI continues to own
// the separate title/composer safe-area bars.
struct BrowserAIChatTranscript: UIViewRepresentable {
    let browser: Browser
    let chat: BrowserAIChat
    let retry: () -> Void
    let hover: (URL?, URL?, CGSize, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.estimatedRowHeight = 100
        table.rowHeight = UITableView.automaticDimension
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        context.coordinator.table = table
        context.coordinator.update(self)
        return table
    }
    func updateUIView(_ view: UITableView, context: Context) { context.coordinator.update(self) }
    static func dismantleUIView(_ view: UITableView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        weak var table: UITableView?
        private var parent: BrowserAIChatTranscript?
        private var ids: [UUID] = []
        private var conversationID: UUID?
        private var streamRevision = ""
        private var polling: Task<Void, Never>?

        func update(_ value: BrowserAIChatTranscript) {
            parent = value
            let newIDs = value.chat.messages.map(\.id)
            if newIDs != ids || value.chat.id != conversationID {
                ids = newIDs
                conversationID = value.chat.id
                table?.reloadData()
                scrollToBottom()
            }
            if value.chat.isResponding && polling == nil {
                polling = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        self?.refresh()
                    }
                }
            } else if !value.chat.isResponding {
                polling?.cancel()
                polling = nil
                refresh()
            }
        }
        func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
            (parent?.chat.messages.count ?? 0) + 1 + ((parent?.chat.messages.isEmpty ?? false) ? 1 : 0)
        }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = (tableView.dequeueReusableCell(withIdentifier: "chat") as? TranscriptUIKitCell) ?? TranscriptUIKitCell(style: .default, reuseIdentifier: "chat")
            guard let parent else { return cell }
            let index = indexPath.row
            if parent.chat.messages.isEmpty && index == 0 {
                cell.configureWelcome()
            } else if index == tableView.numberOfRows(inSection: 0) - 1 {
                cell.configureStream(parent.chat, retry: parent.retry, open: { parent.browser.openHistoryURL($0, inBackground: false) })
            } else {
                cell.configure(parent.chat.messages[index], tint: UIColor(parent.browser.theme.tabColor),
                    open: { parent.browser.openHistoryURL($0, inBackground: false) },
                    artifact: { item in
                        do { try BrowserWebsiteAugment.open(item, in: parent.browser) }
                        catch { parent.browser.session.toastManager.show(symbol: "exclamationmark.triangle", message: error.localizedDescription) }
                    })
            }
            return cell
        }
        private func refresh() {
            guard let parent, let table else { return }
            let chat = parent.chat
            let value = chat.preview + chat.activity + String(chat.isResponding) + String(chat.canRetry) +
                chat.toolCalls.map(\.status).joined() + (chat.error ?? "")
            guard value != streamRevision else { return }
            streamRevision = value
            let nearBottom = table.contentOffset.y + table.bounds.height >= table.contentSize.height - 48
            table.reloadRows(at: [IndexPath(row: table.numberOfRows(inSection: 0) - 1, section: 0)], with: .none)
            if nearBottom { scrollToBottom() }
        }
        private func scrollToBottom() {
            guard let table, table.numberOfRows(inSection: 0) > 0 else { return }
            table.layoutIfNeeded()
            table.scrollToRow(at: IndexPath(row: table.numberOfRows(inSection: 0) - 1, section: 0), at: .bottom, animated: false)
        }
        func stop() { polling?.cancel(); polling = nil; parent = nil; table?.dataSource = nil; table?.delegate = nil }
    }
}

@MainActor private final class TranscriptUIKitCell: UITableViewCell {
    private let stack = UIStackView()
    private var actions: [UIAction] = []
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func reset() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actions.removeAll()
    }
    private func text(_ string: String, size: CGFloat = 14, secondary: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = string
        label.font = .systemFont(ofSize: size)
        label.textColor = secondary ? .secondaryLabel : .label
        label.numberOfLines = 0
        return label
    }
    private func tools(_ calls: [BrowserAIChat.ToolActivity]) {
        for call in calls {
            let action = BrowserAIAction(rawValue: call.name)
            let line = text((action?.title ?? call.name.replacingOccurrences(of: "_", with: " ").capitalized), size: 12, secondary: true)
            line.accessibilityIdentifier = "ai-chat-tool-\(call.id)"
            stack.addArrangedSubview(line)
        }
    }
    private func markdown(_ value: String, open: @escaping (URL) -> Void) {
        let field = UITextView()
        field.backgroundColor = .clear
        field.isEditable = false
        field.isScrollEnabled = false
        field.textContainerInset = .zero
        field.textContainer.lineFragmentPadding = 0
        field.attributedText = NSAttributedString((try? AttributedString(markdown: value)) ?? AttributedString(value))
        field.font = .preferredFont(forTextStyle: .body)
        field.dataDetectorTypes = [.link]
        field.delegate = nil
        stack.addArrangedSubview(field)
    }
    func configureWelcome() {
        reset()
        stack.addArrangedSubview(text("Work with this page", size: 19))
        stack.addArrangedSubview(text("Ask a question, summarise, or change what’s shown. Use @ to add another tab.", secondary: true))
    }
    func configure(_ message: BrowserAIChat.Message, tint: UIColor, open: @escaping (URL) -> Void,
                   artifact: @escaping (BrowserWebsiteAugmentArtifact) -> Void) {
        reset()
        if !message.attachments.isEmpty {
            let scroller = UIScrollView()
            scroller.showsHorizontalScrollIndicator = false
            scroller.heightAnchor.constraint(equalToConstant: 90).isActive = true
            for (index, attachment) in message.attachments.enumerated() {
                let image = UIImageView(image: attachment.image?.data.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "doc.text"))
                image.contentMode = .scaleAspectFit
                image.frame = CGRect(x: index * 88, y: 0, width: 80, height: 64)
                scroller.addSubview(image)
                let name = text(attachment.name, size: 10)
                name.frame = CGRect(x: index * 88, y: 68, width: 80, height: 16)
                scroller.addSubview(name)
            }
            scroller.contentSize = CGSize(width: CGFloat(message.attachments.count * 88), height: 90)
            stack.addArrangedSubview(scroller)
        }
        if message.isUser {
            let body = text(message.text)
            body.textColor = UIColor.label.withAlphaComponent(0.85)
            let bubble = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            bubble.layer.cornerRadius = 16
            bubble.clipsToBounds = true
            body.translatesAutoresizingMaskIntoConstraints = false
            bubble.contentView.addSubview(body)
            NSLayoutConstraint.activate([
                body.topAnchor.constraint(equalTo: bubble.contentView.topAnchor, constant: 12),
                body.bottomAnchor.constraint(equalTo: bubble.contentView.bottomAnchor, constant: -12),
                body.leadingAnchor.constraint(equalTo: bubble.contentView.leadingAnchor, constant: 12),
                body.trailingAnchor.constraint(equalTo: bubble.contentView.trailingAnchor, constant: -12)
            ])
            stack.addArrangedSubview(bubble)
        } else {
            if let calls = message.toolCalls { tools(calls) }
            if !message.text.isEmpty { markdown(message.text, open: open) }
            for item in message.augmentArtifacts ?? [] {
                let button = UIButton(type: .system)
                button.configuration = .tinted()
                button.configuration?.title = item.title
                button.configuration?.image = UIImage(systemName: "rectangle.3.group")
                button.accessibilityIdentifier = "ai-chat-artifact-\(item.id)"
                button.addAction(UIAction { _ in artifact(item) }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
        }
    }
    func configureStream(_ chat: BrowserAIChat, retry: @escaping () -> Void, open: @escaping (URL) -> Void) {
        reset()
        if chat.isResponding {
            tools(chat.toolCalls)
            if chat.preview.isEmpty { stack.addArrangedSubview(text("✧  " + chat.activity, size: 12, secondary: true)) }
            else { markdown(chat.preview, open: open) }
        } else if chat.error != nil, !chat.toolCalls.isEmpty,
                  chat.messages.last?.toolCalls?.last?.id != chat.toolCalls.last?.id {
            tools(chat.toolCalls)
        }
        if chat.canRetry {
            let button = UIButton(type: .system)
            button.setTitle("Retry Message", for: .normal)
            button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
            button.addAction(UIAction { _ in retry() }, for: .touchUpInside)
            button.accessibilityIdentifier = "ai-chat-retry"
            stack.addArrangedSubview(button)
        }
        if stack.arrangedSubviews.isEmpty {
            let spacer = UIView()
            spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
            stack.addArrangedSubview(spacer)
        }
    }
}
#endif
