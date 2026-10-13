import CoreText
import Foundation

@main
struct EaselFontCheck {
	static func main() {
		let directory = URL(fileURLWithPath: "astra/Resources/EaselFonts", isDirectory: true)
		let names = ["SF-Mono-Regular.otf", "NewYorkSmall-Regular.otf", "GeistPixel-Square.ttf", "ThestralNeue-Bold.otf", "Solare_Regular.ttf"]
		let sample = (32 ... 126).compactMap(UnicodeScalar.init).map(String.init).joined()
		for name in names {
			let url = directory.appendingPathComponent(name)
			let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor]
			let font = CTFontCreateWithFontDescriptor(descriptors[0], 15, nil)
			let characters = Array(sample.utf16)
			var glyphs = Array(repeating: CGGlyph(0), count: characters.count)
			CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
			let missing = zip(characters, glyphs).filter { $0.1 == 0 }.compactMap { UnicodeScalar($0.0).map(String.init) }.joined()
			let attributed = NSAttributedString(string: sample, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
			let line = CTLineCreateWithAttributedString(attributed)
			for run in CTLineGetGlyphRuns(line) as! [CTRun] {
				var renderedGlyphs = Array(repeating: CGGlyph(0), count: CTRunGetGlyphCount(run))
				CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &renderedGlyphs)
				precondition(renderedGlyphs.allSatisfy { $0 != 0 }, "Missing rendered glyph in \(name)")
			}
			print("\(name): printable ASCII renders; native missing glyphs: \(missing.isEmpty ? "none" : missing)")
		}
	}
}
