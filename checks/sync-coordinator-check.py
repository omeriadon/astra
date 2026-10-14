"""Compile actual coordinator task orchestration against deterministic network holds.

The extracted production methods retain request gate, task lifetime, cancellation,
and waiter behavior. AppKit/credentials/UI adapters are replaced by boundary mocks.
Run on Xcode 27 / Swift 6: python3 checks/sync-coordinator-check.py
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path("astra/Storage/BrowserSync.swift").read_text()

def method(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

swift = r'''
import Foundation
nonisolated enum BrowserLog {
    static func syncEvent(_ event: String, metadata: [String: String] = [:]) {}
}
@MainActor final class BrowserSync {
    var canSync = true
    var isSyncing = false
    var scheduledSync: Task<Void, Never>?
    var activeSync: Task<Void, Never>?
    var requestGate = BrowserSyncRequestGate()
    var reasons: [String] = []
    var inFlight = 0
    var maximumInFlight = 0
    var reschedules = 0
    private var hold: CheckedContinuation<Void, Never>?
    var manualQueued: Bool { requestGate.manualQueued }
    func reschedule(reason: String) { reschedules += 1 }
    func performSync(reason: String) async {
        reasons.append(reason)
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        await withCheckedContinuation { hold = $0 }
        inFlight -= 1
    }
    func release() { let continuation = hold; hold = nil; continuation?.resume() }
    func cancelSession() { canSync = false; activeSync?.cancel() }
    func automatic() async { await startSync(reason: "startup") }
'''
swift += method("func syncNow() async") + "\n" + method("private func startSync(reason: String) async") + "\n}\n"
swift += r'''
@main struct Check {
    @MainActor static func until(_ predicate: () -> Bool) async {
        for _ in 0..<10000 {
            if predicate() { return }
            await Task.yield()
        }
        preconditionFailure("Coordinator failed to progress without a timer")
    }
    @MainActor static func main() async {
        let sync = BrowserSync()
        let startup = Task { await sync.automatic() }
        await until { sync.reasons.count == 1 }
        precondition(sync.isSyncing)
        // A burst of manual clicks waits for the actual current + follow-up work.
        var manualFinished = 0
        var manualEntered = 0
        let manuals = (0..<8).map { _ in Task { manualEntered += 1; await sync.syncNow(); manualFinished += 1 } }
        await until { sync.manualQueued && manualEntered == 8 }
        precondition(manualFinished == 0)
        sync.release()
        await until { sync.reasons.count == 2 }
        precondition(sync.reasons == ["startup", "manual"])
        precondition(manualFinished == 0)
        sync.release()
        await startup.value
        for manual in manuals { await manual.value }
        precondition(manualFinished == 8 && sync.maximumInFlight == 1)
        precondition(!sync.isSyncing && sync.activeSync == nil && !sync.requestGate.running)
        // Cancellation/sign-out drains the task and gate without a queued follow-up.
        let interrupted = Task { await sync.automatic() }
        await until { sync.reasons.count == 3 }
        let pending = Task { await sync.syncNow() }
        await until { sync.manualQueued }
        sync.cancelSession()
        sync.release()
        await interrupted.value
        await pending.value
        precondition(sync.reasons.count == 3 && !sync.isSyncing && !sync.requestGate.running)
        await sync.syncNow()
        precondition(sync.reasons.count == 3)
        // A new login is allowed to start fresh after cancellation completes.
        sync.canSync = true
        let login = Task { await sync.automatic() }
        await until { sync.reasons.count == 4 }
        sync.release()
        await login.value
        precondition(sync.maximumInFlight == 1 && sync.activeSync == nil)
        // Concurrent automatic triggers join one operation without another pass.
        let firstAutomatic = Task { await sync.automatic() }
        await until { sync.reasons.count == 5 }
        var secondEntered = false
        let secondAutomatic = Task { secondEntered = true; await sync.automatic() }
        await until { secondEntered }
        precondition(!sync.manualQueued)
        sync.release()
        await firstAutomatic.value
        await secondAutomatic.value
        precondition(sync.reasons.count == 5 && sync.maximumInFlight == 1)
        print("Actual coordinator: startup, manual waiters/coalescing, no overlap, cancellation, sign-out/re-login passed")
    }
}
'''
compiler = shutil.which("swiftc")
if compiler is None:
    print("SKIP: actual coordinator runtime check requires Xcode 27 / Swift 6")
else:
    with tempfile.TemporaryDirectory(prefix="astra-sync-coordinator-") as tmp:
        fixture = Path(tmp) / "coordinator.swift"
        fixture.write_text(swift)
        binary = Path(tmp) / "check"
        subprocess.run([compiler, "-swift-version", "6", "-parse-as-library",
                        "astra/Storage/BrowserSyncSchedule.swift", str(fixture), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=30)
