#!/usr/bin/env python3
"""Prevent GitHub Actions toolchain and superseded-run cancellation regressions."""

from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
workflows = sorted((root / ".github/workflows").glob("*.yml"))
errors = []
if not workflows:
    errors.append("No GitHub Actions workflows found")

# These two workflows intentionally do not cancel superseded runs.
CANCELLATION_EXCEPTIONS = {
    "browser-use-sdk-policy.yml",
    "publish-release.yml",
}


def workflow_concurrency(source: str) -> dict[str, str]:
    """Read workflow-level concurrency; ignore job-local settings."""
    lines = source.splitlines()
    if "concurrency:" not in lines:
        return {}
    start = lines.index("concurrency:") + 1
    result = {}
    for line in lines[start:]:
        if line and not line[0].isspace():
            break
        if line.startswith("  ") and not line.startswith("    ") and ":" in line:
            key, value = line.strip().split(":", 1)
            result[key] = value.strip()
    return result


def workflow_job_blocks(source: str) -> list[tuple[str, str]]:
    """Separate jobs so Ubuntu checks do not inherit unrelated macOS steps."""
    if "\njobs:\n" in source:
        jobs_source = source.split("\njobs:\n", 1)[1]
    elif source.startswith("jobs:\n"):
        jobs_source = source[len("jobs:\n"):]
    else:
        return []
    markers = list(re.finditer(r"(?m)^  ([\w-]+):\s*$", jobs_source))
    return [
        (marker.group(1), jobs_source[marker.end():markers[i + 1].start() if i + 1 < len(markers) else None])
        for i, marker in enumerate(markers)
    ]


def python_check_requires_xcrun(path: str) -> bool:
    """Detect scripts that actually invoke xcrun, not just mention it in a comment."""
    candidate = (root / path).resolve()
    if not candidate.is_relative_to(root) or not candidate.is_file():
        return False
    source = candidate.read_text(encoding="utf-8")
    return bool(re.search(
        r"""subprocess\.(?:run|call|check_call|check_output|Popen)\s*\(\s*\[\s*['"]xcrun['"]""",
        source,
    ))


macos_jobs = 0
cancellable_workflows = 0
seen_groups = {}
for workflow in workflows:
    text = workflow.read_text(encoding="utf-8")
    if workflow.name not in CANCELLATION_EXCEPTIONS:
        concurrency = workflow_concurrency(text)
        group = concurrency.get("group", "")
        if concurrency.get("cancel-in-progress") != "true":
            errors.append(f"{workflow.name}: newer commits must cancel superseded workflow runs")
        if not ("github.ref" in group or "github.event.pull_request.number" in group):
            errors.append(f"{workflow.name}: concurrency group must distinguish PRs/branches")
        if not group:
            errors.append(f"{workflow.name}: missing workflow-level concurrency group")
        elif "github.workflow" not in group:
            # Distinct static prefixes must not cancel a different workflow.
            previous = seen_groups.setdefault(group, workflow.name)
            if previous != workflow.name:
                errors.append(f"{workflow.name}: concurrency group also used by {previous}")
        if concurrency.get("cancel-in-progress") == "true" and group:
            cancellable_workflows += 1

    # Python checks that compile fixtures using Apple's xcrun must not run
    # on Ubuntu, even when the rest of the workflow is platform-neutral.
    for job_name, body in workflow_job_blocks(text):
        runner_match = re.search(r"(?m)^    runs-on:\s*([^#\n]+)", body)
        if not runner_match or runner_match.group(1).strip().strip("'\"") != "ubuntu-latest":
            continue
        if re.search(r"(?m)^\s+(?:xcrun|xcodebuild|codesign)\b", body):
            errors.append(f"{workflow.name}/{job_name}: Apple tooling cannot run on Ubuntu")
        for script_match in re.finditer(r"(?m)^\s+python3\s+([\w./-]+\.py)\b", body):
            script_path = script_match.group(1)
            if python_check_requires_xcrun(script_path):
                errors.append(
                    f"{workflow.name}/{job_name}: {script_path} invokes xcrun; use xcode-27"
                )

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

print(
    f"Verified {len(workflows)} workflows, {cancellable_workflows} cancelling superseded "
    f"runs, {len(CANCELLATION_EXCEPTIONS)} exclusions, and "
    f"{macos_jobs} Xcode 27 jobs (Swift 6.4 compiler)."
)
