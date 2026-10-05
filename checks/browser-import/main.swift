// Run from the repository root:
// swiftc astra/Models/Library/Bookmark.swift astra/Models/Tabs/BrowserVisit.swift astra/Storage/BrowserUserData.swift astra/Storage/BrowserImportSource.swift astra/Storage/BrowserProfileImporter.swift checks/browser-import/main.swift -o /tmp/astra-browser-import-check && /tmp/astra-browser-import-check
import Foundation
import SQLite3

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
	precondition(condition(), message)
}

func database(_ url: URL, sql: String) throws {
	var handle: OpaquePointer?
	guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
		throw CocoaError(.fileWriteUnknown)
	}
	defer { sqlite3_close(handle) }
	guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
		throw NSError(domain: "SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
	}
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let date = Date(timeIntervalSince1970: 1_750_000_000)
let chrome = root.appendingPathComponent("Default")
try FileManager.default.createDirectory(at: chrome, withIntermediateDirectories: true)
let chromiumJSON = #"{"roots":{"bookmark_bar":{"type":"folder","name":"Work","children":[{"type":"url","name":"Example & Test","url":"https://example.com/"},{"type":"url","name":"Internal","url":"chrome://settings"},{"type":"folder","name":"Nested","children":[{"type":"url","name":"Other","url":"https://other.example/"}]}]}}}"#
try Data(chromiumJSON.utf8).write(to: chrome.appendingPathComponent("Bookmarks"))
try database(chrome.appendingPathComponent("History"), sql: """
CREATE TABLE urls (id INTEGER, url TEXT, title TEXT);
CREATE TABLE visits (url INTEGER, visit_time REAL);
INSERT INTO urls VALUES (1, 'https://example.com/', 'Example');
INSERT INTO visits VALUES (1, \((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000));
INSERT INTO visits VALUES (1, \((date.timeIntervalSince1970 + 11_644_473_600 + 60) * 1_000_000));
""")
let profile = BrowserImportProfile(source: .chrome, directory: chrome, name: "Default", sidebar: nil)
let preview = try BrowserProfileImporter.read(profile, scope: .all)
require(preview.document.bookmarks.count == 2, "Chromium URL filtering")
require(preview.document.bookmarks[1].folder == "Work/Nested", "Chromium folder nesting")
require(preview.document.history.count == 2, "Preserve repeated visits")
require(preview.document.history[1].visitedAt == date, "Chromium epoch")
let historyOnly = try BrowserProfileImporter.read(profile, scope: .history)
require(historyOnly.document.bookmarks.isEmpty, "History-only import")
for source in BrowserImportSource.allCases where source != .safari && source != .firefox && source != .arc {
	let found = try BrowserProfileImporter.profiles(for: source, in: root)
	require(found.count == 1, "Chromium profile discovery for \(source)")
	let result = try BrowserProfileImporter.read(BrowserImportProfile(source: source, directory: chrome, name: "Default", sidebar: nil), scope: .all)
	require(result.document.bookmarks.count == 2 && result.document.history.count == 2, "Chromium data reader for \(source)")
}

let safari = root.appendingPathComponent("Safari")
try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
let plist: [String: Any] = ["Children": [["Title": "Favorites", "Children": [["URLString": "https://example.com/", "URIDictionary": ["title": "Safari Example"]]]]]]
try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: safari.appendingPathComponent("Bookmarks.plist"))
try database(safari.appendingPathComponent("History.db"), sql: """
CREATE TABLE history_items (id INTEGER, url TEXT);
CREATE TABLE history_visits (history_item INTEGER, title TEXT, visit_time REAL);
INSERT INTO history_items VALUES (1, 'https://example.com/');
INSERT INTO history_visits VALUES (1, 'Safari Example', \(date.timeIntervalSince1970 - 978_307_200));
""")
let safariResult = try BrowserProfileImporter.read(BrowserImportProfile(source: .safari, directory: safari, name: "Safari", sidebar: nil), scope: .all)
require(safariResult.document.bookmarks.first?.folder == "Favorites", "Safari plist folders")
require(safariResult.document.history.first?.visitedAt == date, "Safari epoch")
let firefox = root.appendingPathComponent("Firefox")
try FileManager.default.createDirectory(at: firefox, withIntermediateDirectories: true)
try database(firefox.appendingPathComponent("places.sqlite"), sql: """
CREATE TABLE moz_places (id INTEGER, url TEXT, title TEXT);
CREATE TABLE moz_historyvisits (place_id INTEGER, visit_date REAL);
CREATE TABLE moz_bookmarks (id INTEGER, parent INTEGER, title TEXT, fk INTEGER, type INTEGER, position INTEGER, guid TEXT);
INSERT INTO moz_places VALUES (1, 'https://example.com/', 'Firefox Example');
INSERT INTO moz_historyvisits VALUES (1, \(date.timeIntervalSince1970 * 1_000_000));
INSERT INTO moz_bookmarks VALUES (1, 0, '', NULL, 2, 0, 'root________'), (2, 1, 'Toolbar', NULL, 2, 0, 'toolbar_____'), (3, 2, 'Research', NULL, 2, 0, 'folder-id'), (4, 3, 'Firefox Example', 1, 1, 0, 'bookmark-id'), (5, 1, 'Tags', NULL, 2, 0, 'tags________'), (6, 5, 'Tag', NULL, 2, 0, 'tag-id'), (7, 6, '', 1, 1, 0, 'tag-link-id');
""")
let firefoxResult = try BrowserProfileImporter.read(BrowserImportProfile(source: .firefox, directory: firefox, name: "Firefox", sidebar: nil), scope: .all)
require(firefoxResult.document.bookmarks.count == 1, "Firefox tags are not bookmark folders")
require(firefoxResult.document.bookmarks.first?.folder == "Toolbar/Research", "Firefox parent folders")
require(firefoxResult.document.history.first?.visitedAt == date, "Firefox epoch")
let arcJSON = #"{"sidebar":{"containers":["container-key",{"items":["root-key",{"id":"root","data":{"list":{}}},{"id":"folder","parentID":"root","title":"Research","data":{"list":{}}},{"id":"tab","parentID":"folder","title":"Renamed Pin","data":{"tab":{"savedURL":"https://example.com/","savedTitle":"Original"}}},{"id":"today","data":{"tab":{"url":"https://today.example/"}}}],"spaces":["space-key",{"title":"Work","itemContainerIDs":["root"]}]}]}}"#
let arcBookmarks = try BrowserProfileImporter.arcBookmarks(Data(arcJSON.utf8))
require(arcBookmarks.count == 1, "Arc saved pins only")
require(arcBookmarks.first?.folder == "Arc/Work/Research", "Arc spaces and folders")
require(arcBookmarks.first?.name == "Renamed Pin", "Arc custom title")
let html = preview.document.encodedHTML()
let roundTrip = try BrowserUserData.decode(html, isHTML: true)
require(roundTrip.bookmarks.count == 2, "HTML round trip")
let historyExport = BrowserImportScope.history.selecting(preview.document)
let historyRoundTrip = try BrowserUserData.decode(JSONEncoder().encode(historyExport), isHTML: false)
require(historyRoundTrip.bookmarks.isEmpty && historyRoundTrip.history.count == 2, "History export isolation and round trip")
let missing = BrowserImportProfile(source: .chrome, directory: root.appendingPathComponent("missing"), name: "Missing", sidebar: nil)
do {
	_ = try BrowserProfileImporter.read(missing, scope: .all)
	preconditionFailure("Missing source must fail")
} catch {}
let brokenHistory = root.appendingPathComponent("Broken")
try FileManager.default.createDirectory(at: brokenHistory, withIntermediateDirectories: true)
try Data(chromiumJSON.utf8).write(to: brokenHistory.appendingPathComponent("Bookmarks"))
let partial = try BrowserProfileImporter.read(BrowserImportProfile(source: .chrome, directory: brokenHistory, name: "Broken", sidebar: nil), scope: .all)
require(partial.document.bookmarks.count == 2 && partial.document.history.isEmpty && partial.warnings.count == 1, "Report partial imports")
let walURL = root.appendingPathComponent("WALHistory")
try FileManager.default.createDirectory(at: walURL, withIntermediateDirectories: true)
var writer: OpaquePointer?
require(sqlite3_open(walURL.appendingPathComponent("History").path, &writer) == SQLITE_OK, "Open WAL fixture")
let walSQL = "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE urls (id INTEGER, url TEXT, title TEXT); CREATE TABLE visits (url INTEGER, visit_time REAL); INSERT INTO urls VALUES (1, 'https://wal.example/', 'WAL'); INSERT INTO visits VALUES (1, \((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000));"
require(sqlite3_exec(writer, walSQL, nil, nil, nil) == SQLITE_OK, "Create WAL fixture")
let walResult = try BrowserProfileImporter.read(BrowserImportProfile(source: .chrome, directory: walURL, name: "WAL", sidebar: nil), scope: .history)
require(walResult.document.history.count == 1, "Read committed WAL visits while source is open")
sqlite3_close(writer)
print("Browser import checks passed")
