#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import plistlib
import re
import subprocess
import sys
from pathlib import Path

EXPECTED_BUNDLE_ID = "com.omeriadon.astra"
EXPECTED_FEED = "https://github.com/omeriadon/astra/releases/latest/download/appcast.xml"
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+(?:\.[0-9]+)?$")
BUILD_RE = re.compile(r"^[0-9]+$")
REQUIRED_TRUE_ENTITLEMENTS = {
    "com.apple.security.app-sandbox",
    "com.apple.security.network.client",
    "com.apple.security.files.downloads.read-write",
    "com.apple.security.files.user-selected.read-write",
    "com.apple.security.files.bookmarks.app-scope",
    "com.apple.security.device.camera",
    "com.apple.security.device.audio-input",
    "com.apple.security.personal-information.location",
}


class ValidationError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise ValidationError(message)


def validate_info(info: dict) -> None:
    bundle_id = info.get("CFBundleIdentifier")
    if bundle_id != EXPECTED_BUNDLE_ID:
        fail(f"unexpected bundle identifier: {bundle_id!r}")

    version = str(info.get("CFBundleShortVersionString", ""))
    build = str(info.get("CFBundleVersion", ""))
    if not VERSION_RE.fullmatch(version):
        fail(f"invalid marketing version: {version!r}")
    if not BUILD_RE.fullmatch(build):
        fail(f"invalid build number: {build!r}")

    if info.get("LSFileQuarantineEnabled") is not True:
        fail("download quarantine must remain enabled")

    ats = info.get("NSAppTransportSecurity")
    if not isinstance(ats, dict) or ats.get("NSAllowsArbitraryLoadsInWebContent") is not True:
        fail("web-content ATS exception is missing")
    if ats.get("NSAllowsArbitraryLoads") is True:
        fail("global native ATS bypass is forbidden")

    feed = info.get("SUFeedURL")
    if feed != EXPECTED_FEED:
        fail(f"unexpected Sparkle feed URL: {feed!r}")

    public_key = info.get("SUPublicEDKey")
    if not isinstance(public_key, str):
        fail("Sparkle public key is missing")
    try:
        decoded = base64.b64decode(public_key, validate=True)
    except Exception as error:
        fail(f"Sparkle public key is not valid base64: {error}")
    if len(decoded) != 32:
        fail(f"Sparkle Ed25519 public key must decode to 32 bytes, got {len(decoded)}")

    if info.get("SUEnableInstallerLauncherService") is not True:
        fail("Sparkle installer launcher service must be enabled for the sandboxed distribution path")
    if info.get("SUEnableDownloaderService") is True:
        fail("Sparkle downloader XPC service must stay disabled while Astra has network-client entitlement")


def validate_entitlements(entitlements: dict) -> None:
    missing = sorted(key for key in REQUIRED_TRUE_ENTITLEMENTS if entitlements.get(key) is not True)
    if missing:
        fail("signed artifact is missing required entitlements: " + ", ".join(missing))
    if entitlements.get("com.apple.security.get-task-allow") is True:
        fail("distribution artifact contains debugger entitlement com.apple.security.get-task-allow")

    apple_sign_in = entitlements.get("com.apple.developer.applesignin")
    if not isinstance(apple_sign_in, list) or "Default" not in apple_sign_in:
        fail("signed artifact is missing the selected Sign in with Apple entitlement")

    mach_names = entitlements.get("com.apple.security.temporary-exception.mach-lookup.global-name")
    required_names = {f"{EXPECTED_BUNDLE_ID}-spks", f"{EXPECTED_BUNDLE_ID}-spki"}
    if not isinstance(mach_names, list) or not required_names.issubset(set(mach_names)):
        fail("signed artifact is missing Sparkle installer mach-lookup exceptions")


def run(command: list[str]) -> str:
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        fail(f"command failed ({' '.join(command)}): {detail}")
    return (result.stdout + result.stderr).strip()


def plist_from_codesign(output: str) -> dict:
    start = output.find("<?xml")
    end = output.rfind("</plist>")
    if start < 0 or end < 0:
        fail("codesign did not return an entitlements plist")
    payload = output[start : end + len("</plist>")].encode()
    try:
        value = plistlib.loads(payload)
    except Exception as error:
        fail(f"could not decode signed entitlements: {error}")
    if not isinstance(value, dict):
        fail("signed entitlements are not a dictionary")
    return value


def validate_signature(app: Path, expected_team_id: str) -> None:
    run(["codesign", "--deep", "--strict", "--verify", str(app)])
    details = run(["codesign", "-d", "--verbose=4", str(app)])
    if "Signature=adhoc" in details:
        fail("artifact is ad-hoc signed")
    if "runtime" not in details:
        fail("artifact is missing Hardened Runtime")
    if not re.search(r"^Timestamp=.+$", details, flags=re.MULTILINE):
        fail("artifact is missing a secure signing timestamp")

    match = re.search(r"^TeamIdentifier=(.+)$", details, flags=re.MULTILINE)
    if not match:
        fail("signed artifact has no TeamIdentifier")
    actual_team = match.group(1).strip()
    if actual_team != expected_team_id:
        fail(f"signed artifact team is {actual_team!r}, expected {expected_team_id!r}")

    entitlement_output = run(["codesign", "-d", "--entitlements", ":-", str(app)])
    validate_entitlements(plist_from_codesign(entitlement_output))


def validate_app(app: Path, team_id: str | None) -> None:
    if app.suffix != ".app" or not app.is_dir():
        fail(f"artifact is not an application bundle: {app}")
    info_path = app / "Contents" / "Info.plist"
    executable_dir = app / "Contents" / "MacOS"
    if not info_path.is_file():
        fail("application Info.plist is missing")
    if not executable_dir.is_dir() or not any(path.is_file() for path in executable_dir.iterdir()):
        fail("application executable is missing")
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    validate_info(info)
    if team_id:
        if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
            fail("team ID must be exactly 10 uppercase letters/digits")
        validate_signature(app, team_id)


def self_test() -> None:
    valid_info = {
        "CFBundleIdentifier": EXPECTED_BUNDLE_ID,
        "CFBundleShortVersionString": "0.1.2",
        "CFBundleVersion": "42",
        "LSFileQuarantineEnabled": True,
        "NSAppTransportSecurity": {"NSAllowsArbitraryLoadsInWebContent": True},
        "SUFeedURL": EXPECTED_FEED,
        "SUPublicEDKey": base64.b64encode(bytes(range(32))).decode(),
        "SUEnableInstallerLauncherService": True,
    }
    validate_info(valid_info)

    invalid_info_cases = [
        {**valid_info, "CFBundleIdentifier": "example.invalid"},
        {**valid_info, "CFBundleShortVersionString": "0.1-beta"},
        {**valid_info, "CFBundleVersion": "4.2"},
        {**valid_info, "LSFileQuarantineEnabled": False},
        {**valid_info, "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True, "NSAllowsArbitraryLoadsInWebContent": True}},
        {**valid_info, "SUFeedURL": "http://example.invalid/appcast.xml"},
        {**valid_info, "SUPublicEDKey": base64.b64encode(b"short").decode()},
        {**valid_info, "SUEnableInstallerLauncherService": False},
        {**valid_info, "SUEnableDownloaderService": True},
    ]
    for case in invalid_info_cases:
        try:
            validate_info(case)
        except ValidationError:
            continue
        raise AssertionError(f"invalid Info.plist fixture passed validation: {case}")

    valid_entitlements = {key: True for key in REQUIRED_TRUE_ENTITLEMENTS}
    valid_entitlements["com.apple.developer.applesignin"] = ["Default"]
    valid_entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] = [
        f"{EXPECTED_BUNDLE_ID}-spks",
        f"{EXPECTED_BUNDLE_ID}-spki",
    ]
    validate_entitlements(valid_entitlements)
    for mutation in (
        {"com.apple.security.app-sandbox": False},
        {"com.apple.security.get-task-allow": True},
        {"com.apple.developer.applesignin": []},
        {"com.apple.security.temporary-exception.mach-lookup.global-name": []},
    ):
        case = dict(valid_entitlements)
        case.update(mutation)
        try:
            validate_entitlements(case)
        except ValidationError:
            continue
        raise AssertionError(f"invalid entitlement fixture passed validation: {mutation}")

    print("release validation self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail-closed Astra release artifact validation")
    parser.add_argument("app", nargs="?", type=Path)
    parser.add_argument("--team-id")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    try:
        if arguments.self_test:
            self_test()
            return 0
        if arguments.app is None:
            parser.error("an .app path is required unless --self-test is used")
        validate_app(arguments.app.resolve(), arguments.team_id)
    except ValidationError as error:
        print(f"release validation failed: {error}", file=sys.stderr)
        return 1
    print("release artifact validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
