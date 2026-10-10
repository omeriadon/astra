"""Check the website-app helper in a built Astra bundle without launching it."""

import argparse
import os
import plistlib
import tempfile
from pathlib import Path


def validate(app: Path) -> None:
    with (app / "Contents/Info.plist").open("rb") as stream:
        main = plistlib.load(stream)
    helper = app / "Contents/Resources/AstraWebsiteAppTemplate.app"
    with (helper / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != "dev.omeriadon.astra.website-template":
        raise ValueError("Unexpected website-app helper identity")
    for key in ("CFBundleVersion", "CFBundleShortVersionString"):
        if not main.get(key) or info.get(key) != main[key]:
            raise ValueError(f"Website-app helper does not match Astra's {key}")
    name = info.get("CFBundleExecutable")
    if not isinstance(name, str) or not name or Path(name).name != name:
        raise ValueError("Invalid website-app helper executable name")
    executable = helper / "Contents/MacOS" / name
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("Website-app helper executable is missing or not executable")
    if info.get("CFBundleURLTypes"):
        raise ValueError("Website-app helper must not register Astra's URL handlers")


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="astra-helper-bundle-check-") as directory:
        app = Path(directory) / "astra.app"
        main = {"CFBundleVersion": "3", "CFBundleShortVersionString": "0.0"}
        helper = app / "Contents/Resources/AstraWebsiteAppTemplate.app"
        executable = helper / "Contents/MacOS/AstraWebsiteAppTemplate"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b"fixture")
        executable.chmod(0o755)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(main))
        info = {
            **main,
            "CFBundleIdentifier": "dev.omeriadon.astra.website-template",
            "CFBundleExecutable": executable.name,
        }
        plist = helper / "Contents/Info.plist"
        plist.write_bytes(plistlib.dumps(info))
        validate(app)
        for mutation in (
            {"CFBundleVersion": "2"},
            {"CFBundleIdentifier": "com.omeriadon.astra"},
            {"CFBundleExecutable": "../invalid"},
            {"CFBundleExecutable": "missing"},
            {"CFBundleURLTypes": [{"CFBundleURLSchemes": ["astra"]}]},
        ):
            plist.write_bytes(plistlib.dumps({**info, **mutation}))
            try:
                validate(app)
            except ValueError:
                pass
            else:
                raise AssertionError(f"Invalid helper passed: {mutation}")
        plist.unlink()
        try:
            validate(app)
        except FileNotFoundError:
            pass
        else:
            raise AssertionError("Missing helper passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
    elif arguments.app:
        validate(arguments.app)
    else:
        parser.error("Provide an Astra app bundle or --self-test")
    print("Website-app helper bundle check passed")
