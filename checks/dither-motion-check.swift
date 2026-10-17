import Foundation

@main struct DitherMotionCheck {
	static func main() {
		// A retarget must preserve both position and momentum; no cursor teleport at an event.
		let first = DitherMotion.Segment(time: 0, position: .zero, velocity: .zero,
		                                 target: SIMD2(100, 50), omega: 18)
		let moving = first.sample(at: 0.08)
		precondition(moving.0.x > 0 && moving.0.x < 100)
		precondition(moving.1.x > 0)
		let second = DitherMotion.Segment(time: 0.08, position: moving.0, velocity: moving.1,
		                                  target: SIMD2(0, 100), omega: 18)
		precondition(second.sample(at: 0.08).0 == moving.0)
		precondition(second.sample(at: 0.08).1 == moving.1)
		let settled = second.sample(at: 10)
		precondition(abs(settled.0.x) < 0.001 && abs(settled.0.y - 100) < 0.001)
		precondition(abs(settled.1.x) < 0.001 && abs(settled.1.y) < 0.001)

		// Closed-form sampling must be independent of 30/60/120 Hz frame schedules.
		for fps in [30, 60, 120] {
			var sample = (SIMD2<Double>.zero, SIMD2<Double>.zero)
			for frame in 0 ... fps {
				sample = first.sample(at: Double(frame) / Double(fps))
			}
			precondition(sample.0 == first.sample(at: 1).0)
		}

		var motion = DitherMotion()
		motion.move(to: CGPoint(x: 10, y: 20), at: 1, response: 0.28, fade: 0.5)
		precondition(motion.trail(at: 1, duration: 0.45, fade: 0.5).isEmpty)
		motion.move(to: CGPoint(x: 110, y: 20), at: 1.2, response: 0.28, fade: 0.5)
		let trail = motion.trail(at: 1.3, duration: 0.2, fade: 0.5)
		precondition(trail.count == 24 && trail.allSatisfy(\.isFinite))
		precondition(trail[0] > trail[21], "Head must lead the delayed wake")
		let beforeExit = motion.presence(at: 1.4, fade: 0.5)
		motion.move(to: nil, at: 1.4, response: 0.28, fade: 0.5)
		precondition(abs(motion.presence(at: 1.4, fade: 0.5) - beforeExit) < 0.0001)
		precondition(motion.presence(at: 1.9, fade: 0.5) < beforeExit)
		precondition(motion.trail(at: 10, duration: 0.45, fade: 0.5).isEmpty)
		motion.move(to: CGPoint(x: 900, y: 500), at: 11, response: 0.28, fade: 0.5)
		let reentry = motion.trail(at: 11.2, duration: 0, fade: 0.5)
		precondition(reentry[0] == 900 && reentry[1] == 500, "Reentry must not sweep from the old location")

		// Large input rates must remain finite and leave a valid eight-sample trail.
		for i in 0 ..< 10000 {
			motion.move(to: CGPoint(x: Double(i % 500), y: Double(i % 300)), at: 12 + Double(i) / 1000,
			            response: 0.05, fade: 0.1)
		}
		precondition(motion.trail(at: 22, duration: 1, fade: 0.1).allSatisfy(\.isFinite))

		var clock = DitherClock()
		precondition(clock.value(at: 1) == 0)
		clock.setRunning(true, at: 1)
		clock.setRunning(false, at: 3)
		precondition(clock.value(at: 100) == 2)
		clock.setRunning(true, at: 100)
		precondition(clock.value(at: 101) == 3, "Background time must not advance the animation")

		var configuration = DitherConfiguration(gridSize: 5, gridSpacing: 2, cornerRadius: 1)
		configuration.cursorInteractionEnabled = false
		precondition(DitherConfiguration.decode(configuration.encoded) == configuration)
		precondition(DitherConfiguration.decode(Data("invalid".utf8)) == DitherConfiguration())
		precondition(configuration.safe(.nan, 1 ... 24, fallback: 3) == 3)
		precondition(configuration.safe(-100, 1 ... 24) == 1)
		precondition(configuration.safe(100, 1 ... 24) == 24)
		print("Dither motion, clock, configuration and persistence checks passed")
	}
}
