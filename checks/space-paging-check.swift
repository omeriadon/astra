let maximum = 1200.0
for raw in [-2000.0, -100.0, 0.0, 300.0, 1200.0, 1300.0, 4000.0] {
	let displayed = BrowserSpacePagingPhysics.resistedOffset(raw, maximum: maximum)
	let adopted = BrowserSpacePagingPhysics.adoptedOffset(displayed, maximum: maximum)
	precondition(abs(adopted - raw) < 0.000001)
}

precondition(abs(BrowserSpacePagingPhysics.resistedOffset(-100, maximum: maximum) + 14.1666666667) < 0.000001)
let destinations: [(Double, Double, Bool, Int)] = [
	(390, 0, false, 1),
	(390, 20, false, 2),
	(390, -20, false, 1),
	(630, 20, false, 3),
	(630, -20, false, 2),
	(600, -20, false, 2),
	(630, -20, true, 1),
	(630, 20, true, 3),
	(-20, -20, false, 0),
	(1300, 20, false, 4),
]
for (offset, velocity, interrupted, expected) in destinations {
	precondition(
		BrowserSpacePagingPhysics.destination(
			offset: offset,
			width: 300,
			count: 5,
			velocity: velocity,
			interrupted: interrupted
		) == expected
	)
}

let samples: [(time: TimeInterval, offset: Double)] = [(1, 0), (1.05, 20)]
precondition(abs(BrowserSpacePagingPhysics.velocity(samples: samples, at: 1.05) - 400) < 0.000001)
precondition(BrowserSpacePagingPhysics.velocity(samples: samples, at: 1.2) == 0)
precondition(BrowserSpacePagingPhysics.velocity(samples: [(1, 0)], at: 1) == 0)
let spring = Spring(response: 0.25, dampingRatio: 1)
let frequency = 2 * Double.pi / 0.25
for time in [0.0, 0.016, 0.1, 0.25, 0.4] {
	let displacement = 390.0 - 600.0
	let expected = 600 + (displacement + (400 + frequency * displacement) * time) * exp(-frequency * time)
	let actual: Double = spring.value(fromValue: 390.0, toValue: 600.0, initialVelocity: 400.0, time: time)
	precondition(abs(actual - expected) < 0.000001)
}

// A high-speed release near the target must not cross the target and then
// visibly reverse direction. Critical damping on its own does not ensure that.
for (start, target, velocity) in [(290.0, 300.0, 10000.0), (310.0, 300.0, -10000.0)] {
	let limited = BrowserSpacePagingPhysics.monotonicVelocity(
		from: start, to: target, velocity: velocity, response: 0.25
	)
	precondition(limited.sign == (target - start).sign)
	precondition(abs(limited) <= (2 * Double.pi / 0.25) * abs(target - start) + 0.000001)
	var previous = start
	for step in 0 ... 120 {
		let time = Double(step) / 120.0
		let value: Double = spring.value(fromValue: start, toValue: target, initialVelocity: limited, time: time)
		precondition((target - start) * (value - previous) >= -0.000001, "Spring reversed direction")
		precondition((target - start) * (value - target) <= 0.000001, "Spring overshot destination")
		previous = value
	}
}

precondition(BrowserSpacePagingPhysics.monotonicVelocity(from: 300, to: 300, velocity: 1000, response: 0.25) == 0)
precondition(BrowserSpacePagingPhysics.monotonicVelocity(from: 290, to: 300, velocity: -1000, response: 0.25) == 0)
precondition(BrowserSpacePagingPhysics.monotonicVelocity(from: 290, to: 300, velocity: .infinity, response: 0.25) == 0)

let settled: Double = spring.value(fromValue: 390.0, toValue: 600.0, initialVelocity: 400.0, time: spring.settlingDuration)
precondition(abs(settled - 600) < 1)

let mountedWindows: [(Double, Int, ClosedRange<Int>?)] = [
	(0, 0, nil),
	(0, 1, 0 ... 0),
	(0, 8, 0 ... 1),
	(0.4, 8, 0 ... 2),
	(3, 8, 2 ... 4),
	(3.25, 8, 2 ... 5),
	(7, 8, 6 ... 7),
	(100, 8, 6 ... 7),
	(-100, 8, 0 ... 1),
]
for (position, count, expected) in mountedWindows {
	let actual = BrowserSpacePagingPhysics.mountedPageIndices(position: position, count: count)
	precondition(actual == expected, "Wrong mount window for \(position)/\(count)")
	precondition(actual == nil || actual!.count <= 4, "More than four attached space pages")
}

precondition(BrowserSpacePagingPhysics.mountedPageIndices(position: .nan, count: 8) == nil)

print("Paging calculations passed: resistance/adoption, release direction, multi-page travel, interruption, edge bounds, stale velocity, monotone handoff and spring convergence.")
