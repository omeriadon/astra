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
    "for id in browser.recentlyUsedTabIDs where result.count < warmControllerLimit",
    "let ownedTabIDs = BrowserWindowRegistry.shared.ownedTabIDs(in: browser)",
    "guard let controller, controller.url != nil, seen.insert(controller.id).inserted",
    "append(tab.controller?.shouldKeepWebViewAttached == true ? tab.controller : nil)",
    "if peek.controller.shouldKeepWebViewAttached",
):
    assert text in policy, text
assert "let limit = switch level {" in policy
for case, expected in (("normal", 4), ("warning", 2), ("critical", 1)):
    # Swift 6 permits both switch expressions and assignment statements.
    assert (
        f"case .{case}: {expected}" in policy
        or f"case .{case}: limit = {expected}" in policy
    ), f"Expected warm-controller limit {expected} for {case} pressure"
assert policy.index("for id in browser.recentlyUsedTabIDs") < policy.index("for tab in browser.tabs")
print("Adaptive WebKit tab resource budget and protected media/peek retention checks passed")

# Startup page attachment must not poll expensive WebKit screenshots without
# an actual handoff curtain. Only reparenting an existing preview needs it.
webview = Path("astra/Web/Navigation/BrowserWebView.swift").read_text()
handoff = webview.split("if webView.superview !== self {", 1)[1].split(
    "// WebKit owns the page frame while its inspector is docked", 1
)[0]
assert "curtain.isHidden = !specification.isVisible || curtain.image == nil" in handoff
assert "if !curtain.isHidden {" in handoff
assert handoff.index("if !curtain.isHidden {") < handoff.index("handoffTask = Task {")
print("WebKit first-attach snapshot work is guarded by visible curtain")
