import ImageIO
import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
	import AppKit
#else
	import UIKit
#endif

struct BrowserEaselView: View {
	let browser: Browser
	let tab: BrowserTab
	@State private var document: BrowserEaselDocument
	@State private var selectedID: UUID?
	@State private var importingImage = false
	@State private var editorError: String?
	@State private var showingLinkEntry = false
	@State private var linkSearch = ""
	@State private var editingTextID: UUID?
	@State private var optionIsPressed = false
	@State private var draggedCopy: (source: UUID, copy: UUID)?
	@State private var isDropTargeted = false
	@State private var linkText = "https://"
	@State private var baseline: BrowserEaselDocument.Item?
	@State private var drawingPoints: [BrowserEaselDocument.Item.Point] = []
	private enum Tool { case cursor, pen, eraser }
	@State private var activeTool: Tool = .cursor
	#if os(macOS)
		@FocusState private var canvasFocused: Bool
	#endif
	@State private var constrainsShape = false
	@State private var shiftIsPressed = false
	@Namespace private var transitions
	@Environment(\.colorScheme) private var colorScheme

	init(browser: Browser, tab: BrowserTab) {
		BrowserEaselFonts.register()
		self.browser = browser
		self.tab = tab
		_document = State(initialValue: tab.easelDocument)
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			GeometryReader { geometry in
				ScrollView([.horizontal, .vertical]) {
					canvasContents(width: canvasWidth(geometry.size.width), viewportHeight: geometry.size.height)
				}
				.scrollDisabled(activeTool != .cursor)
			}
			if let item = document.items.first(where: { $0.id == selectedID }) {
				selectionControls(item).padding(12)
			}
		}
		.overlay(alignment: .bottomTrailing) {
			toolbar.padding(12)
		}
		#if os(macOS)
		.focusable()
		.focused($canvasFocused)
		.onDeleteCommand { deleteSelectedItem() }
		.onExitCommand {
			selectedID = nil
			editingTextID = nil
			activeTool = .cursor
			baseline = nil
			drawingPoints = []
		}
		#endif
		.onChange(of: activeTool) { _, _ in
			editingTextID = nil
			baseline = nil
			drawingPoints = []
		}
		.onChange(of: document) { _, value in
			if !tab.updateEasel(value) {
				document = tab.easelDocument
				editorError = "This change exceeds the easel's content limits. The previous content has been kept."
			}
		}
		.onChange(of: tab.easelDocument) { _, value in
			if value != document {
				document = value
			}
		}
		.background {
			#if os(macOS)
				EaselPointerModifiers { constrainsShape = $0 }
					.allowsHitTesting(false)
			#endif
		}
		#if os(macOS)
		.onModifierKeysChanged(mask: [.shift, .option]) { _, modifiers in
			shiftIsPressed = modifiers.contains(.shift)
			optionIsPressed = modifiers.contains(.option)
		}
		#endif
		.disabled(!browser.isHydrationFinished)
		.accessibilityIdentifier("easel-editor")
		.fileImporter(isPresented: $importingImage, allowedContentTypes: [.image], onCompletion: importImage)
		.alert("Easel", isPresented: Binding(
			get: { editorError != nil },
			set: {
				if !$0 {
					editorError = nil
				}
			}
		)) {
			Button(role: .cancel) {} label: { Label("OK", systemImage: "checkmark") }
		} message: {
			Text(editorError ?? "The change could not be saved.")
		}
		.sheet(isPresented: $showingLinkEntry) {
			NavigationStack {
				List {
					Section("Open Tabs") {
						ForEach(linkableTabs, id: \.id) { openTab in
							if let url = openTab.currentURL {
								Button {
									linkText = BrowserAddress.withoutCredentials(url).absoluteString
									addLink()
								} label: {
									VStack(alignment: .leading, spacing: 3) {
										Text(openTab.title).lineLimit(1)
										Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
									}
								}
								.accessibilityIdentifier("easel-link-tab-\(openTab.id)")
							}
						}
					}
					Section("Custom URL") {
						TextField("https://example.com", text: $linkText)
							.accessibilityIdentifier("easel-link-url")
					}
				}
				.searchable(text: $linkSearch, prompt: "Search open tabs")
				.navigationTitle("Add Link")
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Cancel") { showingLinkEntry = false }
					}
					ToolbarItem(placement: .confirmationAction) {
						Button("Add URL", systemImage: "plus", action: addLink)
							.disabled(URL(string: linkText).map(BrowserEaselDocument.isSafeLink) != true)
							.accessibilityIdentifier("easel-confirm-link")
					}
				}
			}
			#if os(macOS)
			.frame(width: 480, height: 490)
			#else
			.navigationTransition(.zoom(sourceID: "add-link", in: transitions))
			#endif
		}
	}

	/// Selection leaves scrolling and object drags to the underlying canvas.
	/// Ink gestures only run while the pen or eraser tool is active.
	@ViewBuilder
	private func canvasContents(width: CGFloat, viewportHeight: CGFloat) -> some View {
		let surface = ZStack(alignment: .topLeading) {
			Color.clear.contentShape(Rectangle()).onTapGesture { selectedID = nil; editingTextID = nil }
			ForEach(document.items) { item in
				itemView(item, canvasWidth: width)
			}
			if !drawingPoints.isEmpty {
				smoothPath(drawingPoints)
					.stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
					.allowsHitTesting(false)
			}
		}
		.frame(width: width, height: canvasHeight(viewportHeight), alignment: .topLeading)
		.contentShape(Rectangle())
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Easel canvas")
		.accessibilityIdentifier("easel-canvas")
		.onDrop(of: [.image, .fileURL, .url], isTargeted: $isDropTargeted) { providers, location in
			receiveDrop(providers, at: location)
		}
		if activeTool == .cursor {
			surface
		} else {
			surface.highPriorityGesture(DragGesture(minimumDistance: 0)
				.onChanged { value in
					if activeTool == .pen, drawingPoints.count < 10000 {
						drawingPoints.append(.init(x: value.location.x, y: value.location.y))
					} else if activeTool == .eraser {
						erase(at: value.location)
					}
				}
				.onEnded { _ in if activeTool == .pen { finishDrawing() } })
		}
	}

	private var toolbar: some View {
		HStack(spacing: 10) {
			Button("Cursor", systemImage: "cursorarrow") { activeTool = .cursor }
				.accessibilityIdentifier("easel-cursor")
				.tint(activeTool == .cursor ? .accentColor : .primary)
			Button("Pen", systemImage: "pencil.tip") { activeTool = .pen; selectedID = nil }
				.accessibilityIdentifier("easel-draw")
				.tint(activeTool == .pen ? .accentColor : .primary)
			Button("Eraser", systemImage: "eraser") { activeTool = .eraser; selectedID = nil }
				.accessibilityIdentifier("easel-eraser")
				.tint(activeTool == .eraser ? .accentColor : .primary)
			Divider().frame(height: 22)
			Button("Text", systemImage: "textformat") { activeTool = .cursor; add(.text) }
				.accessibilityIdentifier("easel-add-text")
			Button("Image", systemImage: "photo") { activeTool = .cursor; importingImage = true }
				.accessibilityIdentifier("easel-add-image")
			Button("Link", systemImage: "link") {
				activeTool = .cursor
				let source = browser.splitLeftTabID.flatMap { browser.tab(withID: $0)?.currentURL } ?? browser.selectedTab?.currentURL
				linkText = source.map(BrowserAddress.withoutCredentials)?.absoluteString ?? "https://"
				linkSearch = ""
				showingLinkEntry = true
			}
			.matchedTransitionSource(id: "add-link", in: transitions)
			.accessibilityIdentifier("easel-add-link")
			Button("Rectangle", systemImage: "rectangle") { activeTool = .cursor; add(.rectangle) }
				.accessibilityIdentifier("easel-add-rectangle")
			Button("Ellipse", systemImage: "circle") { activeTool = .cursor; add(.ellipse) }
				.accessibilityIdentifier("easel-add-ellipse")
			Button("Line", systemImage: "line.diagonal") { activeTool = .cursor; add(.line) }
				.accessibilityIdentifier("easel-add-line")
			Button("Arrow", systemImage: "arrow.up.right") { activeTool = .cursor; add(.arrow) }
				.accessibilityIdentifier("easel-add-arrow")
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.plain)
		.padding(12)
		.glassEffect(.regular, in: Capsule())
		.accessibilityIdentifier("easel-tool-rail")
	}

	private func selectionControls(_ item: BrowserEaselDocument.Item) -> some View {
		VStack(spacing: 10) {
			if item.kind == .text {
				Button("Change Font", systemImage: "textformat.alt") {
					edit(item.id) { value in
						let fonts = BrowserEaselDocument.Item.Font.allCases
						value.font = fonts[((fonts.firstIndex(of: value.font) ?? 0) + 1) % fonts.count]
					}
				}
				.help(item.font.displayName)
				.accessibilityValue(item.font.displayName)
				.accessibilityIdentifier("easel-font")
				Button("Smaller Text", systemImage: "minus") { adjustSize(item, by: -1) }
					.disabled(item.size == .small)
					.accessibilityIdentifier("easel-smaller-text")
				Button("Larger Text", systemImage: "plus") { adjustSize(item, by: 1) }
					.disabled(item.size == .huge)
					.accessibilityIdentifier("easel-larger-text")
			}
			if item.kind != .image && item.kind != .link {
				Button("Cycle Colour", systemImage: "paintpalette") {
					edit(item.id) { $0.background = $0.background.next }
				}
				.accessibilityValue(item.background.rawValue)
				.accessibilityIdentifier("easel-colour")
			}
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.plain)
		.padding(12)
		.glassEffect(.regular, in: Capsule())
		.accessibilityIdentifier("easel-item-controls")
	}

	private func canvasWidth(_ viewport: CGFloat) -> CGFloat {
		min(20000, max(1600, viewport, document.items.map { $0.x + $0.width + 400 }.max() ?? 0))
	}

	private func canvasHeight(_ viewport: CGFloat) -> CGFloat {
		min(1_000_000, max(1200, viewport, document.items.map { $0.y + $0.height + 400 }.max() ?? 0))
	}

	private var linkableTabs: [BrowserTab] {
		browser.tabs.filter { candidate in
			guard let url = candidate.currentURL, BrowserEaselDocument.isSafeLink(url) else { return false }
			let query = linkSearch.trimmingCharacters(in: .whitespacesAndNewlines)
			return query.isEmpty || candidate.title.localizedCaseInsensitiveContains(query) || url.absoluteString.localizedCaseInsensitiveContains(query)
		}
	}

	private func ink(_ item: BrowserEaselDocument.Item) -> Color {
		item.background == .none ? .primary : item.background.isLight ? .black : .white
	}

	private func palette(_ item: BrowserEaselDocument.Item) -> Color {
		guard let value = UInt32(item.background.rawValue, radix: 16) else { return .primary }
		return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
	}

	private func itemView(_ item: BrowserEaselDocument.Item, canvasWidth: CGFloat) -> some View {
		itemContent(item, canvasWidth: canvasWidth)
			.frame(width: item.width, height: item.height, alignment: .topLeading)
			.contentShape(Rectangle())
			.overlay {
				if selectedID == item.id {
					RoundedRectangle(cornerRadius: 6).strokeBorder(.tint, lineWidth: 1)
						.allowsHitTesting(false)
				}
			}
			.overlay(alignment: .bottomTrailing) {
				if selectedID == item.id {
					Circle().fill(.tint).frame(width: 12, height: 12)
						.padding(5)
						.contentShape(Rectangle())
						.highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
							.onChanged { resize(item, translation: $0.translation, canvasWidth: canvasWidth) }
							.onEnded { _ in baseline = nil })
						.accessibilityLabel("Resize item")
						.accessibilityIdentifier("easel-resize-\(item.id)")
				}
			}
			.overlay(alignment: .top) {
				if selectedID == item.id, [.image, .rectangle, .ellipse].contains(item.kind) {
					VStack(spacing: 0) {
						Circle().fill(.tint).frame(width: 14, height: 14)
							.contentShape(Rectangle())
							.highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
								.onChanged { rotate(item, translation: $0.translation) }
								.onEnded { _ in baseline = nil })
							.accessibilityLabel("Rotate item")
							.accessibilityIdentifier("easel-rotate-\(item.id)")
						Rectangle().fill(.tint).frame(width: 1, height: 14)
							.allowsHitTesting(false)
					}
					.offset(y: -28)
				}
			}
			.rotationEffect(.degrees(item.rotation))
			.offset(x: item.x, y: item.y)
			.gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
				.onChanged { value in
					guard activeTool == .cursor, editingTextID != item.id else { return }
					drag(item, translation: value.translation, canvasWidth: canvasWidth)
				}
				.onEnded { _ in baseline = nil; draggedCopy = nil })
			.onTapGesture {
				guard activeTool == .cursor else { return }
				selectedID = item.id
				if editingTextID != item.id { editingTextID = nil }
				browser.selectTab(tab.id)
				#if os(macOS)
					if editingTextID == nil { canvasFocused = true }
				#endif
			}
			.highPriorityGesture(TapGesture(count: 2).onEnded {
				guard activeTool == .cursor else { return }
				selectedID = item.id
				if item.kind == .text {
					editingTextID = item.id
				} else if item.kind == .link, let url = item.url {
					browser.openEaselLink(url, in: tab)
				}
			})
			.contextMenu {
				Button("Bring to Front", systemImage: "square.2.layers.3d.top.filled") {
					reorder(item.id, front: true)
				}
				Button("Send to Back", systemImage: "square.2.layers.3d.bottom.filled") {
					reorder(item.id, front: false)
				}
				Divider()
				Button("Delete Item", systemImage: "trash", role: .destructive) {
					deleteItem(item.id)
				}
			}
			.allowsHitTesting(activeTool == .cursor)
			.accessibilityElement(children: .contain)
			.accessibilityIdentifier("easel-item-\(item.id)")
	}

	@ViewBuilder
	private func itemContent(_ item: BrowserEaselDocument.Item, canvasWidth: CGFloat) -> some View {
		switch item.kind {
			case .text:
				Group {
					if editingTextID == item.id {
						textEditor(item)
					} else {
						Text(item.text.isEmpty ? "Double-click to edit" : item.text)
							.font(.custom(item.font.rawValue, size: CGFloat(item.size.rawValue)))
							.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
					}
				}
				.foregroundStyle(ink(item))
				.padding(8)
				.frame(width: item.width, height: item.height, alignment: .topLeading)
				.background(item.background == .none ? Color.clear : palette(item), in: RoundedRectangle(cornerRadius: 6))
				.accessibilityLabel("Easel text")
			case .rectangle:
				Rectangle().stroke(palette(item), lineWidth: 1.5).frame(height: item.height)
			case .ellipse:
				Ellipse().stroke(palette(item), lineWidth: 1.5).frame(height: item.height)
			case .line, .arrow:
				ZStack(alignment: .topLeading) {
					linePath(item).stroke(palette(item), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
					if selectedID == item.id {
						ForEach(0 ..< 2, id: \.self) { index in
							endpoint(item, index: index, canvasWidth: canvasWidth)
						}
					}
				}.frame(height: item.height)
			case .freehand:
				smoothPath(item.points).stroke(palette(item), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
					.frame(height: item.height)
			case .image:
				if let data = item.imageData {
					EaselImageView(data: data)
						.frame(height: item.height)
				}
			case .link:
				if let url = item.url {
					EaselLinkCard(url: url)
						.frame(width: item.width, height: item.height, alignment: .topLeading)
						.clipped()
						.accessibilityLabel("Easel link to \(url.host ?? url.absoluteString)")
						.accessibilityIdentifier("easel-open-link-\(item.id)")
				}
		}
	}

	@ViewBuilder
	private func textEditor(_ item: BrowserEaselDocument.Item) -> some View {
		let binding = Binding<String>(
			get: { document.items.first(where: { $0.id == item.id })?.text ?? "" },
			set: { text in edit(item.id) { $0.text = text } }
		)
		#if os(macOS)
			EaselTextEditor(
				text: binding,
				fontName: item.font.rawValue,
				fontSize: CGFloat(item.size.rawValue),
				color: NSColor(ink(item)),
				onSelect: {
					selectedID = item.id
					browser.selectTab(tab.id)
				},
				onFinish: { editingTextID = nil }
			)
		#else
			TextField("Text", text: binding, axis: .vertical)
				.textFieldStyle(.plain)
				.font(.custom(item.font.rawValue, size: CGFloat(item.size.rawValue)))
				.lineSpacing(CGFloat(item.size.rawValue) * 0.5)
		#endif
	}

	private func endpoint(_ item: BrowserEaselDocument.Item, index: Int, canvasWidth: CGFloat) -> some View {
		let point = item.points[index]
		return Circle().fill(.tint).frame(width: 12, height: 12)
			.position(x: point.x, y: point.y)
			.highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
				if baseline?.id != item.id {
					baseline = item
				}
				guard let baseline else { return }
				edit(item.id) {
					$0 = baseline
					$0.moveEndpoint(index, by: .init(x: value.translation.width, y: value.translation.height), withinWidth: canvasWidth)
				}
			}.onEnded { _ in
				edit(item.id) { $0.orderEndpoints() }
				baseline = nil
			})
			.accessibilityElement()
			.accessibilityLabel(index == 0 ? "Line start" : "Line end")
			.accessibilityIdentifier("easel-endpoint-\(index)-\(item.id)")
	}

	private func linePath(_ item: BrowserEaselDocument.Item) -> Path {
		Path { path in
			guard item.points.count == 2 else { return }
			let start = CGPoint(x: item.points[0].x, y: item.points[0].y)
			let end = CGPoint(x: item.points[1].x, y: item.points[1].y)
			path.move(to: start)
			path.addLine(to: end)
			if item.kind == .arrow {
				let angle = atan2(end.y - start.y, end.x - start.x)
				for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
					path.move(to: end)
					path.addLine(to: CGPoint(x: end.x - cos(angle + offset) * 10, y: end.y - sin(angle + offset) * 10))
				}
			}
		}
	}

	private func smoothPath(_ points: [BrowserEaselDocument.Item.Point]) -> Path {
		Path { path in
			guard let first = points.first else { return }
			path.move(to: CGPoint(x: first.x, y: first.y))
			for index in points.indices.dropFirst() {
				let previous = points[index - 1]
				let point = points[index]
				path.addQuadCurve(to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: CGPoint(x: previous.x, y: previous.y))
			}
			if let last = points.last {
				path.addLine(to: CGPoint(x: last.x, y: last.y))
			}
		}
	}

	private func add(_ kind: BrowserEaselDocument.Item.Kind) {
		var item = BrowserEaselDocument.Item(kind: kind)
		item.y += Double(document.items.count) * 30
		item.constrainShape(constrainsShape || shiftIsPressed)
		if [.line, .arrow].contains(kind) {
			item.points = [.init(x: 0, y: 0), .init(x: 240, y: 120)]
		}
		append(item)
	}

	private func append(_ item: BrowserEaselDocument.Item) {
		var next = document
		next.items.append(item)
		guard next.isValid else {
			editorError = "This easel is full. Its existing content has been kept."
			return
		}
		document = next
		selectedID = item.id
		browser.selectTab(tab.id)
	}

	private func addLink() {
		guard let url = URL(string: linkText), BrowserEaselDocument.isSafeLink(url) else { return }
		var item = BrowserEaselDocument.Item(kind: .link)
		item.url = url
		append(item)
		showingLinkEntry = false
	}

	private func edit(_ id: UUID, change: (inout BrowserEaselDocument.Item) -> Void) {
		guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
		var next = document
		change(&next.items[index])
		guard next.isValid else {
			editorError = "This change exceeds the easel's content limits."
			return
		}
		document = next
	}

	private func reorder(_ id: UUID, front: Bool) {
		guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
		let item = document.items.remove(at: index)
		document.items.insert(item, at: front ? document.items.count : 0)
	}

	private func deleteItem(_ id: UUID) {
		document.items.removeAll { $0.id == id }
		if selectedID == id { selectedID = nil }
		if editingTextID == id { editingTextID = nil }
	}

	private func deleteSelectedItem() {
		guard activeTool == .cursor, editingTextID == nil, let selectedID else { return }
		deleteItem(selectedID)
	}

	/// Erase complete freehand strokes at the pointer; other objects use Delete.
	private func erase(at point: CGPoint) {
		document.items.removeAll { item in
			guard item.kind == .freehand, item.points.count > 1 else { return false }
			let local = CGPoint(x: point.x - item.x, y: point.y - item.y)
			for index in 1 ..< item.points.count {
				let a = CGPoint(x: item.points[index - 1].x, y: item.points[index - 1].y)
				let b = CGPoint(x: item.points[index].x, y: item.points[index].y)
				let dx = b.x - a.x, dy = b.y - a.y
				let length = dx * dx + dy * dy
				let fraction = length > 0 ? min(1, max(0, ((local.x - a.x) * dx + (local.y - a.y) * dy) / length)) : 0
				if hypot(local.x - a.x - dx * fraction, local.y - a.y - dy * fraction) <= 14 {
					return true
				}
			}
			return false
		}
		if let selectedID, !document.items.contains(where: { $0.id == selectedID }) {
			self.selectedID = nil
		}
	}

	private func adjustSize(_ item: BrowserEaselDocument.Item, by offset: Int) {
		let sizes = BrowserEaselDocument.Item.Size.allCases
		let index = sizes.firstIndex(of: item.size) ?? 2
		edit(item.id) { $0.size = sizes[min(max(index + offset, 0), sizes.count - 1)] }
	}

	private func drag(_ item: BrowserEaselDocument.Item, translation: CGSize, canvasWidth: CGFloat) {
		if baseline?.id != item.id && draggedCopy?.source != item.id {
			#if os(macOS)
				let duplicate = optionIsPressed || NSEvent.modifierFlags.contains(.option)
			#else
				let duplicate = optionIsPressed
			#endif
			if duplicate {
				var copy = item
				copy.id = UUID()
				append(copy)
				draggedCopy = (source: item.id, copy: copy.id)
				baseline = copy
			} else {
				baseline = item
			}
		}
		if let copy = draggedCopy, copy.source == item.id,
		   let duplicated = document.items.first(where: { $0.id == copy.copy }) {
			move(duplicated, translation: translation, canvasWidth: canvasWidth)
		} else {
			move(item, translation: translation, canvasWidth: canvasWidth)
		}
	}

	private func rotate(_ item: BrowserEaselDocument.Item, translation: CGSize) {
		if baseline?.id != item.id { baseline = item }
		guard let baseline else { return }
		edit(item.id) {
			$0.rotation = min(360, max(-360, baseline.rotation + Double(translation.width) * 0.7))
		}
	}

	private func move(_ item: BrowserEaselDocument.Item, translation: CGSize, canvasWidth: CGFloat) {
		if baseline?.id != item.id { baseline = item }
		guard let baseline else { return }
		edit(item.id) {
			$0.x = min(max(0, baseline.x + translation.width), min(10000, max(0, canvasWidth - baseline.width)))
			$0.y = min(max(0, baseline.y + translation.height), 1_000_000)
		}
	}

	private func resize(_ item: BrowserEaselDocument.Item, translation: CGSize, canvasWidth: CGFloat) {
		if baseline?.id != item.id {
			baseline = item
		}
		guard let baseline else { return }
		edit(item.id) {
			$0.x = baseline.x
			$0.width = min(max(32, baseline.width + translation.width), min(10000, max(32, canvasWidth - item.x)))
			if item.kind == .image {
				$0.height = min(10000, max(1, baseline.height * $0.width / baseline.width))
			} else {
				$0.height = min(max(item.kind == .text ? 40 : 1, baseline.height + translation.height), 10000)
				if [.freehand, .line, .arrow].contains(item.kind) {
					let scaleX = $0.width / baseline.width
					let scaleY = $0.height / baseline.height
					$0.points = baseline.points.map { point in
						.init(x: point.x * scaleX, y: point.y * scaleY)
					}
				}
				$0.constrainShape(constrainsShape || shiftIsPressed)
			}
		}
	}

	private func finishDrawing() {
		guard activeTool == .pen else { return }
		defer { drawingPoints = [] }
		guard drawingPoints.count > 1 else { return }
		let minX = drawingPoints.map(\.x).min() ?? 0
		let minY = drawingPoints.map(\.y).min() ?? 0
		var item = BrowserEaselDocument.Item(kind: .freehand)
		item.x = max(0, minX)
		item.y = max(0, minY)
		item.points = drawingPoints.map { .init(x: $0.x - minX, y: $0.y - minY) }
		item.width = max(32, item.points.map(\.x).max() ?? 32)
		item.height = max(1, item.points.map(\.y).max() ?? 1)
		append(item)
	}

	private func receiveDrop(_ providers: [NSItemProvider], at location: CGPoint) -> Bool {
		for provider in providers {
			if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
				_ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
					guard let data else { return }
					Task { @MainActor in addImageData(data, at: location) }
				}
				return true
			}
			let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
				? UTType.fileURL.identifier : UTType.url.identifier
			guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
			_ = provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
				let url: URL?
				switch value {
					case let item as URL: url = item
					case let item as Data:
						url = String(data: item, encoding: .utf8).flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
					case let item as String: url = URL(string: item)
					default: url = nil
				}
				guard let url else { return }
				if url.isFileURL {
					let data = try? Data(contentsOf: url)
					Task { @MainActor in
						if let data { addImageData(data, at: location) }
					}
				} else {
					Task { @MainActor in addDroppedLink(url, at: location) }
				}
			}
			return true
		}
		return false
	}

	private func addDroppedLink(_ url: URL, at point: CGPoint) {
		guard BrowserEaselDocument.isSafeLink(url) else { return }
		var item = BrowserEaselDocument.Item(kind: .link)
		item.url = BrowserAddress.withoutCredentials(url)
		item.x = max(0, min(10000 - item.width, Double(point.x)))
		item.y = max(0, min(1_000_000 - item.height, Double(point.y)))
		append(item)
	}

	private func importImage(_ result: Result<URL, Error>) {
		do {
			let url = try result.get()
			let access = url.startAccessingSecurityScopedResource()
			defer {
				if access { url.stopAccessingSecurityScopedResource() }
			}
			addImageData(try Data(contentsOf: url))
		} catch {
			if (error as NSError).code != NSUserCancelledError {
				editorError = error.localizedDescription
			}
		}
	}

	private func addImageData(_ data: Data, at point: CGPoint? = nil) {
		guard data.count <= 20_000_000 else {
			editorError = "Choose an image smaller than 20 MB."
			return
		}
		guard let source = CGImageSourceCreateWithData(data as CFData, nil),
		      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
		      	kCGImageSourceCreateThumbnailFromImageAlways: true,
		      	kCGImageSourceCreateThumbnailWithTransform: true,
		      	kCGImageSourceThumbnailMaxPixelSize: 1600,
		      ] as CFDictionary)
		else {
			editorError = "This image could not be decoded."
			return
		}
		#if os(macOS)
			let bitmap = NSBitmapImageRep(cgImage: thumbnail)
			let encoded = bitmap.representation(using: bitmap.hasAlpha ? .png : .jpeg, properties: [.compressionFactor: 0.75])
		#else
			let encoded = UIImage(cgImage: thumbnail).pngData()
		#endif
		guard let encoded, encoded.count <= 1_000_000 else {
			editorError = "The compressed image must be smaller than 1 MB."
			return
		}
		var item = BrowserEaselDocument.Item(kind: .image)
		item.imageData = encoded
		item.height = item.width * Double(thumbnail.height) / Double(thumbnail.width)
		if let point {
			item.x = max(0, min(10000 - item.width, Double(point.x)))
			item.y = max(0, min(1_000_000 - item.height, Double(point.y)))
		}
		append(item)
	}

}

private struct EaselLinkCard: View {
	let url: URL
	@State private var title: String?
	@State private var imageData: Data?

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			#if os(macOS)
				if let imageData, let image = NSImage(data: imageData) {
					Image(nsImage: image).resizable().scaledToFill().frame(height: 100).clipped()
				}
			#endif
			Label(title ?? url.host ?? "Web Page", systemImage: "link")
				.font(.headline).lineLimit(2)
			Text(url.host ?? url.absoluteString).font(.caption).foregroundStyle(.secondary)
		}
		.padding(12)
		.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
		.task(id: url) {
			let provider = LPMetadataProvider()
			provider.timeout = 10
			do {
				let metadata = try await provider.startFetchingMetadata(for: url)
				title = metadata.title
				if let image = metadata.imageProvider {
					image.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
						Task { @MainActor in imageData = data }
					}
				}
			} catch {
				title = url.host
			}
		}
	}
}
