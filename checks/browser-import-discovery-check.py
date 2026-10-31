#!/usr/bin/env python3
"""Exercise production profile discovery with real temporary browser directories.

Run on a macOS Swift 6.2+ host: python3 checks/browser-import-discovery-check.py
The view checks below run without Swift; directory/runtime checks explicitly skip.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
importer = (root / 'astra/Storage/BrowserProfileImporter.swift').read_text()
view = (root / 'astra/UI/Settings/Detail/BrowserImportView.swift').read_text()
source = (root / 'astra/Storage/BrowserImportSource.swift').read_text()

# A folder grant belongs to the worker using it, never the view's lifetime.
assert '.onDisappear' not in view
assert 'folder = (selectedSource, url)' in view
assert 'guard source == selectedSource else { return }' in view
assert 'folder?.source == source ? folder?.url : nil' in view
assert 'folder?.source == profile.source ? folder?.url : nil' in view
assert 'withFolderAccess(to: directory)' in view
assert 'withFolderAccess(to: accessFolder)' in view
assert 'defer {' in importer.split('static func withFolderAccess', 1)[1].split('static func profiles', 1)[0]
assert 'case .helium: "Application Support/net.imput.helium"' in source
print('PASS: folder access ownership, source association, and Helium path checks', flush=True)

swift = shutil.which('swiftc')
if not swift:
    print('SKIP: production Swift discovery/runtime checks (swiftc unavailable)')
    raise SystemExit(0)

# Use the exact production discovery implementation, with logging and unused
# data-model boundaries stubbed so no SwiftUI/AppKit app target is required.
start = importer.index('\tstatic func profiles(')
end = importer.index('\n\tstatic func read(', start)
discovery = importer[start:end]
fixture = r'''
import Foundation
struct BrowserUserData {
    var bookmarks: [Int]
    var history: [Int]
}
enum BrowserLog {
    enum Category { case persistence }
    static func info(_ category: Category, _ event: String, metadata: [String: String]) {}
    static func path(_ url: URL?) -> String { url?.path ?? "" }
}
'''
fixture += source + '\nenum BrowserProfileImporter {\n' + discovery + '\n}\n'
fixture += r'''
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
func file(_ path: String, _ text: String = "") throws {
    let url = root.appendingPathComponent(path)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}
try file("net.imput.helium/Default/History")
try file("net.imput.helium/Profile 2/Bookmarks")
try file("net.imput.helium/Cache/entry")
try file("net.imput.helium/Not a directory")
try file("net.imput.helium/Local State", #"{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 2":{"name":"Work"}}}}"#)
let helium = root.appendingPathComponent("net.imput.helium")
let profiles = try BrowserProfileImporter.profiles(for: .helium, in: helium)
precondition(profiles.map(\.name) == ["Personal (Default)", "Work (Profile 2)"])
let direct = try BrowserProfileImporter.profiles(for: .helium, in: helium.appendingPathComponent("Default"))
precondition(direct.count == 1 && direct[0].directory.lastPathComponent == "Default")
try fm.createDirectory(at: root.appendingPathComponent("Empty"), withIntermediateDirectories: true)
let empty = try BrowserProfileImporter.profiles(for: .helium, in: root.appendingPathComponent("Empty"))
precondition(empty.isEmpty)
do {
    _ = try BrowserProfileImporter.profiles(for: .helium, in: root.appendingPathComponent("Missing"))
    preconditionFailure("Missing folders must report a filesystem error")
} catch {}
try file("Firefox/random.default/places.sqlite")
let firefox = try BrowserProfileImporter.profiles(for: .firefox, in: root.appendingPathComponent("Firefox"))
precondition(firefox.count == 1)
try file("Arc/StorableSidebar.json", "{}")
try file("Arc/User Data/Default/History")
let arc = try BrowserProfileImporter.profiles(for: .arc, in: root.appendingPathComponent("Arc"))
precondition(arc.count == 1 && arc[0].sidebar?.lastPathComponent == "StorableSidebar.json")
// POSIX permission assertions are meaningful only when not running as root.
let locked = root.appendingPathComponent("Locked")
try fm.createDirectory(at: locked, withIntermediateDirectories: true)
try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
if !fm.isReadableFile(atPath: locked.path) {
    do {
        _ = try BrowserProfileImporter.profiles(for: .helium, in: locked)
        preconditionFailure("Unreadable folders must report a permission error")
    } catch {}
} else {
    print("SKIP: permission fixture (host can read mode-000 directories)")
}
print("PASS: Helium root/direct profiles, labels, empty/missing folders, Firefox, Arc, permission recovery")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(fixture)
    executable = Path(directory) / 'browser-import-check'
    subprocess.run([swift, '-swift-version', '6', str(path), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
