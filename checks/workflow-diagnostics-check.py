"""Regression guards for cross-workflow performance instrumentation."""
from pathlib import Path
import subprocess
import sys

browser = Path("astra/Models/Core/Browser.swift").read_text()
registry = Path("astra/Models/Core/BrowserWindowRegistry.swift").read_text()
content = Path("astra/UI/Content/BrowserContentView.swift").read_text()
tool = Path("scripts/astra_workflow_report.py")
for stage, code in (
    ("workflow.tab.create-to-model-commit", browser),
    ("workflow.tabs.close-to-model-commit", browser),
    ("tab.select.end", browser),
    ("workflow.windows.shared-state-fanout", registry),
    ("workflow.webview-hosts.resolve", content),
):
    assert stage in code, stage
    assert "BrowserLog.duration(.performance" in code or '"tab.select.end"' == stage
assert "warnAboveMilliseconds: 8" in content
assert "warnAboveMilliseconds: 16" in browser
proc = subprocess.run([sys.executable, str(tool), "--self-test"], check=True, text=True, capture_output=True)
assert "passed" in proc.stdout
print("Workflow instrumentation and timing-report parser checks passed")
