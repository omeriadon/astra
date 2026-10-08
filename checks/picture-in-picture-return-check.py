"""Run with python3 checks/picture-in-picture-return-check.py on macOS."""

from pathlib import Path
import re
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source = (root / "astra/Web/Navigation/BrowserController.swift").read_text()
callback = re.search(
    r'\t\t@objc\(_webViewFullscreenMayReturnToInline:\)\n'
    r'\t\tfunc webViewFullscreenMayReturnToInline.*?\n\t\t}', source, re.S
)
assert callback, "Astra must handle WebKit's native return-to-inline callback"
restore = re.search(r'\tfunc returnToPictureInPictureSource\(\).*?\n\t}', source, re.S).group()

with tempfile.TemporaryDirectory(prefix="astra-pip-return-") as directory:
    swift = Path(directory) / "main.swift"
    executable = Path(directory) / "check"
    swift.write_text('''import WebKit

@MainActor
final class Controller: NSObject, WKUIDelegate {
    let webView = WKWebView()
    var isPictureInPictureActive = false
    var isEnteringPictureInPicture = false
    var pictureInPictureRestoreRequested: (() -> Void)?

    func owns(_ candidate: WKWebView) -> Bool {
        candidate === webView
    }
''' + callback.group() + "\n" + restore + '''
}

MainActor.assumeIsolated {
    let controller = Controller()
    var restores = 0
    controller.pictureInPictureRestoreRequested = { restores += 1 }
    let selector = NSSelectorFromString("_webViewFullscreenMayReturnToInline:")
    precondition(controller.responds(to: selector))
    controller.perform(selector, with: controller.webView)
    precondition(restores == 0, "Ordinary fullscreen must not restore a PiP source")
    controller.isPictureInPictureActive = true
    controller.perform(selector, with: WKWebView())
    precondition(restores == 0, "A stale view must not restore the source")
    controller.perform(selector, with: controller.webView)
    precondition(restores == 1, "Native PiP return must restore its source")
    controller.isPictureInPictureActive = false
    controller.isEnteringPictureInPicture = true
    controller.perform(selector, with: controller.webView)
    precondition(restores == 2, "A return during entry must restore its source")
    print("Picture in Picture native return check passed")
}
''')
    subprocess.run(["swiftc", str(swift), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
