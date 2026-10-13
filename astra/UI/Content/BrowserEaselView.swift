import ImageIO
import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
	import AppKit
	import InfiniteCanvas
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
	@State private var linkText = "https://"
	@State private var baseline: BrowserEaselDocument.Item?
	@State private var drawingPoints: [BrowserEaselDocument.Item.Point] = []
	private enum Tool { case cursor, pen, eraser }
	@State private var activeTool: Tool = .cursor
	#if os(macOS)
		@StateObject private var canvasController = InfiniteCanvasController()
		@FocusState private var canvasFocused: Bool
	#endif
	@State private var constrainsShape = false
	@State private var shiftIsPressed = false
	@State private var measuredHeights: [UUID: CGFloat] = [:]
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
				#if os(macOS)
				InfiniteCanvas(controller: canvasController) {
					canvasContents(width: max(1200, geometry.size.width), viewportHeight: geometry.size.height)
						.canvasPosition(position: .zero, controller: canvasController)
				}
				#else
				ScrollView([.horizontal, .vertical]) {
					canvasContents(width: max(1200, geometry.size.width), viewportHeight: geometry.size.height)
				}
				.scrollDisabled(activeTool != .cursor)
				#endif
			}
			HStack(alignment: .top, spacing: 10) {
				toolbar
				if let item = document.items.first(where: { $0.id == selectedID }) {
					selectionControls(item)
				}
			}
			.padding(12)
		}
		#if os(macOS)
		.focusable()
		.focused($canvasFocused)
		.onDeleteCommand { deleteSelectedItem() }
		#endif
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
		.onModifierKeysChanged(mask: .shift) { _, modifiers in
			shiftIsPressed = modifiers.contains(.shift)
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
					Section("Link URL") {
						TextField("https://example.com", text: $linkText)
							.accessibilityIdentifier("easel-link-url")
					}
				}
				.navigationTitle("Add Link")
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button(role: .cancel) { showingLinkEntry = false }
					}
					ToolbarItem(placement: .confirmationAction) {
						Button("Add Link", systemImage: "plus", role: .confirm, action: addLink)
							.buttonStyle(.glassProminent)
							.disabled(URL(string: linkText).map(BrowserEaselDocument.isSafeLink) != true)
							.accessibilityIdentifier("easel-confirm-link")
					}
				}
			}
			#if os(macOS)
			.frame(width: 440, height: 300)
			#endif
			.presentationDetents([.fraction(0.5)])
			#if os(iOS)
				.navigationTransition(.zoom(sourceID: "add-link", in: transitions))
			#endif
		}
	}

	/// Selection leaves scrolling and object drags to the underlying canvas.
	/// Ink gestures only run while the pen or eraser tool is active.
	@ViewBuilder
	private func canvasContents(width: CGFloat, viewportHeight: CGFloat) -> some View {
		let surface = ZStack(alignment: .topLeading) {
			Color.clear.contentShape(Rectangle()).onTapGesture { selectedID = nil }
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
		VStack(spacing: 10) {
			Button("Cursor", systemImage: "cursorarrow") { activeTool = .cursor }
				.accessibilityIdentifier("easel-cursor")
				.tint(activeTool == .cursor ? .accentColor : .primary)
			Button("Pen", systemImage: "pencil.tip") { activeTool = .pen; selectedID = nil }
				.accessibilityIdentifier("easel-draw")
				.tint(activeTool == .pen ? .accentColor : .primary)
			Button("Eraser", systemImage: "eraser") { activeTool = .eraser; selectedID = nil }
				.accessibilityIdentifier("easel-eraser")
				.tint(activeTool == .eraser ? .accentColor : .primary)
			Divider().frame(width: 22)
			Button("Text", systemImage: "textformat") { activeTool = .cursor; add(.text) }
				.accessibilityIdentifier("easel-add-text")
			Button("Image", systemImage: "photo") { activeTool = .cursor; importingImage = true }
				.accessibilityIdentifier("easel-add-image")
			Button("Link", systemImage: "link") {
				activeTool = .cursor
				let source = browser.splitLeftTabID.flatMap { browser.tab(withID: $0)?.currentURL } ?? browser.selectedTab?.currentURL
				linkText = source.map(BrowserAddress.withoutCredentials)?.absoluteString ?? "https://"
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
			if item.kind == .image {
				Slider(value: Binding(
					get: { document.items.first(where: { $0.id == item.id })?.rotation ?? 0 },
					set: { angle in edit(item.id) { $0.rotation = angle } }
				), in: -180 ... 180)
					.frame(width: 92)
					.accessibilityLabel("Image rotation")
					.accessibilityIdentifier("easel-image-rotation")
			}
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.plain)
		.padding(12)
		.glassEffect(.regular, in: Capsule())
		.accessibilityIdentifier("easel-item-controls")
	}

	private func canvasHeight(_ viewport: CGFloat) -> CGFloat {
		max(viewport, document.items.map { $0.y + (measuredHeights[$0.id] ?? $0.height) + 400 }.max() ?? 1200)
	}

	private func ink(_ item: BrowserEaselDocument.Item) -> Color {
		item.background == .none ? .primary : item.background.isLight ? .black : .white
	}

	private func palette(_ item: BrowserEaselDocument.Item) -> Color {
		guard let value = UInt32(item.background.rawValue, radix: 16) else { return .primary }
		return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
	}

	private func itemView(_ savedItem: BrowserEaselDocument.Item, canvasWidth: CGFloat) -> some View {
		// Keep items reachable in a narrow split without rewriting their saved placement.
		var item = savedItem
		let width = min(item.width, max(32, canvasWidth))
		let scale = width / item.width
		item.width = width
		item.x = min(item.x, max(0, canvasWidth - width))
		if [.image, .freehand, .line, .arrow, .rectangle, .ellipse].contains(item.kind) {
			item.height *= scale
			item.points = item.points.map { .init(x: $0.x * scale, y: $0.y * scale) }
		}
		let displayedItem = item
		return itemContent(displayedItem, canvasWidth: canvasWidth)
			.frame(width: displayedItem.width, alignment: .topLeading)
			.fixedSize(horizontal: false, vertical: true)
			.overlay {
				if selectedID == displayedItem.id {
					RoundedRectangle(cornerRadius: 6).stroke(.tint, lineWidth: 1)
						.allowsHitTesting(false)
				}
			}
			.overlay(alignment: .topLeading) {
				if selectedID == displayedItem.id, displayedItem.kind == .text {
					Image(systemName: "arrow.up.left.and.arrow.down.right")
						.font(.system(size: 9))
						.padding(4)
						.background(.regularMaterial, in: Circle())
						.contentShape(Rectangle())
						.highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
							move(displayedItem, translation: value.translation, canvasWidth: canvasWidth)
						}.onEnded { _ in baseline = nil })
						.accessibilityLabel("Move text box")
						.accessibilityIdentifier("easel-move-text-\(displayedItem.id)")
				}
			}

			.overlay(alignment: .bottomTrailing) {
				if selectedID == displayedItem.id, ![.line, .arrow].contains(displayedItem.kind) {
					Circle().fill(.tint).frame(width: 10, height: 10)
						.padding(4)
						.contentShape(Rectangle())
						.highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
							resize(displayedItem, translation: value.translation, canvasWidth: canvasWidth)
						}.onEnded { _ in baseline = nil })
						.accessibilityElement()
						.accessibilityLabel("Resize item")
						.accessibilityIdentifier("easel-resize-\(displayedItem.id)")
						.accessibilityAdjustableAction { direction in
							resize(displayedItem, translation: CGSize(width: direction == .increment ? 20 : -20, height: 0), canvasWidth: canvasWidth)
							baseline = nil
						}
				}
			}
			.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
				measuredHeights[displayedItem.id] = height
			}
			.rotationEffect(.degrees(displayedItem.rotation), anchor: .center)
			.offset(x: displayedItem.x, y: displayedItem.y)
			.gesture(DragGesture(minimumDistance: 5, coordinateSpace: .global).onChanged { value in
				guard activeTool == .cursor else { return }
				selectedID = displayedItem.id
				move(displayedItem, translation: value.translation, canvasWidth: canvasWidth)
			}.onEnded { _ in baseline = nil })
			.onTapGesture {
				selectedID = displayedItem.id
				browser.selectTab(tab.id)
				#if os(macOS)
					if displayedItem.kind != .text {
						canvasFocused = true
					}
				#endif
			}
			.contextMenu {
				Button("Bring to Front", systemImage: "square.2.layers.3d.top.filled") {
					reorder(displayedItem.id, front: true)
				}
				Button("Send to Back", systemImage: "square.2.layers.3d.bottom.filled") {
					reorder(displayedItem.id, front: false)
				}
				Divider()
				Button("Delete Item", systemImage: "trash", role: .destructive) {
					deleteItem(displayedItem.id)
				}
			}
			.allowsHitTesting(activeTool == .cursor)
			.accessibilityElement(children: .contain)
			.accessibilityIdentifier("easel-item-\(displayedItem.id)")
	}

	@ViewBuilder
	private func itemContent(_ item: BrowserEaselDocument.Item, canvasWidth: CGFloat) -> some View {
		switch item.kind {
			case .text:
				textEditor(item)
					.foregroundStyle(ink(item))
					.padding(8)
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
					Button {
						selectedID = item.id
						browser.openEaselLink(url, in: tab)
					} label: {
						EaselLinkCard(url: url)
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Peek at \(url.host ?? url.absoluteString)")
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
			EaselTextEditor(text: binding, fontName: item.font.rawValue, fontSize: CGFloat(item.size.rawValue), color: NSColor(ink(item))) {
				selectedID = item.id
				browser.selectTab(tab.id)
			}
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
	}

	private func deleteSelectedItem() {
		guard activeTool == .cursor, let selectedID else { return }
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

	private func move(_ item: BrowserEaselDocument.Item, translation: CGSize, canvasWidth: CGFloat) {
		if baseline?.id != item.id {
			baseline = item
		}
		guard let baseline else { return }
		edit(item.id) {
			$0.x = min(max(0, baseline.x + translation.width), max(0, canvasWidth - item.width))
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
				$0.height = baseline.height * $0.width / baseline.width
			} else if item.kind != .text {
				$0.height = min(max(1, baseline.height + translation.height), 10000)
				if item.kind == .freehand {
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

	private func importImage(_ result: Result<URL, Error>) {
		do {
			let url = try result.get()
			let access = url.startAccessingSecurityScopedResource()
			defer {
				if access {
					url.stopAccessingSecurityScopedResource()
				}
			}
			let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
			guard (attributes.fileSize ?? Int.max) <= 20_000_000 else {
				editorError = "Choose an image smaller than 20 MB."
				return
			}
			let data = try Data(contentsOf: url)
			guard let source = CGImageSourceCreateWithData(data as CFData, nil),
			      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
			      	kCGImageSourceCreateThumbnailFromImageAlways: true,
			      	kCGImageSourceCreateThumbnailWithTransform: true,
			      	kCGImageSourceThumbnailMaxPixelSize: 1600,
			      ] as CFDictionary)
			else { throw CocoaError(.fileReadCorruptFile) }
			#if os(macOS)
				let bitmap = NSBitmapImageRep(cgImage: thumbnail)
				guard let encoded = bitmap.representation(using: bitmap.hasAlpha ? .png : .jpeg, properties: [.compressionFactor: 0.75]) else { throw CocoaError(.fileReadCorruptFile) }
			#else
				let image = UIImage(cgImage: thumbnail)
				guard let encoded = image.pngData() else { throw CocoaError(.fileReadCorruptFile) }
			#endif
			let size = CGSize(width: thumbnail.width, height: thumbnail.height)
			guard encoded.count <= 1_000_000 else {
				editorError = "The compressed image must be smaller than 1 MB."
				return
			}
			var item = BrowserEaselDocument.Item(kind: .image)
			item.imageData = encoded
			item.height = item.width * size.height / size.width
			append(item)
		} catch {
			if (error as NSError).code != NSUserCancelledError {
				editorError = error.localizedDescription
			}
		}
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
