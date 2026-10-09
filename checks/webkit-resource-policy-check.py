"""WebKit resource manager must enforce pressure budgets without sacrificing active media."""
from pathlib import Path
browser = Path("astra/Models/Core/Browser.swift").read_text()
view = Path("astra/UI/Content/BrowserContentView.swift").read_text()
assert "lazy var tabResources = BrowserTabResourceManager(browser: self)" in browser
assert "tabResources.updateMemoryPressure(level)" in browser
assert "automaticHibernationManager?.handleMemoryPressure(level)" in browser
assert "ForEach(browser.tabResources.controllersForDisplay())" in view
assert "private func keepAliveControllers()" not in view
policy = view.split("final class BrowserTabResourceManager", 1)[1].split("private struct HibernatedPlaceholder", 1)[0]
for text in (
    "private(set) var warmControllerLimit = 4",
    "case .normal: limit = 4",
    "case .warning: limit = 2",
    "case .critical: limit = 1",
    "for id in browser.recentlyUsedTabIDs where result.count < warmControllerLimit",
    "let ownedTabIDs = BrowserWindowRegistry.shared.ownedTabIDs(in: browser)",
    "guard let controller, controller.url != nil, seen.insert(controller.id).inserted",
    "append(tab.controller?.shouldKeepWebViewAttached == true ? tab.controller : nil)",
    "if peek.controller.shouldKeepWebViewAttached",
):
    assert text in policy, text
assert policy.index("for id in browser.recentlyUsedTabIDs") < policy.index("for tab in browser.tabs")
print("Adaptive WebKit tab resource budget and protected media/peek retention checks passed")
