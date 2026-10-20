#!/usr/bin/env python3
"""Compile actual production validators in isolation, compare baseline/cached results.
Run with python3 checks/sync-url-validation-check.py [--benchmark] on Swift hosts.
"""
import pathlib, shutil, subprocess, tempfile, sys
root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'astra/Models/Core/BrowserSyncDocument.swift').read_text()

def extract(text, name):
    start = text.index('private nonisolated func ' + name)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end].replace('private nonisolated func ', 'func ')

functions = '\n'.join(extract(source, n) for n in ('isSyncScheme', 'isPortableSyncURL', 'isSafeSyncURL', 'credentialFreeSyncURL'))
assert 'CharacterSet.whitespacesAndNewlines.union' not in functions
assert functions.count('SyncURLValidation.disallowedHostScalars.contains') == 2
swift = shutil.which('swiftc')
if not swift:
    print('PASS: cached scalar set used by both production validators; SKIP Swift correctness/benchmark (swiftc unavailable)')
    sys.exit(0)
fixture = r'''
let cases: [(String, Bool, Bool)] = [
    ("https://example.org", true, true),
    ("HTTP://example.org:65535/a", true, true),
    ("https://bücher.example/日本語", true, true),
    ("https://[::1]:443/", true, true),
    ("https://user:secret@example.org/", true, false),
    ("https://user@example.org/", true, false),
    ("https://example.org:0/", false, false),
    ("https://example.org:65536/", false, false),
    ("https://example.org:-1/", false, false),
    ("https://example.org:abc/", false, false),
    ("https:///", false, false),
    ("/relative/path", false, false),
    ("file:///private/local", false, false),
    ("ftp://example.org/", false, false),
    ("https://bad%20host.example/", false, false),
    ("https://bad%00host.example/", false, false),
    ("https://bad%0Ahost.example/", false, false),
    ("https://example.org/" + String(repeating: "a", count: 16384), false, false),
]
for (raw, portable, safe) in cases {
    guard let url = URL(string: raw) else {
        precondition(!portable && !safe, "Unexpected parse rejection")
        continue
    }
    precondition(isPortableSyncURL(url) == portable, "Portable mismatch: " + raw)
    precondition(isSafeSyncURL(url) == safe, "Safe mismatch: " + raw)
    if portable {
        let sanitized = credentialFreeSyncURL(url)
        precondition(isSafeSyncURL(sanitized))
        precondition(sanitized.user == nil && sanitized.password == nil)
    }
}
let urls = (0..<10000).map { URL(string: "https://www.example-international-publication.org/article/\($0)")! }
var accepted = 0
let start = ProcessInfo.processInfo.systemUptime
for _ in 0..<5 {
    for url in urls {
        if isPortableSyncURL(url) { accepted += 1 }
        if isSafeSyncURL(url) { accepted += 1 }
    }
}
precondition(accepted == 100000)
print("100000 validations elapsed_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
'''
cached = 'enum SyncURLValidation { static let disallowedHostScalars = CharacterSet.whitespacesAndNewlines.union(.controlCharacters) }\n'
with tempfile.TemporaryDirectory() as directory:
    for mode, optimization in (('cached-release', '-O'), ('baseline-release', '-O'), ('cached-debug', '-Onone'), ('baseline-debug', '-Onone')):
        body = functions
        if mode.startswith('baseline'):
            body = body.replace('SyncURLValidation.disallowedHostScalars', 'CharacterSet.whitespacesAndNewlines.union(.controlCharacters)')
        path = pathlib.Path(directory) / 'main.swift'
        path.write_text('import Foundation\n' + cached + body + '\n' + fixture)
        binary = pathlib.Path(directory) / mode
        subprocess.run([swift, optimization, '-swift-version', '6', str(path), '-o', str(binary)], check=True)
        print(mode, flush=True)
        subprocess.run([str(binary)], check=True)
print('PASS: production URL correctness and before/after benchmark')
