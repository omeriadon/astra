"""Verify launch hydration does not serialize independent key and disk work."""
from pathlib import Path

source = Path("astra/Models/Core/Browser.swift").read_text()
block = source.split("Self.launchHydrationTask = Task.detached", 1)[1].split(
    "guard let hydrationTask = Self.launchHydrationTask", 1
)[0]
start_key = block.index("let restorationPreparation = Task")
start_disk = block.index("let persisted = try persistence.loadPersistedState()")
first_wait = block.index("await restorationPreparation.value")
assert start_key < start_disk < first_wait, "Keychain and disk must overlap"
assert block.count("await restorationPreparation.value") == 2, (
    "Both current and legacy restoration paths must await the key before publishing"
)
assert block.count("let previousShutdownWasClean = await launchMetadataTask?.value") == 2
assert "startup.persisted-state-read" in block
print("Startup concurrent hydration dependency checks passed")

# Only foreground WebKit should be constructed when restoring a session.
restoration_start = source.index("let restoredTabs = savedTabs.compactMap")
restoration_end = source.index("var newTabs = restoredTabs", restoration_start)
restoration = source[restoration_start:restoration_end]
assert "let savedTabs = loaded.tabs" in source, (
    "New Tabs must be retained for restoration, even without a URL"
)
assert "loaded.tabs.filter { !$0.isDiscardableNewTab }" not in source
assert "foregroundSavedID" in source
assert "savedWindow?.restoredSelection(availableTabIDs:" in source
assert "isHibernated: saved.isHibernated || startupBehavior != .restore || saved.id != foregroundSavedID" in restoration
assert "initialRestorationBaseline: saved" in restoration
assert "selectedTab.wake()" in source
registry = Path("astra/Models/Core/BrowserWindowRegistry.swift").read_text()
assert "if browser.isHydrationFinished, browser.selectedTab?.isHibernated == true" in registry
app = Path("astra/App/AppDelegate.swift").read_text()
assert "let firstWindowUpdates = AsyncStream<Void>" in app
assert "await withTaskGroup(of: Bool.self)" in app
assert 'try? await Task.sleep(for: .milliseconds(400))' in app
assert 'startup.first-window-frame-gate' in app
assert "foreground.browser.selectTab(foreground.browser.selectedTabID)" in app
print("Foreground-only startup WebKit and first-frame gate checks passed")
