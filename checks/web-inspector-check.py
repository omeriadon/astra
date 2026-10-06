"""Run with python3 checks/web-inspector-check.py. Checks the production inspector preference on an unmounted WebView."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "astra/Web/Navigation/BrowserDesktopCommands.swift").read_text()
start = source.index("\t\tstatic func configureWebInspector(")
end = source.index("\n\t\tstatic func showWebInspector(", start)
configuration = source[start:end]
check = """
import AppKit
import WebKit

@MainActor
enum InspectorCheck {
CONFIGURATION
}

MainActor.assumeIsolated {
    let webView = WKWebView(frame: .zero)
    for enabled in [true, false, true, false] {
        InspectorCheck.configureWebInspector(webView, enabled: enabled)
        assert(webView.isInspectable == enabled)
        let preferences = webView.configuration.preferences
        if preferences.responds(to: NSSelectorFromString("_setDeveloperExtrasEnabled:")) {
            assert(preferences.value(forKey: "developerExtrasEnabled") as? Bool == enabled)
        }
    }
}
print("Web Inspector preference check passed")
""".replace("CONFIGURATION", configuration)
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "inspector-check.swift"
    path.write_text(check)
    subprocess.run(["swift", str(path)], check=True)
