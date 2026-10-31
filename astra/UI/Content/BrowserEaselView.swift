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
	let toolbarAlignment: Alignment
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
	@State private var isManipulating = false
	@GestureState private var gestureActive = false
	@GestureState private var pressedItemID: UUID? = nil
	@State private var drawingPoints: [BrowserEaselDocument.Item.Point] = []
	@State private var canvasOffset = EaselCanvasViewportOffset()
	@State private var textViewportWidth: CGFloat = 800
	private enum Tool: Equatable { case cursor, pen, eraser, shape(BrowserEaselDocument.Item.Kind) }
	@State private var shapeDraft: BrowserEaselDocument.Item?
	@State private var activeTool: Tool = .cursor
	#if os(macOS)
		@FocusState private var canvasFocused: Bool
	#endif
	@State private var constrainsShape = false
	@State private var shiftIsPressed = false
	@Namespace private var transitions
	@Environment(\.colorScheme) private var colorScheme

	init(browser: Browser, tab: BrowserTab, toolbarAlignment: Alignment = .bottomTrailing) {
		BrowserEaselFonts.register()
		self.browser = browser
		self.tab = tab
		self.toolbarAlignment = toolbarAlignment
		_document = State(initialValue: tab.easelDocument)
	}

	var body: some View {
		let selectedItem = document.items.first(where: { $0.id == selectedID })
		ZStack(alignment: .topLeading) {
			GeometryReader { geometry in
				ScrollView(.vertical) {
					canvasContents(width: canvasWidth(geometry.size.width), viewportHeight: geometry.size.height)
				}
				.onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { _, offset in
					canvasOffset.point = CGPoint(x: max(0, offset.x), y: max(0, offset.y))
				}
				.overlayPreferenceValue(EaselSelectedItemBounds.self) { anchor in
					GeometryReader { viewport in
						if let anchor,
						   let item = selectedItem,
						   ![.image, .link, .quote].contains(item.kind),
						   viewport[anchor].intersects(CGRect(origin: .zero, size: viewport.size)) {
							EaselSelectionControlsLayout(itemBounds: viewport[anchor]) {
								selectionControls(item)
							}
						}
					}
				}
				.scrollDisabled(activeTool != .cursor)
				.onAppear {
					updateTextViewport(geometry.size.width, includeFixedText: true)
					centerPendingQuote(in: geometry.size)
				}
				.onChange(of: geometry.size.width) { _, width in updateTextViewport(width) }
				.onChange(of: tab.pendingQuotePlacementID) { _, _ in
					centerPendingQuote(in: geometry.size)
				}
			}
		}
		.overlay(alignment: toolbarAlignment) {
			toolbar.padding(12)
		}
		#if os(macOS)
		.focusable()
		.focused($canvasFocused)
		.focusEffectDisabled()
		.onDeleteCommand { deleteSelectedItem() }
		.onExitCommand {
			selectedID = nil
			editingTextID = nil
			activeTool = .cursor
			baseline = nil
			drawingPoints = []
			shapeDraft = nil
		}
		#endif
		.onChange(of: activeTool) { _, _ in
			editingTextID = nil
			baseline = nil
			drawingPoints = []
			shapeDraft = nil
		}
		.onChange(of: gestureActive) { _, active in
			if !active {
				commitGesture()
				shapeDraft = nil
			}
		}
		.onChange(of: pressedItemID) { _, id in
			if let id, let item = document.items.first(where: { $0.id == id }) {
				selectItem(item)
			}
		}
		.onDisappear { commitGesture(); shapeDraft = nil; drawingPoints = [] }
		.onChange(of: isManipulating ? nil : document) { _, value in
			guard !isManipulating, let value, value != tab.easelDocument else { return }
			if !tab.updateEasel(value) {
				document = tab.easelDocument
				editorError = "This change exceeds the easel's content limits. The previous content has been kept."
			}
		}
		.onChange(of: tab.easelDocument) { _, value in
			guard !isManipulating else { return }
			if value != document {
				document = value
				updateTextViewport(textViewportWidth, includeFixedText: true)
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
		.browserFileImporter(isPresented: $importingImage, allowedContentTypes: [.image], onCompletion: importImage)
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
	/// Drawing gestures use canvas coordinates, including when vertically scrolled.
	@ViewBuilder
	private func canvasContents(width: CGFloat, viewportHeight: CGFloat) -> some View {
		let surface = ZStack(alignment: .topLeading) {
			Color.clear.contentShape(Rectangle()).onTapGesture { selectedID = nil; editingTextID = nil }
			ForEach(document.items) { item in
				itemView(item, canvasWidth: width)
			}
			if let shapeDraft {
				itemContent(shapeDraft, canvasWidth: width)
					.frame(width: shapeDraft.width, height: shapeDraft.height, alignment: .topLeading)
					.offset(x: shapeDraft.x, y: shapeDraft.y)
					.allowsHitTesting(false)
			}
			if !drawingPoints.isEmpty {
				smoothPath(drawingPoints)
					.stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
					.allowsHitTesting(false)
			}
		}
		.frame(width: width, height: canvasHeight(viewportHeight), alignment: .topLeading)
		.coordinateSpace(name: "easel-drawing-canvas")
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
			surface.highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("easel-drawing-canvas")).updating($gestureActive) { _, active, _ in active = true }
				.onChanged { value in
					if case .shape = activeTool {
						updateShapeDraft(start: value.startLocation, end: value.location, canvasWidth: width)
					} else if activeTool == .pen, drawingPoints.count < 10000 {
						drawingPoints.append(.init(x: value.location.x, y: value.location.y))
					} else if activeTool == .eraser {
						erase(at: value.location)
					}
				}
				.onEnded { value in
					if case .shape = activeTool {
						updateShapeDraft(start: value.startLocation, end: value.location, canvasWidth: width)
						if let shapeDraft { append(shapeDraft) }
						shapeDraft = nil
						activeTool = .cursor
					} else if activeTool == .pen {
						finishDrawing()
					}
				})
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
			Button("Rectangle", systemImage: "rectangle") { armShapeTool(.rectangle) }
				.accessibilityIdentifier("easel-add-rectangle")
				.tint(activeTool == .shape(.rectangle) ? .accentColor : .primary)
			Button("Ellipse", systemImage: "circle") { armShapeTool(.ellipse) }
				.accessibilityIdentifier("easel-add-ellipse")
				.tint(activeTool == .shape(.ellipse) ? .accentColor : .primary)
			Button("Line", systemImage: "line.diagonal") { armShapeTool(.line) }
				.accessibilityIdentifier("easel-add-line")
				.tint(activeTool == .shape(.line) ? .accentColor : .primary)
			Button("Arrow", systemImage: "arrow.up.right") { armShapeTool(.arrow) }
				.accessibilityIdentifier("easel-add-arrow")
				.tint(activeTool == .shape(.arrow) ? .accentColor : .primary)
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
				.help(BrowserEaselSystemFonts.displayName(for: item.font))
				.accessibilityValue(BrowserEaselSystemFonts.displayName(for: item.font))
				.accessibilityIdentifier("easel-font")
				Button("Smaller Text", systemImage: "minus") { adjustSize(item, by: -1) }
					.disabled(item.size == .small)
					.accessibilityIdentifier("easel-smaller-text")
				Button("Larger Text", systemImage: "plus") { adjustSize(item, by: 1) }
					.disabled(item.size == .huge)
					.accessibilityIdentifier("easel-larger-text")
			}
			if ![.image, .link, .quote].contains(item.kind) {
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

	private func centerPendingQuote(in viewport: CGSize) {
		guard let id = tab.pendingQuotePlacementID,
		      let item = document.items.first(where: { $0.id == id }) else { return }
		let point = canvasOffset.point
		var next = document
		guard let index = next.items.firstIndex(where: { $0.id == id }) else { return }
		next.items[index].x = min(10000 - item.width, max(0, Double(point.x + viewport.width / 2) - item.width / 2))
		next.items[index].y = min(1_000_000 - item.height, max(0, Double(point.y + viewport.height / 2) - item.height / 2))
		if next.isValid {
			document = next
			selectedID = id
			editingTextID = nil
			activeTool = .cursor
		}
		tab.consumeQuotePlacement(id)
	}

	private func canvasWidth(_ viewport: CGFloat) -> CGFloat {
		min(20000, max(1600, viewport, document.items.map { $0.x + $0.width + 400 }.max() ?? 0))
	}

	private func canvasHeight(_ viewport: CGFloat) -> CGFloat {
		min(4_000_000, max(1200, viewport, document.items.map { $0.y + $0.height + 400 }.max() ?? 0))
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
		let hasEndpointHandles = item.kind == .line || item.kind == .arrow
		return itemContent(item, canvasWidth: canvasWidth)
			.frame(width: item.width, height: item.height, alignment: .topLeading)
			.anchorPreference(key: EaselSelectedItemBounds.self, value: .bounds) { bounds in
				selectedID == item.id ? bounds : nil
			}
			.contentShape(EaselImageMask(isRounded: item.kind == .image && item.roundedCorners == true))
			.overlay {
				if selectedID == item.id, !hasEndpointHandles {
					RoundedRectangle(cornerRadius: 6).strokeBorder(.tint, lineWidth: 1)
						.allowsHitTesting(false)
				}
			}
			.overlay(alignment: item.kind == .text ? .trailing : .bottomTrailing) {
				if selectedID == item.id, !hasEndpointHandles {
					Circle().fill(.tint).frame(width: 12, height: 12)
						.padding(5)
						.contentShape(Rectangle())
						.highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).updating($gestureActive) { _, active, _ in active = true }
							.onChanged { resize(item, translation: $0.translation, canvasWidth: canvasWidth) }
							.onEnded { _ in commitGesture(); baseline = nil })
						.accessibilityLabel(item.kind == .text ? "Resize text width" : "Resize item")
						.accessibilityIdentifier("easel-resize-\(item.id)")
				}
			}
			.overlay(alignment: .top) {
				if selectedID == item.id, [.image, .rectangle, .ellipse].contains(item.kind) {
					VStack(spacing: 0) {
						Circle().fill(.tint).frame(width: 14, height: 14)
							.contentShape(Rectangle())
							.highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).updating($gestureActive) { _, active, _ in active = true }
								.onChanged { rotate(item, translation: $0.translation) }
								.onEnded { _ in commitGesture(); baseline = nil })
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
			.gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global).updating($gestureActive) { _, active, _ in active = true }
				.onChanged { value in
					guard activeTool == .cursor, editingTextID != item.id else { return }
					drag(item, translation: value.translation, canvasWidth: canvasWidth)
				}
				.onEnded { _ in commitGesture(); baseline = nil; draggedCopy = nil })
			.onTapGesture { activateItem(item, activationScreenPoint: BrowserPeek.currentActivationScreenPoint()) }
			.highPriorityGesture(TapGesture(count: 2).onEnded {
				guard activeTool == .cursor else { return }
				selectItem(item)
				if item.kind == .text {
					editingTextID = item.id
				} else if item.kind == .link, let url = item.url {
					browser.openEaselLink(url, in: tab, activationScreenPoint: BrowserPeek.currentActivationScreenPoint())
				}
			})
			// Observe the press alongside the move and double-tap recognizers. A
			// single tap must otherwise wait for mouse-up and double-tap failure.
			// Keeping this simultaneous lets text selection, handles, scrolling,
			// context menus and the existing 3-point move threshold keep working.
			// GestureState reports each press once and resets even on cancellation;
			// later movement must not reselect an Option-drag's original item.
			.simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressedItemID) { _, id, _ in
				id = item.id
			})
			.contextMenu {
				if item.kind == .image {
					Button(item.roundedCorners == true ? "Square Image Corners" : "Round Image Corners",
					       systemImage: item.roundedCorners == true ? "rectangle" : "rectangle.roundedtop") {
						setImageRoundedCorners(item.id, rounded: item.roundedCorners != true)
					}
					Divider()
				}
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
			.accessibilityAction { activateItem(item) }
	}

	/// Selection never edits or saves the document, decodes media, or waits for
	/// tap recognition. An already active browser tab needs no selection work.
	private func selectItem(_ item: BrowserEaselDocument.Item) {
		guard activeTool == .cursor else { return }
		if selectedID != item.id { selectedID = item.id }
		if editingTextID != nil, editingTextID != item.id { editingTextID = nil }
		if browser.selectedTabID != tab.id { browser.selectTab(tab.id) }
		#if os(macOS)
			if editingTextID == nil, !canvasFocused { canvasFocused = true }
		#endif
	}

	private func activateItem(_ item: BrowserEaselDocument.Item, activationScreenPoint: CGPoint? = nil) {
		guard activeTool == .cursor else { return }
		selectItem(item)
		if item.kind == .quote, let quote = item.quote {
			browser.openEaselQuote(quote, in: tab, activationScreenPoint: activationScreenPoint)
		}
	}

	@ViewBuilder
	private func itemContent(_ item: BrowserEaselDocument.Item, canvasWidth: CGFloat) -> some View {
		switch item.kind {
			case .text:
				Group {
					if editingTextID == item.id {
						textEditor(item)
					} else {
						Text(item.text)
							.font(BrowserEaselSystemFonts.swiftUIFont(for: item.font, size: CGFloat(item.size.rawValue)))
							.fixedSize(horizontal: false, vertical: true)
							.frame(maxWidth: .infinity, alignment: .topLeading)
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
					EaselImageView(data: data, roundedCorners: item.roundedCorners == true)
						.frame(height: item.height)
				}
			case .link:
				if let url = item.url {
					EaselLinkCard(url: url, width: item.width, height: item.height)
						.frame(width: item.width, height: item.height, alignment: .topLeading)
						.clipped()
						.accessibilityLabel("Easel link to \(url.host ?? url.absoluteString)")
						.accessibilityIdentifier("easel-open-link-\(item.id)")
				}
			case .quote:
				if let quote = item.quote {
					VStack(alignment: .leading, spacing: 12) {
						Image(systemName: "quote.opening")
							.font(.title2)
							.foregroundStyle(.secondary)
						Text(quote.text)
							.font(.system(size: 16, weight: .medium, design: .serif))
							.lineLimit(7)
							.frame(maxWidth: .infinity, alignment: .leading)
						Spacer(minLength: 0)
						Label(quote.url.host ?? "Source", systemImage: "arrow.up.right.square")
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					.padding(16)
					.frame(width: item.width, height: item.height)
					.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
					.accessibilityLabel("Website quote: \(quote.text)")
					.accessibilityHint("Open source in a peek with the quote highlighted")
					.accessibilityIdentifier("easel-open-quote-\(item.id)")
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
				font: item.font,
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
				.font(BrowserEaselSystemFonts.swiftUIFont(for: item.font, size: CGFloat(item.size.rawValue)))
		#endif
	}

	private func endpoint(_ item: BrowserEaselDocument.Item, index: Int, canvasWidth: CGFloat) -> some View {
		let point = item.points[index]
		return Circle().fill(.tint).frame(width: 12, height: 12)
			.position(x: point.x, y: point.y)
			.highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).updating($gestureActive) { _, active, _ in active = true }.onChanged { value in
				isManipulating = true
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
				commitGesture()
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

	private func armShapeTool(_ kind: BrowserEaselDocument.Item.Kind) {
		activeTool = .shape(kind)
		selectedID = nil
		editingTextID = nil
		shapeDraft = nil
		#if os(macOS)
			canvasFocused = true
		#endif
	}

	private func updateShapeDraft(start: CGPoint, end: CGPoint, canvasWidth: CGFloat) {
		guard case let .shape(kind) = activeTool else { return }
		shapeDraft = BrowserEaselDocument.Item.drawnShape(
			kind: kind, from: .init(x: start.x, y: start.y), to: .init(x: end.x, y: end.y),
			constrained: constrainsShape || shiftIsPressed, withinWidth: canvasWidth
		)
	}

	private func add(_ kind: BrowserEaselDocument.Item.Kind) {
		var item = BrowserEaselDocument.Item(kind: kind)
		item.y += Double(document.items.count) * 30
		if kind == .text {
			item.textWidthIsFixed = false
			EaselTextLayout.fit(&item, viewportWidth: textViewportWidth)
		}
		append(item)
		if kind == .text, selectedID == item.id { editingTextID = item.id }
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
		let previous = document.items[index]
		let changed = next.items[index]
		if changed.kind == .text,
		   previous.text != changed.text || previous.font != changed.font || previous.size != changed.size
			|| previous.width != changed.width || previous.textWidthIsFixed != changed.textWidthIsFixed {
			EaselTextLayout.fit(&next.items[index], viewportWidth: textViewportWidth)
		}
		guard (isManipulating ? next.items[index].geometryIsValid : next.isValid) else {
			editorError = "This change exceeds the easel's content limits."
			return
		}
		document = next
	}

	private func commitGesture() {
		guard isManipulating else { return }
		isManipulating = false
		baseline = nil
		draggedCopy = nil
		if document != tab.easelDocument, !tab.updateEasel(document) {
			document = tab.easelDocument
			editorError = "This change exceeds the easel's content limits. The previous content has been kept."
		}
	}

	private func reorder(_ id: UUID, front: Bool) {
		guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
		let item = document.items.remove(at: index)
		document.items.insert(item, at: front ? document.items.count : 0)
	}

	private func setImageRoundedCorners(_ id: UUID, rounded: Bool) {
		edit(id) { item in
			guard item.kind == .image else { return }
			item.roundedCorners = rounded
		}
	}

	private func deleteItem(_ id: UUID) {
		document.items.removeAll { $0.id == id }

		if selectedID == id {
			selectedID = nil
		}
		if editingTextID == id {
			editingTextID = nil
		}
	}

	private func deleteSelectedItem() {
		guard activeTool == .cursor, editingTextID == nil, let selectedID else { return }
		deleteItem(selectedID)
	}

	/// Erase complete freehand strokes at the pointer; other objects use Delete.
	private func erase(at point: CGPoint) {
		isManipulating = true
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

	/// Called for viewport changes/restoration only. Keystrokes measure one item in edit().
	private func updateTextViewport(_ width: CGFloat, includeFixedText: Bool = false) {
		guard width.isFinite, width > 0 else { return }
		textViewportWidth = width
		var next = document
		for index in next.items.indices where next.items[index].kind == .text
			&& (includeFixedText || next.items[index].textWidthIsFixed == false) {
			EaselTextLayout.fit(&next.items[index], viewportWidth: width)
		}
		if next != document { document = next }
	}

	private func adjustSize(_ item: BrowserEaselDocument.Item, by offset: Int) {
		let sizes = BrowserEaselDocument.Item.Size.allCases
		let index = sizes.firstIndex(of: item.size) ?? 2
		edit(item.id) { $0.size = sizes[min(max(index + offset, 0), sizes.count - 1)] }
	}

	private func drag(_ item: BrowserEaselDocument.Item, translation: CGSize, canvasWidth: CGFloat) {
		isManipulating = true
		if baseline?.id != item.id, draggedCopy?.source != item.id {
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
		   let duplicated = document.items.first(where: { $0.id == copy.copy })
		{
			move(duplicated, translation: translation, canvasWidth: canvasWidth)
		} else {
			move(item, translation: translation, canvasWidth: canvasWidth)
		}
	}

	private func rotate(_ item: BrowserEaselDocument.Item, translation: CGSize) {
		isManipulating = true
		if baseline?.id != item.id {
			baseline = item
		}
		guard let baseline else { return }
		edit(item.id) {
			$0.rotation = min(360, max(-360, baseline.rotation + Double(translation.width) * 0.7))
		}
	}

	private func move(_ item: BrowserEaselDocument.Item, translation: CGSize, canvasWidth: CGFloat) {
		isManipulating = true
		if baseline?.id != item.id {
			baseline = item
		}
		guard let baseline else { return }
		edit(item.id) {
			$0.x = min(max(0, baseline.x + translation.width), min(10000, max(0, canvasWidth - baseline.width)))
			$0.y = min(max(0, baseline.y + translation.height), 1_000_000)
		}
	}

	private func resize(_ item: BrowserEaselDocument.Item, translation: CGSize, canvasWidth: CGFloat) {
		isManipulating = true
		if baseline?.id != item.id {
			baseline = item
		}
		guard let baseline else { return }
		edit(item.id) {
			$0.x = baseline.x
			// A link needs room for both a readable title and its site name.
			let minimumWidth: Double = item.kind == .link ? 140 : 32
			$0.width = min(max(minimumWidth, baseline.width + translation.width), min(10000, max(minimumWidth, canvasWidth - item.x)))
			if item.kind == .image {
				$0.height = min(10000, max(1, baseline.height * $0.width / baseline.width))
			} else if item.kind == .text {
				$0.textWidthIsFixed = true
			} else {
				let minimumHeight: Double = item.kind == .link ? 72 : (item.kind == .quote ? 40 : 1)
				$0.height = min(max(minimumHeight, baseline.height + translation.height), 10000)
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
					Task { @MainActor in await addImageData(data, at: location) }
				}
				return true
			}
			let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
				? UTType.fileURL.identifier : UTType.url.identifier
			guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
			_ = provider.loadObject(ofClass: NSURL.self) { object, _ in
				guard let url = object as? URL else { return }
				if url.isFileURL {
					Task { @MainActor in
						if let data = try? await Self.readImageFile(url), !Task.isCancelled {
							await addImageData(data, at: location)
						}
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
		Task { @MainActor in
			do {
				let url = try result.get()
				let data = try await Self.readImageFile(url)
				guard !Task.isCancelled else { return }
				await addImageData(data)
			} catch {
				if (error as NSError).code != NSUserCancelledError {
					editorError = error.localizedDescription
				}
			}
		}
	}

	/// Sandbox-extension acquisition/release can synchronously wait on system
	/// services too. Keep the complete scoped operation off the UI actor, with
	/// release guaranteed on both success and failure before resuming the caller.
	private nonisolated static func readImageFile(_ url: URL) async throws -> Data {
		try await Task.detached(priority: .userInitiated) {
			let access = url.startAccessingSecurityScopedResource()
			defer {
				if access { url.stopAccessingSecurityScopedResource() }
			}
			return try Data(contentsOf: url)
		}.value
	}

	private nonisolated struct PreparedImage: Sendable {
		let data: Data
		let aspectRatio: Double
	}

	/// ImageIO runs without the main actor: JPEG/PNG compression and thumbnail
	/// decoding can otherwise stall scrolling for large imported files.
	private nonisolated static func prepareImage(_ data: Data) -> PreparedImage? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil),
		      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
		      	kCGImageSourceCreateThumbnailFromImageAlways: true,
		      	kCGImageSourceCreateThumbnailWithTransform: true,
		      	kCGImageSourceThumbnailMaxPixelSize: 1600,
		      ] as CFDictionary)
		else { return nil }

		let hasAlpha = switch thumbnail.alphaInfo {
			case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast: true
			default: false
		}
		let encoded = NSMutableData()
		let destinationType = (hasAlpha ? UTType.png : UTType.jpeg).identifier as CFString
		guard let destination = CGImageDestinationCreateWithData(encoded as CFMutableData, destinationType, 1, nil) else { return nil }
		CGImageDestinationAddImage(destination, thumbnail, [
			kCGImageDestinationLossyCompressionQuality: 0.75,
		] as CFDictionary)
		guard CGImageDestinationFinalize(destination) else { return nil }
		return PreparedImage(
			data: encoded as Data,
			aspectRatio: Double(thumbnail.height) / Double(thumbnail.width)
		)
	}

	private func addImageData(_ data: Data, at point: CGPoint? = nil) async {
		guard data.count <= 20_000_000 else {
			editorError = "Choose an image smaller than 20 MB."
			return
		}
		let prepared = await Task.detached(priority: .userInitiated) {
			Self.prepareImage(data)
		}.value
		guard !Task.isCancelled else { return }
		guard let prepared else {
			editorError = "This image could not be decoded."
			return
		}
		guard prepared.data.count <= 1_000_000 else {
			editorError = "The compressed image must be smaller than 1 MB."
			return
		}
		var item = BrowserEaselDocument.Item(kind: .image)
		item.imageData = prepared.data
		item.height = item.width * prepared.aspectRatio
		if let point {
			item.x = max(0, min(10000 - item.width, Double(point.x)))
			item.y = max(0, min(1_000_000 - item.height, Double(point.y)))
		}
		append(item)
	}
}

private struct EaselLinkCard: View {
	let url: URL
	let width: Double
	let height: Double
	@State private var title: String?
	@State private var previewImage: Image?

	var body: some View {
		let contentWidth = max(0, width - 24)
		let contentHeight = max(0, height - 24)
		// Wide, short cards share their width with the image. Taller cards give
		// the image the remaining height after reserving readable metadata.
		let horizontal = width >= 240 && height < 180
		let titleLines = contentHeight >= 70 ? 2 : 1
		let fontSize = min(20, max(13, width / 22), max(13, (contentHeight - 26) / (1.3 * Double(titleLines))))
		let metadataHeight = fontSize * 1.3 * Double(titleLines) + 26
		let imageHeight = horizontal ? contentHeight : max(0, contentHeight - metadataHeight - 10)
		let showsImage = previewImage != nil && imageHeight >= 44

		Group {
			if horizontal {
				HStack(alignment: .center, spacing: 12) {
					if showsImage {
						preview(width: min(120, contentWidth * 0.34), height: imageHeight)
					}
					metadata(fontSize: fontSize, titleLines: titleLines)
				}
			} else {
				VStack(alignment: .leading, spacing: 10) {
					if showsImage {
						preview(width: contentWidth, height: imageHeight)
					}
					metadata(fontSize: fontSize, titleLines: titleLines)
					if !showsImage { Spacer(minLength: 0) }
				}
			}
		}
		.frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
		.padding(12)
		.frame(width: width, height: height)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
		.clipShape(RoundedRectangle(cornerRadius: 12))
		.task(id: url) {
			let provider = LPMetadataProvider()
			provider.timeout = 10
			do {
				let metadata = try await provider.startFetchingMetadata(for: url)
				guard !Task.isCancelled else { return }
				title = metadata.title
				if let image = metadata.imageProvider {
					image.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
						Task { @MainActor in
							// Decode once when metadata arrives, never during resize/layout.
							guard let data else { return }
							#if os(macOS)
								previewImage = NSImage(data: data).map { Image(nsImage: $0) }
							#else
								previewImage = UIImage(data: data).map { Image(uiImage: $0) }
							#endif
						}
					}
				}
			} catch {
				title = url.host
			}
		}
	}

	private func preview(width: Double, height: Double) -> some View {
		previewImage?.resizable().scaledToFit()
			.frame(width: width, height: height)
			.accessibilityHidden(true)
	}

	private func metadata(fontSize: Double, titleLines: Int) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Label(title ?? url.host ?? "Web Page", systemImage: "link")
				.font(.system(size: fontSize, weight: .semibold))
				.lineLimit(titleLines)
				.fixedSize(horizontal: false, vertical: true)
			Text(url.host ?? url.absoluteString)
				.font(.system(size: min(14, max(11, fontSize - 3))))
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

/// A reference-type snapshot avoids invalidating the Easel view on every scroll frame.
private final class EaselCanvasViewportOffset {
	var point: CGPoint = .zero
}

/// Only the selected item contributes an anchor; scrolling resolves it in the viewport
/// without publishing scroll positions or measuring every item into view state.
private struct EaselSelectedItemBounds: PreferenceKey {
	static var defaultValue: Anchor<CGRect>? { nil }

	static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
		if let next = nextValue() { value = next }
	}
}

/// Measure the actual controls in the same layout pass that positions them.
private struct EaselSelectionControlsLayout: Layout {
	let itemBounds: CGRect

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		proposal.replacingUnspecifiedDimensions()
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		guard let controls = subviews.first else { return }
		let size = controls.sizeThatFits(.unspecified)
		let margin: CGFloat = 12
		let gap: CGFloat = 12
		let below = itemBounds.maxY + gap
		let preferredY = below + size.height <= bounds.height - margin
			? below : itemBounds.minY - gap - size.height
		// When neither side fits, keep the controls reachable inside the viewport.
		let x = min(max(margin, itemBounds.midX - size.width / 2), max(margin, bounds.width - margin - size.width))
		let y = min(max(margin, preferredY), max(margin, bounds.height - margin - size.height))
		controls.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(size))
	}
}
