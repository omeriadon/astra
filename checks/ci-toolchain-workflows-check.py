#!/usr/bin/env python3
"""Prevent GitHub Actions toolchain regressions in Astra's workflows."""

from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
workflows = sorted((root / ".github/workflows").glob("*.yml"))
errors = []
if not workflows:
    errors.append("No GitHub Actions workflows found")

macos_jobs = 0
for workflow in workflows:
    text = workflow.read_text(encoding="utf-8")
    runners = re.findall(r"(?m)^\s+runs-on:\s*([^#\n]+)", text)
    for value in runners:
        runner = value.strip().strip("'\"")
        if runner == "xcode-27":
            macos_jobs += 1
            if "select-xcode-27.sh" not in text:
                errors.append(f"{workflow.name}: Xcode job has no shared toolchain verification")
        elif runner != "ubuntu-latest":
            errors.append(f"{workflow.name}: unapproved runner {runner!r}")
    if re.search(r"\bXcode_26|\bxcode-26|\bSWIFT_VERSION\s*=\s*5|\-swift-version\s+5\b", text, flags=re.I):
        errors.append(f"{workflow.name}: obsolete Xcode / Swift selection")
    if re.search(r"\bxcode-select\s+-s\b", text):
        errors.append(f"{workflow.name}: inline Xcode selection; use shared verifier")
    for line in text.splitlines():
        if line.lstrip().startswith("swiftc ") and "-version" not in line and "-swift-version 6" not in line:
            errors.append(f"{workflow.name}: Swift compile step missing Swift 6 language mode: {line.strip()}")

selector = root / "scripts/ci/select-xcode-27.sh"
if not selector.is_file() or "xcrun swiftc -version" not in selector.read_text(encoding="utf-8"):
    errors.append("Missing central Swift compiler version verification")
if not macos_jobs:
    errors.append("No xcode-27 jobs found")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)

print(f"Verified {len(workflows)} workflows and {macos_jobs} Xcode 27 jobs (Swift 6.4 compiler).")
