"""Regression guards for automatic segmented download recovery.

These supplement the macOS compilation job; the network-drop integration test
still requires exercising a live download with Wi-Fi toggled.
"""
from pathlib import Path

engine = Path("astra/Web/Downloads/SegmentedDownloadEngine.swift").read_text()
manager = Path("astra/Web/Downloads/BrowserDownloadManager.swift").read_text()
model = Path("astra/Models/Library/BrowserDownload.swift").read_text()

assert "NWPathMonitor()" in engine
assert "await checkForStalls(threshold: 0)" in engine
assert "await checkForStalls(threshold: 90)" in engine
assert "task.cancel()" in engine
assert "scheduleRetry(itemID)" in engine
assert "NSURLErrorNetworkConnectionLost" in engine
assert "NSURLErrorNotConnectedToInternet" in engine
assert "NSURLErrorTimedOut" in engine

# Transport should never trigger fallback for recoverable transport errors.
failed = engine.split("private func failed(", 1)[1].split("private let delegateQueue", 1)[0]
assert failed.index("scheduleRetry(itemID)") < failed.index("manager?.segmentFailed(itemID)")
assert "activeTaskIDs[key] == taskID" in failed

# Do not accept a late cancelled attempt's temporary file.
assert "guard segmented.acceptsCompletion(itemID, index: index, taskID: taskID)" in manager
assert "Self.partURL(itemID, index: index, taskID: taskID)" in engine

# A restart should request only unfinished ranges and retain completed pieces.
start = engine.split("func start(_ item:", 1)[1].split("func fallbackRequest(", 1)[0]
assert "where !segment.completed" in start
assert "let segments = current.segments" in start
assert "task.resume()" in start

# Pausing or closing must invalidate recovery and retain replay headers for resume.
pause = engine.split("func pause(_ itemID:", 1)[1].split("func cancel(", 1)[0]
assert "stopMonitoring(itemID)" in pause
assert "replayHeaders[itemID] = nil" not in engine.split("func stopMonitoring(", 1)[1].split("func forget(", 1)[0]
cancel_and_wait = engine.split("func cancelAndWait(", 1)[1].split("nonisolated func urlSession(", 1)[0]
assert "for itemID in itemIDs {" in cancel_and_wait
assert "forget(itemID)" in cancel_and_wait
assert "segmented.forget(itemID)" in manager

# A stalled transfer cannot continue displaying a stale ETA.
assert "items[index].estimatedTimeRemaining = nil" in manager.split("func setSegmentConnectionMessage(", 1)[1].split("private func markFailed", 1)[0]
assert 'if let errorMessage, segments != nil' in model
print("Download recovery structure checks passed")
