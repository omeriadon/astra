"""Check revision-bound history projections preserve observation and invalidate correctly."""
from pathlib import Path
source = Path("astra/Models/Core/Browser.swift").read_text()
history = source.split("private(set) var historyVisits: [BrowserVisit]", 1)[1].split(
    "/// Reuse the expensive per-URL", 1
)[0]
for marker in (
    "historySearchIndex = nil",
    "recentHistoryCache = nil",
    "frequentHistoryCache = nil",
    "historyChangeRevision &+= 1",
):
    assert marker in history, marker
for name, cache in (
    ("recentHistoryVisits", "recentHistoryCache"),
    ("frequentHistory", "frequentHistoryCache"),
):
    block = source.split(f"var {name}: ", 1)[1].split("\n\tvar ", 1)[0]
    assert "let revision = historyChangeRevision" in block
    assert f"cache = {cache}" in block
    assert "cache.revision == revision" in block
    assert f"{cache} = (revision, result)" in block
    assert "return result" in block
assert "@ObservationIgnored private var recentHistoryCache" in source
assert "@ObservationIgnored private var frequentHistoryCache" in source
print("History projection observation and cache invalidation checks passed")
