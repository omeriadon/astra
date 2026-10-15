#!/usr/bin/env python3
"""Small self-check for the streaming render trace analyzer."""

import importlib.util
import json
import sys
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
SOURCE = ROOT / "scripts" / "analyze_render_trace.py"
spec = importlib.util.spec_from_file_location("render_trace", SOURCE)
module = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(module)


def fixture() -> Path:
    xml = """<?xml version="1.0"?><trace-query-result><node><schema name="ProcessCPUUsage"/>
    <row><start-time id="1">1000000000</start-time><duration id="2">500000000</duration><system-cpu-percent id="3">20</system-cpu-percent></row>
    <row><start-time ref="1"/><duration ref="2"/><system-cpu-percent ref="3"/></row></node></trace-query-result>"""
    handle = tempfile.NamedTemporaryFile(suffix=".zip", delete=False)
    handle.close()
    with zipfile.ZipFile(handle.name, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("exported-tables/ProcessCPUUsage.xml", xml)
        archive.writestr("exported-tables/time-profile.xml", """<?xml version="1.0"?><trace-query-result><node><schema><col><mnemonic>time</mnemonic></col><col><mnemonic>weight</mnemonic></col><col><mnemonic>stack</mnemonic></col></schema><row><sample-time>1000000000</sample-time><weight>100000000</weight><tagged-backtrace id="9"><frame name="leaf"><binary id="10" name="Demo"/></frame><frame name="parent"><binary ref="10"/></frame></tagged-backtrace></row></node></trace-query-result>""")
    return Path(handle.name)


path = fixture()
try:
    report = module.analyze(path)
    table = report["tables"]["ProcessCPUUsage"]
    assert table["rows"] == 2
    assert table["cpu_samples"] == 2
    assert abs(table["cpu_seconds"] - 0.2) < 1e-12
    assert table["covered_window"]["duration_seconds"] == 0.5
    profile = report["tables"]["time-profile"]
    assert profile["leaf_symbols"][0] == {"key": "leaf", "count": 0.1}
    assert profile["binaries"][0] == {"key": "Demo", "count": 0.1}
    assert sum(entry["count"] for entry in profile["leaf_symbols"]) == 0.1
    assert all(entry["count"] <= 0.1 for entry in profile["inclusive_symbols"])
    try:
        module.scalar(module.ET.fromstring('<duration ref="missing"/>'), {})
    except ValueError:
        pass
    else:
        raise AssertionError("Unresolved references must not silently lose measurements")
    print(json.dumps({"ok": True, "checks": ["id/ref resolution", "nanosecond units", "covered window", "stack attribution", "unresolved reference rejection"]}))
finally:
    path.unlink(missing_ok=True)
