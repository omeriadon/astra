"""Check the contents and ABI export of an Astra website-app runtime."""

import argparse
import ctypes
import plistlib
import subprocess
import tempfile
from pathlib import Path


READER_SCRIPTS = ("Readability.js", "Readability-readerable.js", "Reader.js")
READER_LICENSE = "Readability-LICENSE.txt"
EXTENSION_ARCHIVES = ("darkreader-chrome-mv3.zip", "ublock-origin-lite-safari.zip")


def files_named(root: Path, names: tuple[str, ...]) -> set[str]:
    return {path.name for path in root.rglob("*") if path.is_file() and path.name in names}


def validate(app: Path) -> None:
    runtime = app / "Contents/Frameworks/AstraWebsiteAppRuntime.framework"
    if not runtime.is_dir():
        raise ValueError("AstraWebsiteAppRuntime.framework is missing")

    binary = runtime / "AstraWebsiteAppRuntime"
    if not binary.is_file():
        raise ValueError("AstraWebsiteAppRuntime binary is missing")
    result = subprocess.run(["nm", "-gU", str(binary)], capture_output=True, text=True, check=True)
    exported = {
        line.split()[-1].lstrip("_")
        for line in result.stdout.splitlines()
        if line.split()
    }
    if exported != {"AstraWebsiteAppMain"}:
        raise ValueError(f"Expected only AstraWebsiteAppMain; found {len(exported)} exported symbols")

    runtime_files = files_named(runtime, (*READER_SCRIPTS, READER_LICENSE, *EXTENSION_ARCHIVES))
    if runtime_files:
        raise ValueError(f"Runtime duplicates host resources: {sorted(runtime_files)}")
    if any(path.name == "Assets.car" for path in runtime.rglob("*")):
        raise ValueError("Runtime contains compiled asset resources")

    host_resources = app / "Contents/Resources"
    required_resources = set(READER_SCRIPTS) | {READER_LICENSE} | set(EXTENSION_ARCHIVES)
    missing = required_resources - files_named(host_resources, (*READER_SCRIPTS, READER_LICENSE, *EXTENSION_ARCHIVES))
    if missing:
        raise ValueError(f"Host bundle is missing resources: {sorted(missing)}")
    if not any(path.name == "Assets.car" for path in host_resources.rglob("*")):
        raise ValueError("Host bundle is missing compiled asset resources")


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="astra-runtime-size-check-") as directory:
        root = Path(directory)
        app = root / "astra.app"
        runtime = app / "Contents/Frameworks/AstraWebsiteAppRuntime.framework"
        host = app / "Contents/Resources"
        version = runtime / "Versions/A"
        version.mkdir(parents=True)
        (runtime / "Versions/Current").symlink_to("A")
        (runtime / "AstraWebsiteAppRuntime").symlink_to("Versions/Current/AstraWebsiteAppRuntime")
        (runtime / "Resources").symlink_to("Versions/Current/Resources")
        (version / "Resources").mkdir()
        host.mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.astra.resource-test",
            "CFBundlePackageType": "APPL",
        }))
        (version / "Resources/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.astra.runtime-test",
            "CFBundlePackageType": "FMWK",
            "CFBundleExecutable": "AstraWebsiteAppRuntime",
        }))
        for name in (*READER_SCRIPTS, READER_LICENSE, *EXTENSION_ARCHIVES):
            (host / name).write_bytes(b"fixture")
        (host / "Assets.car").write_bytes(b"fixture")
        fixture = root / "Runtime.swift"
        fixture.write_text('''import Foundation

final class BrowserController: NSObject {}

@_cdecl("AstraWebsiteAppMain")
@MainActor
public func testResources() {
    precondition(BrowserResources.bundle.bundleIdentifier == "dev.astra.resource-test")
    precondition(BrowserResources.bundle.url(forResource: "Reader", withExtension: "js") != nil)
    precondition(BrowserResources.bundle.url(forResource: "ublock-origin-lite-safari", withExtension: "zip") != nil)
    precondition(BrowserResources.bundle.url(forResource: "Assets", withExtension: "car") != nil)
}
''')
        source = Path(__file__).resolve().parents[1] / "astra/App/BrowserResources.swift"
        binary = version / "AstraWebsiteAppRuntime"
        subprocess.run([
            "xcrun", "swiftc", "-emit-library", "-D", "ASTRA_WEBSITE_APP_RUNTIME",
            "-module-name", "AstraWebsiteAppRuntime", str(source), str(fixture),
            "-Xlinker", "-exported_symbol", "-Xlinker", "_AstraWebsiteAppMain",
            "-o", str(binary),
        ], check=True)
        ctypes.CDLL(str(binary)).AstraWebsiteAppMain()
        validate(app)
        main = root / "Main.swift"
        main.write_text('''import Foundation

@main
struct ResourceCheck {
    @MainActor
    static func main() {
        precondition(BrowserResources.bundle === Bundle.main)
    }
}
''')
        executable = root / "resource-check"
        subprocess.run(["xcrun", "swiftc", str(source), str(main), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
        for name in (*READER_SCRIPTS, *EXTENSION_ARCHIVES, "Assets.car"):
            duplicate = version / "Resources" / name
            duplicate.write_bytes(b"duplicate")
            try:
                validate(app)
            except ValueError:
                pass
            else:
                raise AssertionError(f"Duplicated resource passed: {name}")
            duplicate.unlink()
        (host / "Reader.js").unlink()
        try:
            validate(app)
        except ValueError:
            pass
        else:
            raise AssertionError("Missing host reader script passed")


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
    print("Website-app runtime size check passed")
