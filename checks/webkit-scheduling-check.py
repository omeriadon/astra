"""Run with python3 checks/webkit-scheduling-check.py. Does not launch Astra."""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
content = (root / "astra/UI/Content/BrowserContentView.swift").read_text()
web_view = (root / "astra/Web/Navigation/BrowserWebView.swift").read_text()
controller = (root / "astra/Web/Navigation/BrowserController.swift").read_text()


assert "where result.count < 4" in content
assert "Inactive WebViews are" in content

hidden_creation_guard = "if !specification.isVisible, controller.webViewIfLoaded == nil"
assert hidden_creation_guard in web_view
mount_source = web_view[web_view.index("func mountIfReady()"):]
assert mount_source.index(hidden_creation_guard) < mount_source.index("let webView = controller.webView")
assert web_view.count("unmountWebView()") >= 4
assert "controller.webViewIfLoaded" in web_view

assert "var shouldKeepWebViewAttached: Bool" in controller
assert "requiresMediaTeardownConfirmation" in controller
assert "inactiveSchedulingPolicy = requiresContinuousScheduling ? .none : .throttle" in controller
assert ".suspend is deliberately not selected" in controller
assert "inactiveSchedulingPolicy = .suspend" not in controller

print("WebKit scheduling source check passed")
