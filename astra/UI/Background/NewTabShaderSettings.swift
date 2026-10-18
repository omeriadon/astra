import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Each effect keeps its own values when switching backgrounds.
nonisolated struct NewTabEffectSettings: Codable, Equatable, Sendable {
	var values: [String: [String: Double]] = [:]
	func value(_ effect: String, _ key: String) -> Double {
		guard let parameter = Self.parameters(effect).first(where: { $0.id == key }) else { return 0 }
		let value = values[effect]?[key] ?? parameter.initial
		return value.isFinite ? min(max(value, parameter.range.lowerBound), parameter.range.upperBound) : parameter.initial
	}
	static func decode(_ data: Data) -> Self { (try? JSONDecoder().decode(Self.self, from: data)) ?? Self() }
	var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }

	struct Parameter: Identifiable, Sendable {
		let id: String
		let title: String
		let range: ClosedRange<Double>
		let initial: Double
		init(_ id: String, _ title: String, _ range: ClosedRange<Double>, _ initial: Double) {
			self.id = id
			self.title = title
			self.range = range
			self.initial = initial
		}
	}
	static func parameters(_ effect: String) -> [Parameter] {
		switch effect {
		case "float":
			return [
				.init("speed", "Speed", 0...4, 1.5),
				.init("blur", "Blur radius", 0...100, 30),
			]
		case "smoke":
			return [
				.init("amount", "Smoke amount", 0...1, 0.8),
				.init("scale", "Smoke scale", 1...12, 5),
				.init("speed", "Wind speed", 0...4, 1),
				.init("turbulence", "Turbulence", 0...4, 1.5),
			]
		case "holographic":
			return [
				.init("intensity", "Intensity", 0...1, 0.92),
				.init("scale", "Scale", 1...30, 5.2),
				.init("speed", "Speed", 0...3, 1),
				.init("angle", "Angle", 0...Double.pi * 2, 0.785),
			]
		case "ripple":
			return [
				.init("amplitude", "Amplitude", 0...40, 17),
				.init("frequency", "Frequency", 1...60, 34),
				.init("speed", "Speed", 0...10, 4.8),
				.init("damping", "Damping", 0.1...5, 1.6),
				.init("rings", "Rings", 1...5, 3),
				.init("opacity", "Opacity", 0...1, 0.56),
			]
		case "datamosh":
			return [
				.init("corruption", "Block corruption", 0...1, 0.48),
				.init("smear", "Smear amount", 0...60, 42),
				.init("bleed", "Colour bleed", 0...1, 0.65),
				.init("rate", "Glitch rate", 0.5...20, 12),
			]
		case "topographic":
			return [
				.init("lineCount", "Line count", 5...40, 20),
				.init("lineWidth", "Line width", 0.01...0.15, 0.05),
				.init("colorize", "Colour", 0...1, 0.7),
				.init("animate", "Animation", 0...1, 0.3),
			]
		default: return []
		}
	}
}

struct NewTabEffectControls: View {
	let effect: String
	@Binding var settings: NewTabEffectSettings
	@Binding var imageID: String
	@State private var importing = false
	@State private var importError: String?
	@State private var isImporting = false

	var body: some View {
		Form {
			if effect == "topographic" {
				Section("Source image") {
					Button(imageID.isEmpty ? "Upload Image…" : "Replace Image…") { importing = true }
						.disabled(isImporting)
					if isImporting { ProgressView("Importing image…") }
					if !imageID.isEmpty { Button("Use Theme Artwork") { imageID = "" } }
					if let importError { Text(importError).foregroundStyle(.red) }
				}
			}
			Section("Parameters") {
				ForEach(NewTabEffectSettings.parameters(effect)) { parameter in
					VStack(alignment: .leading, spacing: 4) {
						HStack {
							Text(parameter.title)
							Spacer()
							Text(settings.value(effect, parameter.id), format: .number.precision(.fractionLength(2)))
								.monospacedDigit().foregroundStyle(.secondary)
						}
						Slider(value: Binding(get: { settings.value(effect, parameter.id) }, set: {
							settings.values[effect, default: [:]][parameter.id] = $0
						}), in: parameter.range, step: parameter.id == "rings" ? 1 : 0.001)
						.accessibilityLabel(parameter.title)
					}
				}
			}
			Button("Reset Parameters") { settings.values[effect] = nil }
		}
		.formStyle(.grouped)
		.fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
			switch result {
			case .success(let url):
				isImporting = true
				importError = nil
				Task {
					do { imageID = try await Task.detached { try NewTabImageStore.importImage(url) }.value }
					catch { importError = "The image could not be imported. Choose a supported image file." }
					isImporting = false
				}
			case .failure: importError = "The image could not be opened."
			}
		}
	}
}

/// Copy a bounded, decoded image into app-owned storage; never retain a security-scoped URL.
nonisolated enum NewTabImageStore {
	private static func directory() throws -> URL {
		try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
		                           appropriateFor: nil, create: true)
			.appendingPathComponent("Astra/NewTabImages", isDirectory: true)
	}
	static func importImage(_ url: URL) throws -> String {
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }
		guard let image = thumbnail(url) else { throw CocoaError(.fileReadCorruptFile) }
		let folder = try directory()
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let id = UUID().uuidString
		let destination = folder.appendingPathComponent(id).appendingPathExtension("png")
		guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)
		else { throw CocoaError(.fileWriteUnknown) }
		CGImageDestinationAddImage(writer, image, nil)
		guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
		return id
	}
	static func load(_ id: String) -> CGImage? {
		guard UUID(uuidString: id) != nil, let folder = try? directory() else { return nil }
		return thumbnail(folder.appendingPathComponent(id).appendingPathExtension("png"))
	}
	private static func thumbnail(_ url: URL) -> CGImage? {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
		return CGImageSourceCreateThumbnailAtIndex(source, 0, [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceThumbnailMaxPixelSize: 2048,
			kCGImageSourceShouldCacheImmediately: true,
		] as CFDictionary)
	}
}
