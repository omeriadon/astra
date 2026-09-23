import Foundation
import simd

// Run: swiftc browser/UI/Settings/CircularSVPicker.swift Checks/CircularSVPickerCheck.swift -o /tmp/circular-sv-check && /tmp/circular-sv-check
@main
struct CircularSVPickerCheck {
	static func main() {
		for saturation in stride(from: 0.0, through: 1.0, by: 0.1) {
			for value in stride(from: 0.0, through: 1.0, by: 0.1) {
				let position = CircularSVPicker.circlePosition(saturation: saturation, value: value)
				precondition(simd_length(position) <= 1.000001)
				let restored = CircularSVPicker.saturationValue(for: position)
				precondition(abs(restored.value - value) < 0.000001)
				if value > 0 {
					precondition(abs(restored.saturation - saturation) < 0.000001)
				}
			}
		}
		print("PASS: circular saturation/value mapping is reversible")
	}
}
