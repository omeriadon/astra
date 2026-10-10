"""Regression guard for safe, bounded reuse of validated disk checkpoints."""
from pathlib import Path
import re
source = Path("astra/Storage/BrowserPersistence.swift").read_text()
runtime = Path("docs/astra-roadmap/checks-03-persistence.swift").read_text()

assert "checkpointCache: NSCache<NSString, CachedCheckpoint>" in source
assert "cache.totalCostLimit = 24 * 1024 * 1024" in source
assert "data.count <= 8 * 1024 * 1024 ? data : nil" in source
for marker in (
    "attributes[.systemFileNumber]",
    "attributes[.size]",
    "attributes[.modificationDate]",
    "candidate.signature == signature",
    "cached?.backupSignature == backupSignature",
    "try rejectUnsupportedEnvelopeVersion(backupData)",
    "privateDataWasRemoved = previous.hasPrivacyRemoval(comparedTo: state)",
    "try data.write(to: backupURL, options: .atomic)",
    "CheckpointSignature(at: currentURL)",
    "CachedCheckpoint(",
):
    assert marker in source, marker
for marker in (
    "historyURLs.contains(where:",
    "bookmarkURLs.contains(where:",
    "readingURLs.contains(where:",
    "!closedTabIDs.isSubset(of: currentClosed)",
    "previous.history.isSubset(of: Set(updated.history))",
    "deletedVisitsAt.contains(where:",
    "return containedCredentialURLs",
):
    assert marker in source, marker
assert re.search(
    r"previousIndex\s*=\s*(?:try\s+PrivacyDeletionIndex\s*\(\s*decodeSnapshot\s*\(\s*previousData\s*\)\s*\)|PrivacyDeletionIndex\s*\(\s*try\s+decodeSnapshot\s*\(\s*previousData\s*\)\s*\))",
    source,
), "Previous checkpoint must undergo validated decode before building privacy index"
assert re.search(
    r"if\s+previousPrimaryWasUnavailable\s*(?:&&|,)\s*backupPrevious\s*!=\s*nil\s*,\s*let\s+backupData",
    source,
), "Recovery must preserve the last valid backup before removing private data"
assert re.search(
    r"if\s+previous\.recordsNavigationHistory\s*(?:&&|,)\s*!updated\.recordsNavigationHistory",
    source,
), "Disabling navigation history must count as a privacy deletion"
assert source.index("try data.write(to: currentURL, options: .atomic)") < source.index("Self.checkpointCache.setObject(")
for marker in (
    "withPrivateHistory.historyVisits = [privateVisit]",
    "try privacyPersistence.savePersistedState(withPrivateHistory)",
    "withoutPrivateHistory.historyVisits = []",
    "privacyRecovered?.historyVisits?.isEmpty == true",
    "Warm cache allowed newer schema to be overwritten",
):
    assert marker in runtime, marker
print("Bounded checkpoint cache, privacy-deletion and recovery invariants verified")
