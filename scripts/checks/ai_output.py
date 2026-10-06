#!/usr/bin/env python3
"""Run the actual Swift AI output parser against fenced and partial responses."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / "astra/AI/Features/BrowserPageFeatures.swift").read_text()
helper = source[source.index("nonisolated enum BrowserAIOutput {"):]
checks = r'''
let surrounded = "Here are the sections:\n```json\n[{\"name\":\"Research\",\"tabIDs\":[\"id\"]}]\n```"
let value = try JSONSerialization.jsonObject(with: BrowserAIOutput.jsonData(surrounded)) as! [[String: Any]]
assert(value.count == 1 && value[0]["name"] as? String == "Research")
let nested = "{\"response\":\"Braces { in text }\",\"actions\":[{\"name\":\"rename_tab\",\"arguments\":{\"name\":\"A\"}}]}"
let nestedValue = try JSONSerialization.jsonObject(with: BrowserAIOutput.jsonData(nested)) as! [String: Any]
assert(nestedValue["response"] as? String == "Braces { in text }")
let partial = "[{\"name\":\"Ready\",\"tabIDs\":[\"one\"]},{\"name\":\"Incomplete"
assert(BrowserAIOutput.completedObjects(in: partial).count == 1)
assert(BrowserAIOutput.completedObjects(in: "[{\"name\":\"No close\"").isEmpty)
assert(BrowserAIOutput.streamedString("response", in: "{\"response\":\"Hello\\nworld") == "Hello\nworld")
assert(BrowserAIOutput.streamedString("response", in: "{\"response\":\"Trailing\\") == "Trailing")
assert(BrowserAIOutput.streamedString("header", in: "{\"title\":\"One\",\"header\":\"Two\"}") == "Two")
assert(BrowserAIOutput.streamedString("response", in: "{\"actions\":[]}") == nil)
print("AI output parser checks passed")
'''
with tempfile.TemporaryDirectory() as temporary:
    script = Path(temporary) / "check.swift"
    script.write_text("import Foundation\n" + helper + checks)
    subprocess.run(["swift", str(script)], check=True)
