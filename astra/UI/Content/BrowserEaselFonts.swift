import CoreText
import Foundation

@MainActor
enum BrowserEaselFonts {
	private static var registered = false

	static func register() {
		guard !registered else { return }
		registered = true
		let names = ["GeistPixel-Square.ttf", "ThestralNeue-Bold.otf", "Solare_Regular.ttf"]
		for name in names {
			let file = name as NSString
			let url = BrowserResources.bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension)
				?? BrowserResources.bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: "EaselFonts")
			if let url {
				CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
			}
		}
	}
}
