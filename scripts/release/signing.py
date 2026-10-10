#!/usr/bin/env python3

from __future__ import annotations

import base64
import datetime as dt
import os
import plistlib
import secrets
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

PROFILE_CACHE = Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"


def required(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"required release secret {name} is missing")
    return value


def run(command: list[str], *, input_text: str | None = None) -> str:
    result = subprocess.run(command, input=input_text, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"command failed ({command[0]}): {detail}")
    return result.stdout.strip()


def decode_secret(name: str, destination: Path) -> None:
    try:
        data = base64.b64decode(required(name), validate=True)
    except Exception as error:
        raise RuntimeError(f"{name} is not valid base64: {error}") from error
    if not data:
        raise RuntimeError(f"{name} decoded to an empty file")
    destination.write_bytes(data)
    destination.chmod(0o600)


def runner_root() -> Path:
    root = Path(required("RUNNER_TEMP")) / "astra-release-credentials"
    resolved = root.resolve()
    expected_parent = Path(required("RUNNER_TEMP")).resolve()
    if expected_parent not in resolved.parents:
        raise RuntimeError("credential workspace escaped RUNNER_TEMP")
    return resolved


def github_env() -> Path:
    return Path(required("GITHUB_ENV"))


def export_environment(values: dict[str, str]) -> None:
    with github_env().open("a", encoding="utf-8") as stream:
        for name, value in values.items():
            if "\n" in value or "\r" in value:
                raise RuntimeError(f"refusing multiline environment value for {name}")
            stream.write(f"{name}={value}\n")


def current_keychain_search_list() -> list[str]:
    output = run(["security", "list-keychains", "-d", "user"])
    try:
        return shlex.split(output)
    except ValueError as error:
        raise RuntimeError(f"could not parse user keychain search list: {error}") from error


def set_keychain_search_list(paths: list[str]) -> None:
    if not paths:
        raise RuntimeError("refusing to replace the user keychain search list with an empty list")
    run(["security", "list-keychains", "-d", "user", "-s", *paths])


def install_provisioning_profile(profile: Path, profile_payload: dict, root: Path) -> None:
    profile_uuid = profile_payload.get("UUID")
    if not isinstance(profile_uuid, str) or not profile_uuid:
        raise RuntimeError("distribution provisioning profile has no UUID")
    if any(character not in "0123456789abcdefABCDEF-" for character in profile_uuid):
        raise RuntimeError("distribution provisioning profile UUID contains unexpected characters")

    PROFILE_CACHE.mkdir(parents=True, exist_ok=True)
    destination = PROFILE_CACHE / f"{profile_uuid}.provisionprofile"
    source_bytes = profile.read_bytes()

    if destination.exists():
        if destination.read_bytes() != source_bytes:
            raise RuntimeError(f"a different provisioning profile already exists at {destination}")
        return

    destination.write_bytes(source_bytes)
    destination.chmod(0o600)
    (root / "installed-profile-path.txt").write_text(str(destination), encoding="utf-8")


def prepare() -> None:
    root = runner_root()
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(mode=0o700, parents=True)

    certificate = root / "developer-id.p12"
    profile = root / "developer-id.provisionprofile"
    notary_key = root / "AuthKey.p8"
    export_options = root / "ExportOptions.plist"
    keychain = root / "release.keychain-db"
    keychain_state = root / "keychain-search-list.txt"

    previous_keychains = current_keychain_search_list()
    if not previous_keychains:
        raise RuntimeError("user keychain search list is unexpectedly empty")
    keychain_state.write_text("\n".join(previous_keychains) + "\n", encoding="utf-8")

    decode_secret("DEVELOPER_ID_CERTIFICATE_BASE64", certificate)
    decode_secret("DEVELOPER_ID_PROFILE_BASE64", profile)
    decode_secret("APPLE_NOTARY_KEY_BASE64", notary_key)

    certificate_password = required("DEVELOPER_ID_CERTIFICATE_PASSWORD")
    team_id = required("APPLE_TEAM_ID")
    key_id = required("APPLE_NOTARY_KEY_ID")
    issuer_id = required("APPLE_NOTARY_ISSUER_ID")
    if len(team_id) != 10 or not team_id.isalnum() or team_id.upper() != team_id:
        raise RuntimeError("APPLE_TEAM_ID must be a 10-character uppercase team identifier")

    keychain_password = secrets.token_urlsafe(32)
    run(["security", "create-keychain", "-p", keychain_password, str(keychain)])
    run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)])
    run(["security", "unlock-keychain", "-p", keychain_password, str(keychain)])
    set_keychain_search_list([str(keychain), *[path for path in previous_keychains if path != str(keychain)]])
    run([
        "security", "import", str(certificate), "-k", str(keychain),
        "-P", certificate_password, "-T", "/usr/bin/codesign", "-T", "/usr/bin/security",
    ])
    run([
        "security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
        "-s", "-k", keychain_password, str(keychain),
    ])

    identities = run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)])
    identity_lines = [line.strip() for line in identities.splitlines() if "Developer ID Application:" in line]
    if len(identity_lines) != 1:
        raise RuntimeError(f"expected exactly one Developer ID Application identity, found {len(identity_lines)}")
    quoted = identity_lines[0].split('"', 2)
    if len(quoted) < 2:
        raise RuntimeError("could not parse Developer ID Application identity")
    signing_identity = quoted[1]
    if f"({team_id})" not in signing_identity:
        raise RuntimeError("Developer ID certificate team does not match APPLE_TEAM_ID")

    profile_xml = run(["security", "cms", "-D", "-i", str(profile)])
    profile_payload = plistlib.loads(profile_xml.encode())
    profile_name = profile_payload.get("Name")
    profile_team_ids = profile_payload.get("TeamIdentifier") or []
    expiration = profile_payload.get("ExpirationDate")
    if not isinstance(profile_name, str) or not profile_name:
        raise RuntimeError("distribution provisioning profile has no Name")
    if team_id not in profile_team_ids:
        raise RuntimeError("distribution provisioning profile team does not match APPLE_TEAM_ID")
    if not isinstance(expiration, dt.datetime):
        raise RuntimeError("distribution provisioning profile has no valid expiration date")
    now = dt.datetime.now(expiration.tzinfo) if expiration.tzinfo else dt.datetime.now()
    if expiration <= now:
        raise RuntimeError("distribution provisioning profile is expired")

    install_provisioning_profile(profile, profile_payload, root)

    export_payload = {
        "method": "developer-id",
        "signingStyle": "manual",
        "teamID": team_id,
        "signingCertificate": signing_identity,
        "provisioningProfiles": {"com.omeriadon.astra": profile_name},
    }
    with export_options.open("wb") as stream:
        plistlib.dump(export_payload, stream, sort_keys=True)
    export_options.chmod(0o600)

    run([
        "xcrun", "notarytool", "store-credentials", "astra-release",
        "--key", str(notary_key), "--key-id", key_id, "--issuer", issuer_id,
        "--keychain", str(keychain),
    ])

    certificate.unlink(missing_ok=True)
    profile.unlink(missing_ok=True)
    notary_key.unlink(missing_ok=True)

    export_environment({
        "SIGNING_KEYCHAIN": str(keychain),
        "SIGNING_IDENTITY": signing_identity,
        "SIGNING_PROFILE": profile_name,
        "EXPORT_OPTIONS": str(export_options),
    })
    print("temporary distribution credentials prepared")


def cleanup() -> None:
    root = runner_root()
    keychain = root / "release.keychain-db"
    keychain_state = root / "keychain-search-list.txt"
    installed_profile_marker = root / "installed-profile-path.txt"

    if keychain_state.is_file():
        previous_keychains = [
            line.strip()
            for line in keychain_state.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        if previous_keychains:
            subprocess.run(
                ["security", "list-keychains", "-d", "user", "-s", *previous_keychains],
                check=False,
                capture_output=True,
            )

    if keychain.exists():
        subprocess.run(["security", "delete-keychain", str(keychain)], check=False, capture_output=True)

    if installed_profile_marker.is_file():
        installed_profile = Path(installed_profile_marker.read_text(encoding="utf-8").strip()).resolve()
        profile_cache = PROFILE_CACHE.resolve()
        if profile_cache in installed_profile.parents and installed_profile.suffix == ".provisionprofile":
            installed_profile.unlink(missing_ok=True)

    if root.exists():
        shutil.rmtree(root)
    print("temporary distribution credentials removed")


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"prepare", "cleanup"}:
        print("usage: signing.py prepare|cleanup", file=sys.stderr)
        return 2
    try:
        if sys.argv[1] == "prepare":
            prepare()
        else:
            cleanup()
    except Exception as error:
        print(f"release credential setup failed: {error}", file=sys.stderr)
        if sys.argv[1] == "prepare":
            try:
                cleanup()
            except Exception:
                pass
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
