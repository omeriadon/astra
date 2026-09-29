import CoreGraphics
import simd
import SwiftUI

/// Pure CPU rasterizer for the circular saturation/brightness field.
/// Moved verbatim out of CircularThemeColorPicker; no behavior change.
enum SVFieldRenderer {
	static let fieldDimension = 384

	static func hsv(_ color: BrowserColor) -> (hue: Double, saturation: Double, value: Double) {
		let maximum = max(color.red, color.green, color.blue)
		let minimum = min(color.red, color.green, color.blue)
		let difference = maximum - minimum
		let saturation = maximum > 0 ? difference / maximum : 0
		guard difference > 0 else { return (0, saturation, maximum) }
		let segment: Double = if maximum == color.red {
			(color.green - color.blue) / difference
		} else if maximum == color.green {
			(color.blue - color.red) / difference + 2
		} else {
			(color.red - color.green) / difference + 4
		}
		return ((segment / 6 + 1).truncatingRemainder(dividingBy: 1), saturation, maximum)
	}

	static func renderField(hue: Double) -> CGImage {
		let dimension = fieldDimension
		let pureHue = pureHueRGB(hue)
		var pixels = [UInt8](repeating: 0, count: dimension * dimension * 4)
		for (pixel, weights) in fieldWeights.enumerated() {
			guard weights.inside else { continue }
			let index = pixel * 4
			let noise = Double(((pixel &* 73) ^ (pixel >> 3)) & 255) / 255 - 0.5
			pixels[index] = UInt8(min(max((weights.white + weights.hue * pureHue.x) * 255 + noise, 0), 255))
			pixels[index + 1] = UInt8(min(max((weights.white + weights.hue * pureHue.y) * 255 + noise, 0), 255))
			pixels[index + 2] = UInt8(min(max((weights.white + weights.hue * pureHue.z) * 255 + noise, 0), 255))
			pixels[index + 3] = 255
		}
		let provider = CGDataProvider(data: Data(pixels) as CFData)!
		return CGImage(
			width: dimension,
			height: dimension,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: dimension * 4,
			space: CGColorSpace(name: CGColorSpace.sRGB)!,
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
			provider: provider,
			decode: nil,
			shouldInterpolate: true,
			intent: .defaultIntent
		)!
	}

	static let fieldWeights: [(white: Double, hue: Double, inside: Bool)] = {
		let dimension = fieldDimension
		let radius = Double(dimension) / 2
		let rootThree = sqrt(3.0)
		var weights: [(white: Double, hue: Double, inside: Bool)] = []
		weights.reserveCapacity(dimension * dimension)
		for row in 0 ..< dimension {
			for column in 0 ..< dimension {
				let point = SIMD2<Double>(
					(Double(column) + 0.5 - radius) / radius,
					(radius - Double(row) - 0.5) / radius
				)
				guard simd_length_squared(point) <= 1 else {
					weights.append((0, 0, false))
					continue
				}
				let triangle = CircularSVPicker.circleToTriangle(point)
				weights.append((
					(1 + triangle.y) / 3 - triangle.x / rootThree,
					(1 + triangle.y) / 3 + triangle.x / rootThree,
					true
				))
			}
		}
		return weights
	}()

	static func pureHueRGB(_ hue: Double) -> SIMD3<Double> {
		let segment = hue * 6
		let x = 1 - abs(segment.truncatingRemainder(dividingBy: 2) - 1)
		switch Int(segment) % 6 {
			case 0: return SIMD3(1, x, 0)
			case 1: return SIMD3(x, 1, 0)
			case 2: return SIMD3(0, 1, x)
			case 3: return SIMD3(0, x, 1)
			case 4: return SIMD3(x, 0, 1)
			default: return SIMD3(1, 0, x)
		}
	}
}
