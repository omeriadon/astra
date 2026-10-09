"""Window startup sidecar must be checkpoint-bound and fail open to full recovery."""
from pathlib import Path
source = Path("astra/Storage/BrowserPersistence.swift").read_text()
tests = Path("docs/astra-roadmap/checks-03-persistence.swift").read_text()
assert "private nonisolated struct CheckpointSignature: Equatable, Codable" in source
assert "private nonisolated struct WindowRecordsSidecar: Codable" in source
window = source.split("nonisolated func loadWindowRecords()", 1)[1].split("private nonisolated func applyingWindowSelectionUpdates(", 1)[0]
for marker in (
    'directory.appendingPathComponent("browser-state.json")',
    'directory.appendingPathComponent("browser-windows.json")',
    "bytes.count <= 256 * 1024",
    "sidecar.version == 1, sidecar.signature == signature",
    "validateWindowRecords(sidecar.records)",
    "applyingWindowSelectionUpdates(sidecar.records, loadedFrom: primaryURL)",
    "for name in [\"browser-state.json\", \"browser-state.backup.json\"]",
    "JSONDecoder().decode(WindowRecordsEnvelope.self, from: data)",
):
    assert marker in window, marker
assert window.index("sidecar.version == 1") < window.index("for name in")
persist = source.split("nonisolated func savePersistedState(", 1)[1].split("nonisolated func saveShutdownMetadata()", 1)[0]
assert persist.index("try data.write(to: currentURL, options: .atomic)") < persist.index("WindowRecordsSidecar(")
assert persist.index("WindowRecordsSidecar(") < persist.index('directory.appendingPathComponent("browser-windows.json")')
assert "sidecarBytes.count <= 256 * 1024" in persist
assert "window-records.sidecar-write-failed" in persist
for marker in (
    'precondition(FileManager.default.fileExists(atPath: windowSidecar.path))',
    "let indexedRecords = try persistence.loadWindowRecords()",
    'Data("invalid-sidecar".utf8).write(to: windowSidecar)',
    "let fallbackRecords = try persistence.loadWindowRecords()",
):
    assert marker in tests, marker
print("Checkpoint-validated startup sidecar and full-session fallback invariants passed")
