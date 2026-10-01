"""Install distribution credentials temporarily; restore the runner on cleanup."""

import base64
import json
import os
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


STATE = Path(os.environ["RUNNER_TEMP"]) / "astra-signing-state.json"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def cleanup():
    if not STATE.exists():
        return
    state = json.loads(STATE.read_text())
    run("security", "list-keychains", "-d", "user", "-s", *state["keychains"])
    keychain = Path(state["directory"]) / "signing.keychain-db"
    if keychain.exists():
        run("security", "delete-keychain", str(keychain))
    Path(state["profile"]).unlink(missing_ok=True)
    shutil.rmtree(state["directory"])
    STATE.unlink()


def prepare():
    if STATE.exists():
        raise ValueError("Previous signing state needs cleanup before preparing credentials")
    required = (
        "DEVELOPER_ID_CERTIFICATE_BASE64", "DEVELOPER_ID_CERTIFICATE_PASSWORD",
        "DEVELOPER_ID_PROFILE_BASE64", "APPLE_TEAM_ID", "APPLE_NOTARY_KEY_BASE64",
        "APPLE_NOTARY_KEY_ID", "APPLE_NOTARY_ISSUER_ID", "SPARKLE_PRIVATE_KEY",
    )
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise ValueError("Missing release secrets: " + ", ".join(missing))
    directory = Path(tempfile.mkdtemp(prefix="astra-signing-", dir=os.environ["RUNNER_TEMP"]))
    profile_directory = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
    profile_directory.mkdir(parents=True, exist_ok=True)
    profile_path = profile_directory / (directory.name + ".provisionprofile")
    keychains = shlex.split(run("security", "list-keychains", "-d", "user").decode())
    STATE.write_text(json.dumps({
        "directory": str(directory), "profile": str(profile_path), "keychains": keychains,
    }))
    STATE.chmod(0o600)
    try:
        for name, destination in (
            ("DEVELOPER_ID_CERTIFICATE_BASE64", "certificate.p12"),
            ("DEVELOPER_ID_PROFILE_BASE64", "profile.provisionprofile"),
            ("APPLE_NOTARY_KEY_BASE64", "notary.p8"),
        ):
            path = directory / destination
            path.write_bytes(base64.b64decode(os.environ[name], validate=True))
            path.chmod(0o600)
        profile = plistlib.loads(run(
            "security", "cms", "-D", "-i", str(directory / "profile.provisionprofile")
        ))
        team = os.environ["APPLE_TEAM_ID"]
        if team not in profile.get("TeamIdentifier", []):
            raise ValueError("Provisioning profile does not belong to APPLE_TEAM_ID")
        application_id = profile["Entitlements"].get("com.apple.application-identifier")
        application_id = application_id or profile["Entitlements"].get("application-identifier", "")
        bundle_id = application_id.partition(".")[2]
        if not bundle_id or "*" in bundle_id:
            raise ValueError("Distribution profile must identify the Astra app explicitly")
        shutil.copyfile(directory / "profile.provisionprofile", profile_path)
        profile_path.chmod(0o600)
        keychain = str(directory / "signing.keychain-db")
        password = secrets.token_urlsafe(32)
        run("security", "create-keychain", "-p", password, keychain)
        run("security", "set-keychain-settings", "-lut", "21600", keychain)
        run("security", "unlock-keychain", "-p", password, keychain)
        run("security", "import", str(directory / "certificate.p12"), "-k", keychain,
            "-P", os.environ["DEVELOPER_ID_CERTIFICATE_PASSWORD"], "-T", "/usr/bin/codesign")
        run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
            "-s", "-k", password, keychain)
        run("security", "list-keychains", "-d", "user", "-s", keychain, *keychains)
        identities = run("security", "find-identity", "-v", "-p", "codesigning", keychain).decode()
        matches = re.findall(r'([A-F0-9]{40}) "Developer ID Application: [^"\n]+\(' + re.escape(team) + r'\)"', identities)
        if len(matches) != 1:
            raise ValueError("Expected one valid Developer ID Application identity for APPLE_TEAM_ID")
        run("xcrun", "notarytool", "store-credentials", "astra-release", "--key",
            str(directory / "notary.p8"), "--key-id", os.environ["APPLE_NOTARY_KEY_ID"],
            "--issuer", os.environ["APPLE_NOTARY_ISSUER_ID"], "--keychain", keychain)
        options = directory / "ExportOptions.plist"
        options.write_bytes(plistlib.dumps({
            "method": "developer-id", "signingStyle": "manual", "teamID": team,
            "signingCertificate": matches[0], "provisioningProfiles": {bundle_id: profile["UUID"]},
        }))
        with Path(os.environ["GITHUB_ENV"]).open("a") as output:
            for key, value in (
                ("SIGNING_KEYCHAIN", keychain), ("SIGNING_IDENTITY", matches[0]),
                ("SIGNING_PROFILE", profile["UUID"]), ("EXPORT_OPTIONS", str(options)),
            ):
                if "\n" in value or "\r" in value:
                    raise ValueError("Invalid signing metadata")
                output.write(f"{key}={value}\n")
    except Exception:
        cleanup()
        raise


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["cleanup"]:
            cleanup()
        elif sys.argv[1:] == ["prepare"]:
            prepare()
        else:
            raise ValueError("Use prepare or cleanup")
    except subprocess.CalledProcessError:
        # Credential-tool output can contain sensitive values. Never echo it.
        sys.exit("Release credential operation failed; tool output withheld")
    except ValueError as error:
        sys.exit(str(error))
