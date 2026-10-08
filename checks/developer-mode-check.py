"""Run with python3 checks/developer-mode-check.py. Does not launch the app."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
tab = (root / 'astra/Models/Tabs/BrowserTab.swift').read_text()
start = tab.index('\tvar isDeveloperMode: Bool {')
end = tab.index('\n\tvar isHibernated:', start)
property_source = tab[start:end]
commands = (root / 'astra/Web/Navigation/BrowserDesktopCommands.swift').read_text()
host = (root / 'astra/Web/Navigation/BrowserWebView.swift').read_text()
assert 'NSSelectorFromString("detach")' not in commands
assert '__WebInspectorPageGroupLevel1__.WebKit2InspectorAttachmentSide' in commands
assert '"WKInspectorAttach"' in commands
assert 'if !hasDockedInspector {' in host
assert 'BrowserDesktopCommands.attachWebInspector(inspector)' in host
assert 'if wasVisible {' in commands
assert 'toggleElementSelection' in commands

source = '''
import Foundation
enum Defaults {
    enum Key { case developerModeEnabled }
    static var developerModeEnabled = false
    static subscript(_ key: Key) -> Bool { developerModeEnabled }
}
struct Controller {
    var url: URL?
}
struct Tab {
    var internalPage: Bool? = nil
    var activeController: Controller? = nil
    var currentURL: URL? = nil
PROPERTY
}
for address in ["http://localhost:3000", "http://api.localhost", "http://127.0.0.1", "http://[::1]"] {
    assert(Tab(currentURL: URL(string: address)).isDeveloperMode, address)
}
for address in ["https://example.com", "https://localhost.example.com", "https://notlocalhost", "file:///tmp/localhost"] {
    assert(!Tab(currentURL: URL(string: address)).isDeveloperMode, address)
}
assert(!Tab().isDeveloperMode)
Defaults.developerModeEnabled = true
assert(Tab(currentURL: URL(string: "https://example.com")).isDeveloperMode)
Defaults.developerModeEnabled = false
assert(!Tab(internalPage: true, currentURL: URL(string: "http://localhost")).isDeveloperMode)
assert(!Tab(activeController: Controller(url: URL(string: "https://example.com")), currentURL: URL(string: "http://localhost")).isDeveloperMode)
assert(Tab(activeController: Controller(url: URL(string: "http://localhost")), currentURL: URL(string: "https://example.com")).isDeveloperMode)
print("Developer mode check passed")
'''.replace('PROPERTY', property_source)
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'developer-mode.swift'
    path.write_text(source)
    subprocess.run(['swift', str(path)], check=True)
