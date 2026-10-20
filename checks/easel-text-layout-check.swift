// macOS: swiftc -parse-as-library astra/Models/Tabs/BrowserEasel.swift \
//   astra/UI/Content/BrowserEaselSystemFonts.swift astra/UI/Content/EaselTextLayout.swift \
//   checks/easel-text-layout-check.swift -o /tmp/easel-text-layout-check && /tmp/easel-text-layout-check
import AppKit
import Foundation

@main
struct EaselTextLayoutCheck {
	@MainActor
	static func main() throws {
		var item = BrowserEaselDocument.Item(kind: .text)
		item.textWidthIsFixed = false
		item.text = "A short line"
		EaselTextLayout.fit(&item, viewportWidth: 800)
		let shortWidth = item.width
		let singleLineHeight = item.height
		item.text += " "
		EaselTextLayout.fit(&item, viewportWidth: 800)
		precondition(item.width > shortWidth)
		precondition(shortWidth < 240)
		item.text += " that grows"
		EaselTextLayout.fit(&item, viewportWidth: 800)
		precondition(item.width > shortWidth && item.height == singleLineHeight)
		item.text = String(repeating: "words ", count: 50)
		EaselTextLayout.fit(&item, viewportWidth: 400)
		precondition(item.width == 352 && item.height > singleLineHeight)
		let wrappedHeight = item.height
		EaselTextLayout.fit(&item, viewportWidth: 250)
		precondition(item.width == 202 && item.height > wrappedHeight)
		item.textWidthIsFixed = true
		item.width = 100
		EaselTextLayout.fit(&item, viewportWidth: 800)
		let narrowHeight = item.height
		item.width = 200
		EaselTextLayout.fit(&item, viewportWidth: 800)
		precondition(item.width == 200 && item.height < narrowHeight)
		item.size = .huge
		EaselTextLayout.fit(&item, viewportWidth: 800)
		precondition(item.height > wrappedHeight)
		item.text = "line\n"
		EaselTextLayout.fit(&item, viewportWidth: 800)
		let newlineHeight = item.height
		item.text = "line"
		EaselTextLayout.fit(&item, viewportWidth: 800)
		precondition(newlineHeight > item.height)
		item.text = ""
		EaselTextLayout.fit(&item, viewportWidth: 800)
		precondition(item.height > 16)
		// Missing optional field is the legacy conversion: retain its saved width,
		// recompute only height, and preserve all text and font/style fields.
		item.text = "legacy saved text"
		item.textWidthIsFixed = nil
		item.width = 137
		item.height = 500
		let encoded = try JSONEncoder().encode(item)
		precondition(!String(decoding: encoded, as: UTF8.self).contains("textWidthIsFixed"))
		var restored = try JSONDecoder().decode(BrowserEaselDocument.Item.self, from: encoded)
		EaselTextLayout.fit(&restored, viewportWidth: 800)
		precondition(restored.width == 137 && restored.height < 500 && restored.text == item.text)
		restored.textWidthIsFixed = false
		let roundTrip = try JSONDecoder().decode(BrowserEaselDocument.Item.self, from: JSONEncoder().encode(restored))
		precondition(roundTrip == restored)
		// Previously valid large content remains fully visible after narrowing.
		restored.text = String(repeating: "x\n", count: 2000)
		EaselTextLayout.fit(&restored, viewportWidth: 100)
		precondition(restored.height > 10000 && BrowserEaselDocument(items: [restored]).isValid)
		print("easel text natural width, wrap, fixed width, font size, trailing newline, legacy and persistence checks passed")
	}
}
