import Foundation

@main
struct EaselDocumentCheck {
	static func main() throws {
		var item = BrowserEaselDocument.Item(kind: .text)
		item.text = "ABC abc 012 - . *"
		let original = BrowserEaselDocument(items: [item])
		precondition(original.isValid)
		let encoded = try JSONEncoder().encode(original)
		let restored = try JSONDecoder().decode(BrowserEaselDocument.self, from: encoded)
		precondition(restored == original)
		item.x = .infinity
		precondition(!BrowserEaselDocument(items: [item]).isValid)
		precondition(!BrowserEaselDocument(items: [original.items[0], original.items[0]]).isValid)
		for value in ["file:///etc/passwd", "javascript:alert(1)", "https://user:secret@example.com", "https:", "https://example.com:99999"] {
			precondition(!BrowserEaselDocument.isSafeLink(URL(string: value)!))
		}
		precondition(BrowserEaselDocument.isSafeLink(URL(string: "https://example.com/page")!))
		let quoteSource = BrowserEaselQuote(url: URL(string: "https://example.com/page")!,
		                                    text: "Selected text", prefix: "Before ", suffix: " after")
		precondition(quoteSource.isValid)
		var quoteItem = BrowserEaselDocument.Item(kind: .quote)
		precondition(!BrowserEaselDocument(items: [quoteItem]).isValid)
		quoteItem.quote = quoteSource
		let quoteDocument = BrowserEaselDocument(items: [quoteItem])
		precondition(quoteDocument.isValid)
		let encodedQuote = try JSONEncoder().encode(quoteDocument)
		let decodedQuote = try JSONDecoder().decode(BrowserEaselDocument.self, from: encodedQuote)
		precondition(decodedQuote == quoteDocument)
		quoteItem.quote?.url = URL(fileURLWithPath: "/tmp/unsafe")
		precondition(!BrowserEaselDocument(items: [quoteItem]).isValid)
		quoteItem.quote = quoteSource
		quoteItem.quote?.text = String(repeating: "x", count: 8193)
		precondition(!BrowserEaselDocument(items: [quoteItem]).isValid)
		quoteItem.quote = quoteSource
		quoteItem.quote?.prefix = String(repeating: "x", count: 257)
		precondition(!BrowserEaselDocument(items: [quoteItem]).isValid)
		precondition(BrowserEaselDocument.Item.Background.none.next == .mint)
		precondition(BrowserEaselDocument.Item.Background.purple.next == .none)
		precondition(BrowserEaselDocument.Item.Background.mint.isLight)
		precondition(!BrowserEaselDocument.Item.Background.navy.isLight)
		var line = BrowserEaselDocument.Item(kind: .arrow)
		line.points = [.init(x: 100, y: 100), .init(x: 0, y: 0)]
		line.orderEndpoints()
		precondition(line.points[0].x == 0)
		precondition(BrowserEaselDocument(items: [line]).isValid)
		line.moveEndpoint(0, by: .init(x: -10, y: -10), withinWidth: 1000)
		precondition(line.x == 14 && line.y == 14)
		precondition(line.x + line.points[1].x == 124)
		precondition(line.y + line.points[1].y == 124)
		precondition(BrowserEaselDocument(items: [line]).isValid)
		line.imageData = Data(repeating: 0, count: 2_000_001)
		precondition(!BrowserEaselDocument(items: [line]).isValid)
		var shape = BrowserEaselDocument.Item(kind: .rectangle)
		shape.constrainShape(true)
		precondition(shape.width == shape.height)
		shape.kind = .ellipse
		shape.height = 100
		shape.constrainShape(true)
		precondition(shape.width == shape.height)
		// Pointer geometry must preserve press/release direction and canvas positions.
		let dragStart = BrowserEaselDocument.Item.Point(x: 260, y: 840)
		let dragEnd = BrowserEaselDocument.Item.Point(x: 60, y: 720)
		for kind in [BrowserEaselDocument.Item.Kind.rectangle, .ellipse, .line, .arrow] {
			let drawn = BrowserEaselDocument.Item.drawnShape(kind: kind, from: dragStart, to: dragEnd,
			                                               constrained: false, withinWidth: 1000)!
			precondition(drawn.x == 60 && drawn.y == 720 && drawn.width == 200 && drawn.height == 120)
			precondition(BrowserEaselDocument(items: [drawn]).isValid)
			if [.line, .arrow].contains(kind) {
				precondition(drawn.points == [.init(x: 200, y: 120), .init(x: 0, y: 0)])
			}
			precondition(BrowserEaselDocument.Item.drawnShape(kind: kind, from: dragStart, to: dragStart,
			                                                constrained: false, withinWidth: 1000) == nil)
		}
		let square = BrowserEaselDocument.Item.drawnShape(kind: .ellipse, from: dragStart, to: dragEnd,
		                                                 constrained: true, withinWidth: 1000)!
		precondition(square.x == 60 && square.y == 640 && square.width == square.height)
		for end in [BrowserEaselDocument.Item.Point(x: 260, y: 1000), .init(x: 500, y: 840)] {
			let axisLine = BrowserEaselDocument.Item.drawnShape(kind: .line, from: dragStart, to: end,
			                                                  constrained: false, withinWidth: 1000)!
			precondition(axisLine.x + axisLine.points[1].x == end.x)
			precondition(axisLine.y + axisLine.points[1].y == end.y)
			precondition(BrowserEaselDocument(items: [axisLine]).isValid)
		}
		let clipped = BrowserEaselDocument.Item.drawnShape(kind: .arrow, from: dragStart,
		                                                  to: .init(x: -1000, y: -1000),
		                                                  constrained: false, withinWidth: 1000)!
		precondition(clipped.x == 0 && clipped.y == 0)
		precondition(BrowserEaselDocument(items: [clipped]).isValid)
		precondition(BrowserEaselDocument.Item.drawnShape(kind: .line, from: dragStart,
		                                                to: .init(x: .infinity, y: 0),
		                                                constrained: false, withinWidth: 1000) == nil)
		var image = BrowserEaselDocument.Item(kind: .image)
		image.constrainShape(true)
		precondition(image.height == 120)
		image.imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==")!
		precondition(BrowserEaselDocument(items: [image]).isValid)
		image.roundedCorners = true
		let roundedDocument = BrowserEaselDocument(items: [image])
		let roundedData = try JSONEncoder().encode(roundedDocument)
		let restoredRoundedDocument = try JSONDecoder().decode(BrowserEaselDocument.self, from: roundedData)
		precondition(restoredRoundedDocument == roundedDocument)
		var legacyJSON = try JSONSerialization.jsonObject(with: roundedData) as! [String: Any]
		var legacyItems = legacyJSON["items"] as! [[String: Any]]
		legacyItems[0].removeValue(forKey: "roundedCorners")
		legacyJSON["items"] = legacyItems
		let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
		let legacyDocument = try JSONDecoder().decode(BrowserEaselDocument.self, from: legacyData)
		precondition(legacyDocument.items[0].roundedCorners == nil && legacyDocument.isValid)
		image.imageData = Data([0, 1, 2, 3])
		precondition(!BrowserEaselDocument(items: [image]).isValid)
		// Every tool must create a valid item before SwiftUI observes the document.
		let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==")!
		for kind in BrowserEaselDocument.Item.Kind.allCases {
			var candidate = BrowserEaselDocument.Item(kind: kind)
			switch kind {
				case .image: candidate.imageData = pixel
				case .link: candidate.url = URL(string: "https://example.com/item")
				case .quote: candidate.quote = quoteSource
				case .line, .arrow:
					candidate.points = [.init(x: 0, y: 0), .init(x: 240, y: 120)]
				case .freehand:
					candidate.points = [.init(x: 0, y: 0), .init(x: 30, y: 60)]
				default: break
			}
			precondition(BrowserEaselDocument(items: [candidate]).isValid, "Invalid new \(kind)")
			var duplicate = candidate
			duplicate.id = UUID()
			precondition(BrowserEaselDocument(items: [candidate, duplicate]).isValid, "Invalid duplicate \(kind)")
			duplicate.rotation = 45
			duplicate.width += 20
			duplicate.height += 10
			precondition(BrowserEaselDocument(items: [candidate, duplicate]).isValid, "Invalid transformed \(kind)")
		}
		print("Easel persistence, quotes, limits, images, links, palette, endpoints, creation and duplication checks passed")
	}
}
