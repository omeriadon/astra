import Foundation

@main struct SyncSchedulerCheck {
	static func main() {
		var policy = BrowserSyncSchedule()
		assert(policy.deadline(now: 0) == nil, "signed out must have no timer")
		policy.ready = true
		assert(policy.deadline(now: 0) == 0, "startup is immediate")
		policy.succeeded(now: 0)
		assert(policy.deadline(now: 1) == 180)
		for now in 1...179 { assert(policy.deadline(now: Double(now)) == 180, "edits must never delay cadence") }
		policy.lowPower = true
		assert(policy.deadline(now: 180) == 600)
		policy.lowPower = false
		assert(policy.deadline(now: 180) == 180)
		policy.online = false
		assert(policy.deadline(now: 500) == nil, "offline has no wakeups")
		policy.online = true
		policy.catchUp = true
		assert(policy.deadline(now: 50) == 50, "reconnect is prompt")
		policy.failed(now: 50, jitter: 0.5)
		assert(policy.deadline(now: 50) == 65, "reconnect must respect backoff")
		for index in 0..<30 {
			let now = Double(index * 2000)
			policy.failed(now: now, jitter: 1)
			let due = policy.deadline(now: now)!
			assert(due > now && due <= now + 1800, "bounded backoff never spins")
		}
		policy.succeeded(now: 70000)
		assert(policy.failures == 0 && policy.retryAt == nil && !policy.catchUp)
		assert(policy.deadline(now: 80000) == 80000, "wake catch-up")
		policy.ready = false
		assert(policy.deadline(now: 80000) == nil)
		policy.ready = true
		var pulls = 0
		for _ in 0..<480 {
			let due = policy.deadline(now: policy.lastSuccess!)!
			assert(due - policy.lastSuccess! == 180)
			policy.succeeded(now: due)
			pulls += 1
		}
		assert(pulls == 480, "24 hours of healthy periodic pulls")
		var gate = BrowserSyncRequestGate()
		assert(gate.request(manual: false))
		for _ in 0..<100 { assert(!gate.request(manual: true), "no overlapping cycles") }
		assert(gate.nextCycle(canContinue: true), "manual waiter gets a completed follow-up")
		assert(!gate.nextCycle(canContinue: true), "requests coalesce into one follow-up")
		assert(!gate.running)
		assert(gate.request(manual: true), "manual bypasses periodic delay")
		assert(!gate.request(manual: true))
		assert(!gate.nextCycle(canContinue: false), "sign-out cancels queued manual work")
		assert(!gate.running && !gate.manualQueued)
		print("Sync scheduler: startup, normal/LPM cadence, power transition, offline/reconnect, backoff, wake, sign-out, no spin, 24-hour idle simulation passed")
	}
}
