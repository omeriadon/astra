import Foundation
import Observation

/// Pass the same input to a background and its containing view to track over foreground controls.
/// Writing location does not invalidate the containing view unless that view also reads location.
@MainActor @Observable final class DitherPointerInput {
	var location: CGPoint?
}

/// Closed-form critically damped motion. Input events retarget the spring without resetting velocity.
/// Evaluating past spring segments supplies a continuous trailing wake even between mouse events.
nonisolated struct DitherMotion {
	struct Segment {
		var time: Double
		var position: SIMD2<Double>
		var velocity: SIMD2<Double>
		var target: SIMD2<Double>
		var omega: Double

		func sample(at time: Double) -> (SIMD2<Double>, SIMD2<Double>) {
			let dt = max(0, time - self.time)
			// Preserve the exact initial sample when a pointer event retargets the spring.
			// Reconstructing it as target + (position - target) can lose precision.
			guard dt > 0 else { return (position, velocity) }
			let displacement = position - target
			let coefficient = velocity + displacement * omega
			let decay = exp(-omega * dt)
			return (target + (displacement + coefficient * dt) * decay,
			        (velocity - coefficient * (omega * dt)) * decay)
		}
	}

	private var segments: [Segment] = []
	private var enteredAt: Double?
	private var exitedAt: Double?
	private var exitPresence = 0.0

	mutating func move(to point: CGPoint?, at time: Double, response: Double, fade: Double) {
		guard let point else {
			guard enteredAt != nil, exitedAt == nil else { return }
			exitPresence = presence(at: time, fade: fade)
			exitedAt = time
			return
		}
		let target = SIMD2(Double(point.x), Double(point.y))
		guard target.x.isFinite, target.y.isFinite else { return }
		if enteredAt == nil || exitedAt != nil {
			// A fresh entry fades in at its actual location; no sweep across the entire window.
			enteredAt = time
			exitedAt = nil
			segments.removeAll(keepingCapacity: true)
		}
		let current = segments.last?.sample(at: time) ?? (target, .zero)
		segments.append(Segment(time: time, position: current.0, velocity: current.1,
		                        target: target, omega: 5 / max(0.05, response)))
		// Bound event memory and retain enough history for a one-second trail at high mouse rates.
		segments.removeAll { $0.time < time - 1.5 }
		if segments.count > 512 {
			segments.removeFirst(segments.count - 512)
		}
	}

	func presence(at time: Double, fade: Double) -> Double {
		guard let enteredAt, time >= enteredAt else { return 0 }
		if let exitedAt, time >= exitedAt {
			return exitPresence * exp(-(time - exitedAt) / max(0.1, fade))
		}
		return 1 - exp(-(time - enteredAt) / 0.12)
	}

	/// Eight samples, each packed as x/y/weight, consumed directly by the Metal shader.
	func trail(at time: Double, duration: Double, fade: Double) -> [Float] {
		let currentPresence = presence(at: time, fade: fade)
		guard currentPresence > 0.001 else { return [] }
		return (0 ..< 8).flatMap { index -> [Float] in
			let fraction = Double(index) / 7
			let sampleTime = time - fraction * duration
			guard let segment = segments.last(where: { $0.time <= sampleTime }) else { return [0, 0, 0] }
			let point = segment.sample(at: sampleTime).0
			let weight = min(currentPresence, presence(at: sampleTime, fade: fade)) * (1 - fraction * 0.85)
			return [Float(point.x), Float(point.y), Float(weight)]
		}
	}
}

nonisolated struct DitherClock {
	private var accumulated = 0.0
	private var startedAt: Double?

	mutating func setRunning(_ running: Bool, at time: Double) {
		if running, startedAt == nil {
			startedAt = time
		}
		if !running, let start = startedAt {
			accumulated += max(0, time - start)
			startedAt = nil
		}
	}

	func value(at time: Double) -> Double {
		accumulated + (startedAt.map { max(0, time - $0) } ?? 0)
	}
}
