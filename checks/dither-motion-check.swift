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

		var timing = DitherAnimationTiming()
		timing.seed(now: 10)
		precondition(timing.advance(now: 10.5, isAdvancing: true) == 0.5)
		timing.reset()
		timing.seed(now: 100)
		precondition(timing.advance(now: 100.1, isAdvancing: true) < 0.101, "Resuming must exclude inactive time")
		var still = DitherConfiguration()
		still.intro = false
		still.disableAnimation = true
		precondition(DitherRenderSchedulingPolicy.interval(for: still, introComplete: true) == nil)
		still.disableAnimation = false
		still.waveSpeed = 0
		precondition(DitherRenderSchedulingPolicy.interval(for: still, introComplete: true) == nil)
		still.waveSpeed = 0.01
		let slow = DitherRenderSchedulingPolicy.interval(for: still, introComplete: true)!
		still.waveSpeed = 0.05
		let normal = DitherRenderSchedulingPolicy.interval(for: still, introComplete: true)!
		precondition(slow > normal && normal >= 1 / 30)
		let configuration = DitherConfiguration()
		precondition(configuration.gridSize == 2 && configuration.waveSpeed == 0.05)
		precondition(configuration.framesPerSecond == 30 && configuration.minimumIntensity == 0)
		// Migration must preserve valid choices and discard every removed/unknown style.
		for style in ["default", "float", "dither", "ripple", "datamosh", "topographic"] {
			precondition(NewTabBackgroundPreferences.migratedStyle(style) == style)
		}
		for style in ["smoke", "holographic", "solid", "image", "", "future-style"] {
			precondition(NewTabBackgroundPreferences.migratedStyle(style) == "default")
		}
		let suite = "astra.preset-check.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		var saved = configuration
		saved.waveSpeed = -0.8
		saved.waveDirection = 135
		saved.colorNum = 4
		NewTabBackgroundPreferences.saveDitherConfiguration(saved, to: defaults)
		let restored = NewTabBackgroundPreferences.loadDitherConfiguration(from: defaults)
		precondition(restored.waveSpeed == 0.8)
		precondition(restored.waveDirection == 315)
		precondition(restored.colorNum == 4)
		defaults.set(Data("legacy".utf8), forKey: "astra.newTabEffectSettings")
		defaults.set(Data("legacy".utf8), forKey: "astra.newTabTopographicImage")
		NewTabBackgroundPreferences.removeLegacyParameters(in: defaults)
		precondition(defaults.object(forKey: "astra.newTabDitherConfiguration") != nil)
		precondition(defaults.object(forKey: "astra.newTabEffectSettings") == nil)
		precondition(defaults.object(forKey: "astra.newTabTopographicImage") == nil)
		precondition(configuration.safe(.nan, 1 ... 24, fallback: 3) == 3)
		precondition(configuration.safe(-100, 1 ... 24) == 1)
		precondition(configuration.safe(100, 1 ... 24) == 24)
		let legacyJSON = """
		{"gridSize": 8, "gridSpacing": 2, "colorLevels": 6, "waveScale": 2,
		 "animationEnabled": false, "waveSpeed": -0.25, "waveDirection": 90,
		 "backgroundStyle": "future", "colorPlacement": "future", "squareStyle": "future"}
		""".data(using: .utf8)!
		let legacy = try! JSONDecoder().decode(DitherConfiguration.self, from: legacyJSON)
		precondition(legacy.pixelSize == 10 && abs(legacy.gap - 0.1) < 0.0001)
		precondition(legacy.colorNum == 6 && legacy.scale == 2 && legacy.disableAnimation)
		precondition(legacy.waveSpeed == 0.25 && legacy.waveDirection == 270)
		precondition(legacy.backgroundStyle == "custom" && legacy.colorPlacement == "squares" && legacy.squareStyle == "white")
		let secondLoad = try! JSONDecoder().decode(DitherConfiguration.self, from: JSONEncoder().encode(legacy))
		precondition(secondLoad == legacy, "Migration must be idempotent")
		let partial = try! JSONDecoder().decode(DitherConfiguration.self, from: Data("{}".utf8))
		precondition(partial == configuration)
		var invalid = configuration
		invalid.waveSpeed = .nan
		invalid.pixelSize = .infinity
		invalid.gap = 5
		invalid.cursorRadius = .nan
		let bounded = invalid.bounded()
		precondition(bounded.waveSpeed.isFinite && bounded.pixelSize.isFinite)
		precondition(bounded.gap == 0.45 && bounded.cursorRadius == 0.5)
		print("Dither motion, clock, configuration and persistence checks passed")
	}
}
