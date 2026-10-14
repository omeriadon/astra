#!/usr/bin/env python3
"""Report unsigned/signed macOS .app sizes and optional DMG sizes in bytes.

Uses logical file lengths (not allocated disk blocks). Symlink targets are never
followed or counted twice, including versioned macOS frameworks.
"""
from __future__ import annotations

import argparse
import json
import os
import plistlib
import tempfile
from pathlib import Path


CATEGORIES = (
    ("app_bytes", "Total .app bundle"),
    ("executable_bytes", "Main executable"),
    ("frameworks_bytes", "Embedded frameworks and libraries"),
    ("resources_bytes", "Resources and assets"),
    ("dmg_bytes", "Compressed DMG"),
)


def tree_bytes(root: Path) -> int:
    """Sum the logical lengths of regular files without following symlinks."""
    if not root.is_dir() or root.is_symlink():
        return 0
    total = 0
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [name for name in dirs if not (Path(directory) / name).is_symlink()]
        for name in files:
            file = Path(directory) / name
            if not file.is_symlink() and file.is_file():
                total += file.stat().st_size
    return total


def entries(root: Path, app: Path) -> dict[str, int]:
    """Size every immediate child to attribute framework and asset growth."""
    if not root.is_dir() or root.is_symlink():
        return {}
    result = {}
    for item in root.iterdir():
        if item.is_symlink():
            continue
        size = tree_bytes(item) if item.is_dir() else item.stat().st_size if item.is_file() else 0
        result[item.relative_to(app).as_posix()] = size
    return dict(sorted(result.items()))


def measure(app: Path, dmg: Path | None = None) -> dict:
    if not app.is_dir() or app.is_symlink() or app.suffix != ".app":
        raise ValueError(f"Missing macOS .app bundle: {app}")
    info_path = app / "Contents" / "Info.plist"
    with info_path.open("rb") as source:
        info = plistlib.load(source)
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name or "/" in executable_name:
        raise ValueError("CFBundleExecutable must be a filename in Contents/MacOS")
    executable = app / "Contents" / "MacOS" / executable_name
    if not executable.is_file() or executable.is_symlink():
        raise ValueError(f"Main executable not found: {executable}")
    if dmg is not None and (not dmg.is_file() or dmg.is_symlink()):
        raise ValueError(f"DMG does not exist: {dmg}")

    frameworks = app / "Contents" / "Frameworks"
    resources = app / "Contents" / "Resources"
    return {
        "app_bytes": tree_bytes(app),
        "executable_bytes": executable.stat().st_size,
        "frameworks_bytes": tree_bytes(frameworks),
        "resources_bytes": tree_bytes(resources),
        "dmg_bytes": dmg.stat().st_size if dmg is not None else None,
        "framework_items": entries(frameworks, app),
        "resource_items": entries(resources, app),
    }


def difference(before: int | None, after: int | None) -> dict | None:
    if before is None or after is None:
        return None
    return {
        "bytes": after - before,
        "percent": round((after - before) * 100 / before, 2) if before else None,
    }


def entry_differences(base: dict, candidate: dict) -> list[dict]:
    rows = []
    for path in sorted(base.keys() | candidate.keys()):
        before, after = base.get(path, 0), candidate.get(path, 0)
        if before != after:
            delta = difference(before, after)
            rows.append({
                "path": path,
                "base_bytes": before,
                "candidate_bytes": after,
                "delta_bytes": delta["bytes"],
                "delta_percent": delta["percent"],
            })
    return sorted(rows, key=lambda item: (-abs(item["delta_bytes"]), item["path"]))


def byte_label(amount: int | None) -> str:
    if amount is None:
        return "—"
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    value = float(amount)
    for unit in units:
        if abs(value) < 1024 or unit == units[-1]:
            return f"{value:,.0f} B" if unit == "B" else f"{value:,.2f} {unit}"
        value /= 1024
    raise AssertionError("Unreachable")


def byte_cell(amount: int | None) -> str:
    return "—" if amount is None else f"{amount:,} bytes ({byte_label(amount)})"


def change_cell(delta: dict | None) -> str:
    if delta is None:
        return "—"
    amount = delta["bytes"]
    percent = delta["percent"]
    signed = f"{amount:+,} bytes"
    return f"{signed} ({percent:+.2f}%)" if percent is not None else f"{signed} (new)"


def report(candidate: dict, base: dict | None, candidate_label: str, base_label: str) -> tuple[dict, str]:
    deltas = {
        key: difference(base[key], candidate[key]) if base is not None else None
        for key, _ in CATEGORIES
    }
    changes = {}
    if base is not None:
        changes = {
            "framework_items": entry_differences(base["framework_items"], candidate["framework_items"]),
            "resource_items": entry_differences(base["resource_items"], candidate["resource_items"]),
        }
    result = {
        "schema_version": 1,
        "unit": "logical bytes of regular files (symlinks excluded)",
        "candidate_ref": candidate_label,
        "base_ref": base_label if base is not None else None,
        "candidate": candidate,
        "base": base,
        "delta": deltas,
        "item_changes": changes,
    }
    lines = ["## Astra macOS Release size (informational)", ""]
    if candidate_label:
        lines.append(f"Candidate: {candidate_label}")
    if base is not None:
        lines.append(f"Base: {base_label or 'base branch'}")
    elif base_label:
        lines.append("Base Release archive unavailable; comparison omitted.")
    else:
        lines.append("No base supplied; showing absolute sizes only.")
    lines.extend((
        "",
        "Sizes are uncompressed, logical bytes of regular files; framework symlinks are not double-counted.",
        "Only DMG measurements are compressed. Size changes never fail CI.",
        "",
        "| Component | Base | Candidate | Difference |",
        "|---|---:|---:|---:|",
    ))
    for key, label in CATEGORIES:
        lines.append(
            f"| {label} | {byte_cell(base[key]) if base is not None else '—'} "
            f"| {byte_cell(candidate[key])} | {change_cell(deltas[key])} |"
        )
    for key, label in (("framework_items", "Embedded framework/library sizes"),
                       ("resource_items", "Resource/asset sizes")):
        lines.extend(("", f"### {label}", ""))
        if base is not None:
            changed = changes[key][:20]
            if not changed:
                lines.append("No size differences.")
                continue
            lines.extend((
                "| Path | Base (bytes) | Candidate (bytes) | Change |",
                "|---|---:|---:|---:|",
            ))
            for item in changed:
                delta = {"bytes": item["delta_bytes"], "percent": item["delta_percent"]}
                lines.append(
                    f"| {item['path']} | {item['base_bytes']:,} | "
                    f"{item['candidate_bytes']:,} | {change_cell(delta)} |"
                )
            if len(changes[key]) > 20:
                lines.append(f"\nShowing 20 of {len(changes[key])} changed items; see JSON artifact for all.")
        else:
            items = sorted(candidate[key].items(), key=lambda item: (-item[1], item[0]))
            if not items:
                lines.append("No embedded items.")
                continue
            lines.extend(("| Path | Size |", "|---|---:|"))
            for path, size in items[:20]:
                lines.append(f"| {path} | {byte_cell(size)} |")
            if len(items) > 20:
                lines.append(f"\nShowing 20 of {len(items)} items; see JSON artifact for all.")
    return result, "\n".join(lines) + "\n"


def write_report(args: argparse.Namespace) -> None:
    candidate = measure(args.candidate_app, args.dmg)
    base = measure(args.base_app, args.base_dmg) if args.base_app is not None else None
    result, markdown = report(candidate, base, args.candidate_ref, args.base_ref)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "size-report.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    (args.output_dir / "size-summary.md").write_text(markdown)
    print(markdown)


def self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        apps = []
        for label, binary_size, resource_size, framework_size in (
            ("base", 100, 200, 300), ("head", 125, 180, 450),
        ):
            app = root / label / "astra.app"
            binary = app / "Contents" / "MacOS" / "astra"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"a" * binary_size)
            (app / "Contents" / "Info.plist").write_bytes(
                plistlib.dumps({"CFBundleExecutable": "astra"})
            )
            resources = app / "Contents" / "Resources"
            resources.mkdir()
            (resources / "Assets.car").write_bytes(b"r" * resource_size)
            version = app / "Contents" / "Frameworks" / "Demo.framework" / "Versions" / "A"
            version.mkdir(parents=True)
            (version / "Demo").write_bytes(b"f" * framework_size)
            (version.parent / "Current").symlink_to("A")
            (version.parent.parent / "Demo").symlink_to("Versions/Current/Demo")
            apps.append(app)
        before, after = (measure(app) for app in apps)
        assert before["executable_bytes"] == 100
        assert after["executable_bytes"] == 125
        assert before["frameworks_bytes"] == 300
        assert after["frameworks_bytes"] == 450
        assert before["resources_bytes"] == 200
        assert after["resources_bytes"] == 180
        assert before["app_bytes"] + 25 - 20 + 150 == after["app_bytes"]
        assert difference(100, 125) == {"bytes": 25, "percent": 25.0}
        assert difference(0, 25) == {"bytes": 25, "percent": None}
        assert difference(100, 0) == {"bytes": -100, "percent": -100.0}
        changes = entry_differences(before["resource_items"], after["resource_items"])
        assert changes[0]["delta_bytes"] == -20
        dmg = root / "Astra.dmg"
        dmg.write_bytes(b"d" * 42)
        assert measure(apps[1], dmg)["dmg_bytes"] == 42
        assert measure(apps[0])["dmg_bytes"] is None
        result, markdown = report(after, before, "head", "base")
        assert result["delta"]["app_bytes"]["bytes"] == 155
        assert "+155 bytes" in markdown
        assert "Compressed DMG" in markdown and "—" in markdown
        assert "Contents/Resources/Assets.car" in markdown
        assert report(after, None, "head", "base")[0]["base"] is None
        assert report(after, None, "head", "")[0]["delta"]["app_bytes"] is None
        try:
            measure(root / "not-found.app")
        except ValueError:
            pass
        else:
            raise AssertionError("Accepted missing application")
    print("Release size report self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-app", type=Path)
    parser.add_argument("--base-app", type=Path)
    parser.add_argument("--dmg", type=Path)
    parser.add_argument("--base-dmg", type=Path)
    parser.add_argument("--candidate-ref", default="")
    parser.add_argument("--base-ref", default="")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.candidate_app is None or args.output_dir is None:
        parser.error("--candidate-app and --output-dir are required")
    if args.base_dmg is not None and args.base_app is None:
        parser.error("--base-dmg requires --base-app")
    write_report(args)


if __name__ == "__main__":
    main()
