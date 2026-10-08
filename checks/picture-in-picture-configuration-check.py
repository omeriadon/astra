"""Run with python3 checks/picture-in-picture-configuration-check.py on macOS."""

from pathlib import Path
import re
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source = (root / "astra/Web/Navigation/BrowserController.swift").read_text()
configuration = re.search(
    r"configuration\.allowsAirPlayForMediaPlayback = true(.*?)"
    r"if let suffix = Self\.safariUserAgentSuffix", source, re.S
).group(1)
configuration = re.sub(r"^.*AstraConfigureWebPushPreferences.*\n", "", configuration, flags=re.M)

with tempfile.TemporaryDirectory(prefix="astra-pip-check-") as directory:
    swift = Path(directory) / "main.swift"
    executable = Path(directory) / "check"
    swift.write_text(
        "import WebKit\n"
        "let configuration = WKWebViewConfiguration()\n"
        + configuration
        + '\nprecondition(configuration.preferences.value(forKey: "_allowsPictureInPictureMediaPlayback") as? Bool == true, '
        + '"macOS WebKit must enable native Picture in Picture playback")\n'
        + 'print("Picture in Picture configuration check passed")\n'
    )
    subprocess.run(["swiftc", str(swift), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
