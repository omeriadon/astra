import Foundation
import ImageIO

nonisolated struct BrowserEaselQuote: Codable, Equatable, Sendable {
	var url: URL
	var text: String
	var prefix: String
	var suffix: String

	nonisolated var isValid: Bool {
		BrowserEaselDocument.isSafeLink(url)
			&& !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& text.utf8.count <= 8192
			&& prefix.utf8.count <= 256
			&& suffix.utf8.count <= 256
	}
}

nonisolated struct BrowserEaselQuoteDestination: Sendable {
	var id: UUID
	var title: String
}

nonisolated struct BrowserEaselDocument: Codable, Equatable, Sendable {
	private nonisolated static let disallowedHostScalars = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
	var items: [Item] = []

	nonisolated struct Item: Codable, Equatable, Identifiable, Sendable {
		var id: UUID = .init()
		var kind: Kind
		var x: Double = 24
		var y: Double = 24
		var width: Double = 240
		var height: Double = 120
		var rotation: Double = 0
		var text: String = ""
		var font: Font = .sfMono
		var size: Size = .medium
		var background: Background = .none
		var points: [Point] = []
		var url: URL?
		var imageData: Data?
		var quote: BrowserEaselQuote?

		nonisolated enum Kind: String, Codable, CaseIterable, Sendable {
			case text, image, link, quote, freehand, rectangle, ellipse, line, arrow
		}

		nonisolated enum Font: String, Codable, CaseIterable, Sendable {
			case sfMono = "SFMono-Regular"
			case newYork = "NewYorkSmall-Regular"
			case geistPixel = "GeistPixel-Square"
			case thestralNeue = "ThestralNeue-Bold"
			case solare = "Solare-Regular"

			var displayName: String {
				switch self {
					case .sfMono: "SF Mono"
					case .newYork: "New York"
					case .geistPixel: "Geist Pixel"
					case .thestralNeue: "Thestral Neue"
					case .solare: "Solare"
				}
			}
		}

		nonisolated enum Size: Int, Codable, CaseIterable, Sendable {
			case small = 8
			case compact = 12
			case medium = 15
			case large = 20
			case huge = 25
		}

		nonisolated enum Background: String, Codable, CaseIterable, Sendable {
			case none
			case mint = "a3ffd1"
			case orange = "e75e08"
			case blue = "1d5784"
			case navy = "00024f"
			case purple = "5100fa"

			var isLight: Bool {
				guard let value = UInt32(rawValue, radix: 16) else { return false }
				let brightness = Double((value >> 16) & 255) * 0.299
					+ Double((value >> 8) & 255) * 0.587
					+ Double(value & 255) * 0.114
				return brightness >= 128
			}

			var next: Self {
				let index = Self.allCases.firstIndex(of: self) ?? 0
				return Self.allCases[(index + 1) % Self.allCases.count]
			}
		}

		nonisolated struct Point: Codable, Equatable, Sendable {
			var x: Double
			var y: Double
		}

		/// Gesture-only geometry checks; imported bytes remain fully validated
		/// at document commit/import boundaries, never on each pointer event.
		var geometryIsValid: Bool {
			x.isFinite && (0 ... 10000).contains(x)
				&& y.isFinite && (0 ... 1_000_000).contains(y)
				&& width.isFinite && (32 ... 10000).contains(width)
				&& height.isFinite && (0.01 ... 10000).contains(height)
				&& rotation.isFinite && (-360 ... 360).contains(rotation)
				&& points.count <= 10000
				&& points.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10000 && abs($0.y) <= 10000 }
		}

		mutating func constrainShape(_ constrained: Bool) {
			if constrained, [.rectangle, .ellipse].contains(kind) {
				height = width
			}
		}

		mutating func moveEndpoint(_ index: Int, by translation: Point, withinWidth canvasWidth: Double) {
			guard points.count == 2, points.indices.contains(index) else { return }
			var worldPoints = points.map { Point(x: x + $0.x, y: y + $0.y) }
			worldPoints[index].x = min(max(0, worldPoints[index].x + translation.x), canvasWidth)
			worldPoints[index].y = min(max(0, worldPoints[index].y + translation.y), 1_000_000)
			x = worldPoints.map(\.x).min() ?? x
			y = worldPoints.map(\.y).min() ?? y
			points = worldPoints.map { Point(x: $0.x - x, y: $0.y - y) }
			width = max(32, points.map(\.x).max() ?? 32)
			height = max(1, points.map(\.y).max() ?? 1)
		}

		mutating func orderEndpoints() {
			guard points.count == 2 else { return }
			let first = points[0]
			let second = points[1]
			if (x + first.x) * (x + first.x) + (y + first.y) * (y + first.y)
				> (x + second.x) * (x + second.x) + (y + second.y) * (y + second.y)
			{
				points.swapAt(0, 1)
			}
		}
	}

	static let empty = Self()

	nonisolated var isValid: Bool {
		guard items.count <= 500, Set(items.map(\.id)).count == items.count else { return false }
		var imageBytes = 0
		for item in items {
			guard item.x.isFinite, (0 ... 10000).contains(item.x),
			      item.y.isFinite, (0 ... 1_000_000).contains(item.y),
			      item.width.isFinite, (32 ... 10000).contains(item.width),
			      item.height.isFinite, (0.01 ... 10000).contains(item.height),
			      item.rotation.isFinite, (-360 ... 360).contains(item.rotation),
			      item.text.utf8.count <= 80000, item.points.count <= 10000,
			      item.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10000 && abs($0.y) <= 10000 })
			else { return false }
			if let url = item.url, !Self.isSafeLink(url) {
				return false
			}
			if item.kind == .link, item.url == nil {
				return false
			}
			if item.kind == .quote, item.quote?.isValid != true {
				return false
			}
			if item.kind != .quote, item.quote != nil {
				return false
			}
			if [.line, .arrow].contains(item.kind), item.points.count != 2 {
				return false
			}
			if let data = item.imageData {
				guard item.kind == .image, Self.isValidImage(data) else { return false }
			}
			if item.kind == .image, item.imageData == nil {
				return false
			}
			imageBytes += item.imageData?.count ?? 0
			if imageBytes > 2_000_000 {
				return false
			}
		}
		return true
	}

	private nonisolated static func isValidImage(_ data: Data) -> Bool {
		guard !data.isEmpty, data.count <= 1_000_000,
		      let source = CGImageSourceCreateWithData(data as CFData, nil),
		      CGImageSourceGetCount(source) == 1,
		      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
		      let width = properties[kCGImagePropertyPixelWidth] as? Int,
		      let height = properties[kCGImagePropertyPixelHeight] as? Int
		else { return false }
		return width > 0 && height > 0 && width <= 1600 && height <= 1600
	}

	nonisolated static func isSafeLink(_ url: URL) -> Bool {
		guard url.absoluteString.utf8.count <= 16384,
		      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
		      let host = components.host, !host.isEmpty,
		      components.user == nil, components.password == nil,
		      components.port.map({ (1 ... 65535).contains($0) }) ?? true
		else { return false }
		return !host.unicodeScalars.contains { disallowedHostScalars.contains($0) }
	}
}

extension BrowserEaselQuote {
	/// Runs only in the source peek. CSS Custom Highlights survive ordinary
	/// selection changes and clicks because they do not use window selection.
	static let highlightScript = """
	((quote) => {
	  if (!document.body || !globalThis.CSS?.highlights || typeof Highlight === 'undefined') return;
	  const key = 'astra-easel-quote';
	  window.__astraQuoteObserver?.disconnect();
	  const normalize = s => s.replace(/\\s+/g, ' ').trim();
	  const target = normalize(quote.text);
	  if (!target) return;
	  const prefix = normalize(quote.prefix), suffix = normalize(quote.suffix);
	  function locate() {
	    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
	    const parts = [];
	    let raw = '', node, count = 0;
	    while ((node = walker.nextNode()) && count++ < 20000 && raw.length < 500000) {
	      if (!node.nodeValue || node.parentElement?.closest('script,style,noscript,template')) continue;
	      parts.push({node, start: raw.length});
	      raw += node.nodeValue;
	    }
	    if (!raw) return null;
	    let normalized = '', offsets = [];
	    for (let i = 0; i < raw.length; i++) {
	      const c = raw[i];
	      if (/\\s/.test(c)) {
	        if (normalized && normalized[normalized.length - 1] !== ' ') {
	          normalized += ' '; offsets.push(i);
	        }
	      } else {
	        normalized += c; offsets.push(i);
	      }
	    }
	    let best = -1, bestScore = -1, at = 0;
	    for (let n = 0; n < 100; n++) {
	      const found = normalized.indexOf(target, at);
	      if (found < 0) break;
	      const before = normalized.slice(Math.max(0, found - prefix.length), found).trim();
	      const after = normalized.slice(found + target.length, found + target.length + suffix.length).trim();
	      const score = (prefix && before.endsWith(prefix) ? 2 : 0)
	        + (suffix && after.startsWith(suffix) ? 2 : 0);
	      if (score > bestScore) { best = found; bestScore = score; }
	      at = found + 1;
	      if (score === 4) break;
	    }
	    if (best < 0) return null;
	    const start = offsets[best], end = offsets[best + target.length - 1] + 1;
	    const first = parts.find((p, i) => start >= p.start && (i + 1 === parts.length || start < parts[i + 1].start));
	    const last = parts.find((p, i) => end > p.start && (i + 1 === parts.length || end <= parts[i + 1].start));
	    if (!first || !last) return null;
	    const range = document.createRange();
	    range.setStart(first.node, start - first.start);
	    range.setEnd(last.node, end - last.start);
	    return range;
	  }
	  let active;
	  function highlight() {
	    if (active?.startContainer?.isConnected && active?.endContainer?.isConnected) return;
	    active = locate();
	    if (!active) return;
	    CSS.highlights.set(key, new Highlight(active));
	    active.startContainer.parentElement?.scrollIntoView({block:'center', behavior:'instant'});
	  }
	  if (!document.getElementById('astra-easel-quote-style')) {
	    const style = document.createElement('style');
	    style.id = 'astra-easel-quote-style';
	    style.textContent = '::highlight(astra-easel-quote){background-color:rgba(255,211,65,.85);color:#181818;text-decoration:underline;text-decoration-color:#916200}';
	    document.head?.appendChild(style);
	  }
	  highlight();
	  let queued = false;
	  window.__astraQuoteObserver = new MutationObserver(() => {
	    if (queued || active?.startContainer?.isConnected) return;
	    queued = true;
	    requestAnimationFrame(() => { queued = false; highlight(); });
	  });
	  window.__astraQuoteObserver.observe(document.body, {childList:true, subtree:true});
	})(__ASTRA_QUOTE__);
	"""
}
