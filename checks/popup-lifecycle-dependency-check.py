"""Exercise the production weak popup dependency predicate and registration contract."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'astra/Web/Navigation/BrowserController.swift').read_text()
start = source.index('\tprivate var hasLivePopupDependency: Bool {')
end = source.index('\n\tfunc beginLifecycleOperation()', start)
predicate = source[start:end].replace('private var', 'var', 1)
assert 'livePopupControllers.add(controller)' in source
assert '!hasLivePopupDependency' in source
assert '|| hasLivePopupDependency' in source
assert 'livePopupControllers.removeAllObjects()' in source
program = '''
import Foundation
@MainActor final class BrowserController: NSObject {
    let livePopupControllers = NSHashTable<BrowserController>.weakObjects()
    var webViewIfLoaded: NSObject? = NSObject()
''' + predicate + '''
}
@main enum PopupDependencyCheck {
    @MainActor static func main() {
        let parent = BrowserController()
        var child: BrowserController? = BrowserController()
        weak var weakChild = child
        parent.livePopupControllers.add(child!)
        precondition(parent.hasLivePopupDependency)
        child!.webViewIfLoaded = nil
        precondition(!parent.hasLivePopupDependency)
        child!.webViewIfLoaded = NSObject()
        precondition(parent.hasLivePopupDependency)
        child = nil
        precondition(weakChild == nil)
        precondition(!parent.hasLivePopupDependency)
        print("Production weak popup dependency checks passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='astra-popup-dependency-') as directory:
    path = Path(directory) / 'Check.swift'
    binary = Path(directory) / 'check'
    path.write_text(program)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6', '-strict-concurrency=complete', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
