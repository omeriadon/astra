import Foundation
import Metal

@main
struct DitherRendererGPUCheck {
	static func main() throws {
		guard let device = MTLCreateSystemDefaultDevice() else {
			throw NSError(domain: "DitherGPUCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device required"])
		}
		let width = 320
		let height = 240
		let descriptor = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
		)
		descriptor.usage = [.renderTarget, .shaderRead]
		descriptor.storageMode = .shared
		let target = device.makeTexture(descriptor: descriptor)!
		let optimized = try DitherMetalRenderer(usesTopBlur: false)
		let reference = try DitherMetalRenderer(usesFusedFieldAndCellPass: false, usesCoverageAtlas: false, usesTopBlur: false)
		let cellBlur = try DitherMetalRenderer(usesTopBlur: true)
		let mpsBlur = try DitherMetalRenderer(usesTopBlur: true, usesCellBlurFastPath: false)
		let inputs = DitherRenderInputs(
			themePositions: [SIMD2<Float>(0.2, 0.2), SIMD2<Float>(0.8, 0.8)],
			themeColors: [SIMD3<Float>(1, 0.2, 0.1), SIMD3<Float>(0.1, 0.2, 1)],
			cursorTrail: [SIMD3<Float>(160, 90, 1), SIMD3<Float>(130, 100, 0.7)],
			cursorPresence: 1
		)
		func render(_ renderer: DitherMetalRenderer, _ config: DitherConfiguration, _ input: DitherRenderInputs) throws -> [UInt8] {
			try renderer.render(to: target, width: width, height: height, cell: 4, configuration: config, inputs: input, advance: false, atTime: 2)
			var bytes = [UInt8](repeating: 0, count: width * height * 4)
			target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
			return bytes
		}
		func maximumDifference(_ left: [UInt8], _ right: [UInt8]) -> Int {
			zip(left, right).map { abs(Int($0) - Int($1)) }.max() ?? 0
		}
		var count = 0
		for mode in 0 ..< 8 {
			for shape in 0 ..< 3 {
				for theme in [false, true] {
					var config = DitherConfiguration()
					config.intro = false
					config.ditherMode = mode
					config.useThemeColors = theme
					config.palette = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)]
					config.gap = shape == 1 ? 0.1 : 0
					config.cornerRadius = shape == 0 ? 0 : 0.3
					config.joinAdjacentSquares = shape == 2
					let actual = try render(optimized, config, inputs)
					let expected = try render(reference, config, inputs)
					precondition(maximumDifference(actual, expected) <= 1, "Fused/reference mismatch: mode \(mode), shape \(shape), theme \(theme)")
					precondition(stride(from: 0, to: actual.count, by: 4).contains { actual[$0] != 0 || actual[$0 + 1] != 0 || actual[$0 + 2] != 0 }, "Comparison must exercise a visible field")
					count += 1
				}
			}
		}
		var config = DitherConfiguration()
		config.intro = false
		let withCursor = try render(optimized, config, inputs)
		var noCursor = inputs
		noCursor.cursorTrail = []
		noCursor.cursorPresence = 0
		let withoutCursor = try render(optimized, config, noCursor)
		precondition(withCursor != withoutCursor, "Cursor must change fused field output")
		config.cursorInteractionEnabled = false
		let disabledCursor = try render(optimized, config, inputs)
		precondition(disabledCursor == withoutCursor, "Disabled cursor must have no effect")
		config.cursorInteractionEnabled = true
		for transparent in [false, true] {
			config.transparent = transparent
			let fast = try render(cellBlur, config, inputs)
			let fallback = try render(mpsBlur, config, inputs)
			precondition(maximumDifference(fast, fallback) <= 2, "Cell blur must match MPS within two levels")
			precondition(Array(fast[(width * 104 * 4)...]) == Array(fallback[(width * 104 * 4)...]), "Pixels below blur strip must match")
			precondition(cellBlur.lastRenderMetrics?.gaussianEncodeCount == 0, "Eligible cell blur must use fast path")
		}
		print("Dither GPU checks passed: \(count) fused/reference cases, cursor behavior, and opaque/transparent cell blur")
	}
}
