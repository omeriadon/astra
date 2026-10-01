"""Fail closed on missing desktop distribution capabilities. Uses only stdlib."""

import argparse
import base64
import plistlib
import subprocess
from pathlib import Path


def validate_signature(details, team):
    if not any(line.startswith("Authority=Developer ID Application:") for line in details.splitlines()):
        raise ValueError("Application must have a Developer ID Application signature")
    if f"TeamIdentifier={team}" not in details.splitlines():
        raise ValueError("Application signature belongs to a different team")
    if "(runtime)" not in details or "Timestamp=" not in details:
        raise ValueError("Distribution requires Hardened Runtime and a secure timestamp")


def validate(info, entitlements):
    required = (
        "com.apple.security.app-sandbox",
        "com.apple.security.network.client",
        "com.apple.security.files.downloads.read-write",
        "com.apple.security.device.camera",
        "com.apple.security.device.audio-input",
        "com.apple.security.personal-information.location",
        "com.apple.security.files.bookmarks.app-scope",
    )
    for key in required:
        if entitlements.get(key) is not True:
            raise ValueError(f"Required signed entitlement is missing: {key}")
    if entitlements.get("com.apple.security.get-task-allow"):
        raise ValueError("Distribution must not permit debugger attachment")
    if "Default" not in entitlements.get("com.apple.developer.applesignin", []):
        raise ValueError("Sign in with Apple entitlement is missing")
    bundle_id = info["CFBundleIdentifier"]
    services = entitlements.get(
        "com.apple.security.temporary-exception.mach-lookup.global-name", []
    )
    for suffix in ("-spks", "-spki"):
        if bundle_id + suffix not in services:
            raise ValueError(f"Sparkle installer service entitlement is missing: {suffix}")
    if info.get("SUEnableInstallerLauncherService") is not True:
        raise ValueError("Sparkle sandbox installer service is disabled")
    if len(base64.b64decode(info.get("SUPublicEDKey", ""), validate=True)) != 32:
        raise ValueError("Sparkle Ed25519 public key must contain 32 bytes")
    if not info.get("SUFeedURL", "").startswith("https://"):
        raise ValueError("Sparkle feed must use HTTPS")
    ats = info.get("NSAppTransportSecurity", {})
    if ats.get("NSAllowsArbitraryLoads"):
        raise ValueError("Native networking must not have a global ATS exception")
    if ats.get("NSAllowsArbitraryLoadsInWebContent") is not True:
        raise ValueError("Browser web-content ATS policy is missing")
    if info.get("LSFileQuarantineEnabled") is not True:
        raise ValueError("Download quarantine is disabled")


def check():
    signature = "Authority=Developer ID Application: Astra\nTeamIdentifier=EXAMPLE\nflags=0x10000(runtime)\nTimestamp=example"
    validate_signature(signature, "EXAMPLE")
    for invalid in (
        signature.replace("Developer ID Application:", "Apple Development:"),
        signature.replace("TeamIdentifier=EXAMPLE", "TeamIdentifier=OTHER"),
        signature.replace("(runtime)", ""),
        signature.replace("Timestamp=", "Signed Time="),
    ):
        try:
            validate_signature(invalid, "EXAMPLE")
        except ValueError:
            continue
        raise AssertionError("Accepted invalid distribution signature")
    info = {
        "CFBundleIdentifier": "example.astra",
        "SUEnableInstallerLauncherService": True,
        "SUPublicEDKey": base64.b64encode(bytes(32)).decode(),
        "SUFeedURL": "https://example.com/appcast.xml",
        "NSAppTransportSecurity": {"NSAllowsArbitraryLoadsInWebContent": True},
        "LSFileQuarantineEnabled": True,
    }
    entitlements = dict.fromkeys((
        "com.apple.security.app-sandbox",
        "com.apple.security.network.client",
        "com.apple.security.files.downloads.read-write",
        "com.apple.security.device.camera",
        "com.apple.security.device.audio-input",
        "com.apple.security.personal-information.location",
        "com.apple.security.files.bookmarks.app-scope",
    ), True)
    entitlements["com.apple.developer.applesignin"] = ["Default"]
    entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] = [
        "example.astra-spks", "example.astra-spki"
    ]
    validate(info, entitlements)
    for key in tuple(entitlements):
        incomplete = dict(entitlements)
        del incomplete[key]
        try:
            validate(info, incomplete)
        except ValueError:
            continue
        raise AssertionError(f"Accepted missing entitlement: {key}")
    for bad_info, bad_entitlements in (
        ({**info, "LSFileQuarantineEnabled": False}, entitlements),
        ({**info, "SUPublicEDKey": ""}, entitlements),
        ({**info, "SUFeedURL": "http://example.com"}, entitlements),
        ({**info, "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True}}, entitlements),
        (info, {**entitlements, "com.apple.security.get-task-allow": True}),
    ):
        try:
            validate(bad_info, bad_entitlements)
        except ValueError:
            continue
        raise AssertionError("Accepted unsafe distribution settings")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--team-id")
    args = parser.parse_args()
    if args.self_test:
        check()
    elif args.app:
        if not args.team_id:
            parser.error("--team-id is required when checking an app")
        signature = subprocess.run(
            ["codesign", "--display", "--verbose=4", str(args.app)],
            check=True, capture_output=True,
        )
        validate_signature(signature.stderr.decode(), args.team_id)
        info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
        result = subprocess.run(
            ["codesign", "--display", "--entitlements", ":-", str(args.app)],
            check=True, capture_output=True,
        )
        validate(info, plistlib.loads(result.stdout))
    else:
        parser.error("Provide an app or --self-test")
