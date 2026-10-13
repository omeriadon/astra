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
		var image = BrowserEaselDocument.Item(kind: .image)
		image.constrainShape(true)
		precondition(image.height == 120)
		image.imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==")!
		precondition(BrowserEaselDocument(items: [image]).isValid)
		image.imageData = Data([0, 1, 2, 3])
		precondition(!BrowserEaselDocument(items: [image]).isValid)
		// Every tool must create a valid item before SwiftUI observes the document.
		let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==")!
		for kind in BrowserEaselDocument.Item.Kind.allCases {
			var candidate = BrowserEaselDocument.Item(kind: kind)
			switch kind {
				case .image: candidate.imageData = pixel
				case .link: candidate.url = URL(string: "https://example.com/item")
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
		print("Easel persistence, limits, images, links, palette, endpoints, creation and duplication checks passed")
	}
}
