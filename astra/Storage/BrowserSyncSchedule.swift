import Foundation

/// Pure monotonic-time policy: mutations never move the maximum-age deadline.
nonisolated struct BrowserSyncSchedule: Sendable {
	static let normalInterval: TimeInterval = 180
	static let lowPowerInterval: TimeInterval = 600
	static let maximumBackoff: TimeInterval = 1800
	var lowPower = false
	var ready = false
	var online = true
	var lastSuccess: TimeInterval?
	var retryAt: TimeInterval?
	var failures = 0
	var catchUp = false

	func deadline(now: TimeInterval) -> TimeInterval? {
		guard ready, online else { return nil }
		if let retryAt { return max(now, retryAt) }
		if catchUp { return now }
		return max(now, (lastSuccess ?? (now - interval)) + interval)
	}
	var interval: TimeInterval { lowPower ? Self.lowPowerInterval : Self.normalInterval }
	mutating func succeeded(now: TimeInterval) {
		lastSuccess = now
		catchUp = false
		retryAt = nil
		failures = 0
	}
	mutating func failed(now: TimeInterval, jitter: Double) {
		failures = min(failures + 1, 12)
		let delay = min(Self.maximumBackoff, 15 * pow(2, Double(failures - 1)))
		retryAt = now + min(Self.maximumBackoff, delay * (0.8 + 0.4 * min(1, max(0, jitter))))
	}
}

/// Coalesces a burst of manual requests into one awaited follow-up pass.
nonisolated struct BrowserSyncRequestGate: Sendable {
	private(set) var running = false
	private(set) var manualQueued = false
	mutating func request(manual: Bool) -> Bool {
		if running {
			manualQueued = manualQueued || manual
			return false
		}
		running = true
		return true
	}
	mutating func nextCycle(canContinue: Bool) -> Bool {
		if canContinue, manualQueued {
			manualQueued = false
			return true
		}
		running = false
		manualQueued = false
		return false
	}
}
