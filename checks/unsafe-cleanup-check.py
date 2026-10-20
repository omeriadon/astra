#!/usr/bin/env python3
"""Compile and stress the production throttle and compare diagnostic formatting."""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    engine = (ROOT / 'astra/Web/Downloads/SegmentedDownloadEngine.swift').read_text()
    storage = next(line.strip() for line in engine.splitlines() if 'let lastProgressHop = ' in line)
    throttle = engine.split('\t\tlet due = lastProgressHop.withLock', 1)[1].split('\n\t\tguard due else', 1)[0]
    reset = next(line.strip() for line in engine.splitlines() if 'lastProgressHop.withLock { $0[description] = nil }' in line)
    hex_expressions = []
    for path in ('astra/Automation/Spotlight/AstraSpotlightIndexer.swift',
                 'astra/Web/ContentBlocking/BrowserContentBlockingModel.swift'):
        text = (ROOT / path).read_text()
        line = next(line for line in text.splitlines() if 'let digest = SHA256.hash' in line)
        hex_expressions.append(line.split('.map { ', 1)[1].split(' }.joined()', 1)[0])
    source = '''import Dispatch
import Foundation
import Synchronization

nonisolated final class Throttle: Sendable {
    STORAGE
    func due(key: String, now: Date) -> Bool {
        let due = lastProgressHop.withLockTHROTTLE
        return due
    }
    func reset(_ description: String) { RESET }
}

@main struct UnsafeCleanupCheck {
    static func main() {
        let values: [Double] = [0, -0.0, 0.05, -0.05, 1.25, -1.25,
            1.005, 9.995, 9999999.9995, .leastNonzeroMagnitude,
            .greatestFiniteMagnitude, .infinity, -.infinity, .nan]
        let formats: [(String, BrowserLog.DecimalPlaces)] = [
            ("%.0f", .whole), ("%.1f", .tenths),
            ("%.2f", .hundredths), ("%.3f", .thousandths)]
        for value in values {
            for (format, places) in formats {
                let expected = unsafe String(format: format, value)
                precondition(BrowserLog.fixedDecimal(value, places: places) == expected,
                    "Changed printf result for \\(value), \\(format)")
            }
        }
        for byte in UInt8.min...UInt8.max {
            let expected = unsafe String(format: "%02x", byte)
            precondition(({ (value: UInt8) in HEX1 })(byte) == expected)
            precondition(({ (value: UInt8) in HEX2 })(byte) == expected)
        }
        let throttle = Throttle()
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let reports = Mutex(0)
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            if throttle.due(key: "same-task", now: now) {
                reports.withLock { $0 += 1 }
            }
            BrowserLog.bootstrap()
        }
        precondition(reports.withLock { $0 } == 1)
        precondition(!throttle.due(key: "same-task", now: now.addingTimeInterval(0.099)))
        precondition(throttle.due(key: "same-task", now: now.addingTimeInterval(0.1)))
        precondition(throttle.due(key: "other-task", now: now))
        throttle.reset("same-task")
        precondition(throttle.due(key: "same-task", now: now))
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            let key = String(index)
            precondition(throttle.due(key: key, now: now))
            throttle.reset(key)
            precondition(throttle.due(key: key, now: now))
        }
        print("Formatting compatibility and concurrent throttle/bootstrap checks passed")
    }
}
'''
    source = source.replace('STORAGE', storage).replace('THROTTLE', throttle).replace('RESET', reset)
    for index, expression in enumerate(hex_expressions, 1):
        source = source.replace(f'HEX{index}', expression.replace('$0', 'value'))
    with tempfile.TemporaryDirectory(prefix='astra-unsafe-cleanup-') as directory:
        fixture = Path(directory) / 'Check.swift'
        fixture.write_text(source)
        binary = Path(directory) / 'check'
        for flags in (['-Onone'], ['-O'], ['-Onone', '-sanitize=thread']):
            subprocess.run(['xcrun', 'swiftc', '-swift-version', '6',
                '-default-isolation', 'MainActor', '-strict-concurrency=complete',
                '-strict-memory-safety', *flags,
                str(ROOT / 'astra/App/BrowserLog.swift'), str(fixture), '-o', str(binary)], check=True)
            # Verify nil-locale printf results remain independent of user locale.
            import os
            for locale in ('C', 'en_US.UTF-8', 'de_DE.UTF-8'):
                subprocess.run([str(binary)], check=True, env={**os.environ, 'LC_ALL': locale})


if __name__ == '__main__':
    main()
