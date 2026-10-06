"""Exercise production sync scheduling and its cancellation catch without network or accounts."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'astra/Storage/BrowserSync.swift').read_text()
schedule = source[source.index('\tfunc scheduleSync()'):source.index('\n\tfunc signIn(')]
# Shorten only the debounce duration; task ownership remains the production implementation.
schedule = schedule.replace('.seconds(2)', '.milliseconds(2)')
sync = source[source.index('\tfunc syncNow()'):source.index('\n\tprivate func settingSnapshot')]
catch = sync[sync.rindex('\t\t} catch'):sync.rindex('\n\t}')]
program = '''import Foundation
@MainActor final class Probe {
    var browser: Int? = 1
    var isSignedIn = true
    var isSyncing = false
    var syncRequestedWhileBusy = false
    var scheduledSync: Task<Void, Never>?
    var errorDescription: String?
''' + schedule + '''
    func syncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await Task.sleep(for: .seconds(10))
''' + catch + '''
    }
}
@main struct Check {
    @MainActor static func main() async throws {
        let probe = Probe()
        probe.scheduleSync()
        try await Task.sleep(for: .milliseconds(30))
        assert(probe.isSyncing)
        let active = probe.scheduledSync!
        probe.scheduleSync()
        try await Task.sleep(for: .milliseconds(30))
        guard !active.isCancelled, probe.errorDescription == nil else {
            print("FAIL: rescheduling cancels an active sync and publishes CancellationError")
            exit(1)
        }
        active.cancel()
        await active.value
        guard probe.errorDescription == nil else {
            print("FAIL: expected cancellation is presented as a sync failure")
            exit(1)
        }
        print("Sync rescheduling preserves active work and cancellation stays out of the error UI")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='astra-sync-check-') as directory:
    swift = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    swift.write_text(program)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
