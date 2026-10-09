"""Execute the production interaction-state restore block without user persistence."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'astra/Web/Navigation/BrowserController.swift').read_text()
start = source.index('\t\tif let state = pendingInteractionState, let webView = createdWebView {')
end = source.index('\n\t\tif let archive = pendingWebArchive', start)
block = source[start:end]
program = '''
import Foundation
final class BackForwardList {
    var currentItem: Int? = 1
    var backList: [Int] = []
}
final class WebView {
    var interactionState: Data?
    let backForwardList = BackForwardList()
}
final class Controller {
    var pendingInteractionState: Data? = Data([1])
    let createdWebView: WebView? = WebView()
    var history = ["older1", "older2", "native1", "current"]
    var historyIndex = 3
    var liveHistoryPrefix = ["older1", "older2"]
    var pendingRequest: Int? = 1
    var pendingLocalFile: Int? = 1
    var updates = 0
    func updateHistory() { updates += 1 }
    func restore() {
''' + block + '''
    }
}
let withPrefix = Controller()
withPrefix.createdWebView!.backForwardList.backList = [1]
withPrefix.restore()
precondition(withPrefix.liveHistoryPrefix == ["older1", "older2"])
precondition(withPrefix.pendingRequest == nil && withPrefix.pendingLocalFile == nil)
precondition(withPrefix.updates == 1 && withPrefix.pendingInteractionState == nil)
let nativeOnly = Controller()
nativeOnly.createdWebView!.backForwardList.backList = [1, 2, 3]
nativeOnly.restore()
precondition(nativeOnly.liveHistoryPrefix.isEmpty)
let invalid = Controller()
invalid.createdWebView!.backForwardList.currentItem = nil
invalid.restore()
precondition(invalid.liveHistoryPrefix == ["older1", "older2"])
precondition(invalid.pendingRequest != nil && invalid.updates == 0)
print("Interaction-state history prefix checks passed")
'''
with tempfile.TemporaryDirectory(prefix='astra-history-restore-') as directory:
    path = Path(directory) / 'main.swift'
    binary = Path(directory) / 'check'
    path.write_text(program)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-strict-concurrency=complete', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
