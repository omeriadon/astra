"""Check the contents and ABI export of an Astra website-app runtime."""

import argparse
import ctypes
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


READER_SCRIPTS = ("Readability.js", "Readability-readerable.js", "Reader.js")
READER_LICENSE = "Readability-LICENSE.txt"
EXTENSION_ARCHIVES = ("darkreader-chrome-mv3.zip", "ublock-origin-lite-safari.zip")
PACKAGE_BUNDLES = (
    "Defaults_Defaults.bundle", "Litext_Litext.bundle", "MarkdownView_MarkdownView.bundle",
    "Noise_Noise.bundle", "SwiftMath_SwiftMath.bundle",
)


def files_named(root: Path, names: tuple[str, ...]) -> set[str]:
    return {path.name for path in root.rglob("*") if path.is_file() and path.name in names}


def validate(app: Path) -> None:
    runtime = app / "Contents/Frameworks/AstraWebsiteAppRuntime.framework"
    if not runtime.is_dir():
        raise ValueError("AstraWebsiteAppRuntime.framework is missing")

    binary = runtime / "AstraWebsiteAppRuntime"
    if not binary.is_file():
        raise ValueError("AstraWebsiteAppRuntime binary is missing")
    result = subprocess.run(["nm", "-jgU", str(binary)], capture_output=True, text=True, check=True)
    exported = {
        line.lstrip("_")
        for line in result.stdout.splitlines()
        if line and not line.endswith(":")
    }
    if exported != {"AstraWebsiteAppMain", "AstraBrowserMain"}:
        raise ValueError(f"Expected two runtime entry points; found {len(exported)} exported symbols")
    defined = subprocess.run(["nm", "--no-dyldinfo", "-jU", str(binary)], capture_output=True, text=True, check=True)
    symbols = {line.lstrip("_") for line in defined.stdout.splitlines() if line and not line.endswith(":")}
    if symbols != exported:
        raise ValueError("Runtime retains local symbols; keep them in the external dSYM")

    main_binary = app / "Contents/MacOS/astra"
    if not main_binary.is_file():
        raise ValueError("Host executable is missing")
    host_binaries = [main_binary, *main_binary.parent.glob("astra.debug.dylib")]
    linked_runtime = False
    for host_binary in host_binaries:
        # The host only launches the shared implementation; a whole browser copy exceeds this budget.
        if host_binary.stat().st_size > 1024 * 1024:
            raise ValueError(f"Host launcher exceeds 1 MiB; browser code may be duplicated: {host_binary.name}")
        dependencies = subprocess.run(
            ["otool", "-L", str(host_binary)], capture_output=True, text=True, check=True
        ).stdout
        linked_runtime |= "AstraWebsiteAppRuntime.framework" in dependencies
    if not linked_runtime:
        raise ValueError("Host launcher does not link AstraWebsiteAppRuntime.framework")

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
    for name in PACKAGE_BUNDLES:
        if not (host_resources / name).is_dir():
            raise ValueError(f"Host bundle is missing package resources: {name}")


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
        for name in PACKAGE_BUNDLES:
            (host / name).mkdir()
        fixture = root / "Runtime.swift"
        fixture.write_text('''import Foundation

@MainActor
enum browserApp {
    static func main() {
        precondition(["dev.astra.resource-test", "com.omeriadon.astra"].contains(BrowserResources.bundle.bundleIdentifier ?? ""))
        precondition(BrowserResources.bundle.url(forResource: "Reader", withExtension: "js") != nil)
        precondition(BrowserResources.bundle.url(forResource: "ublock-origin-lite-safari", withExtension: "zip") != nil)
        precondition(BrowserResources.bundle.url(forResource: "Assets", withExtension: "car") != nil)
    }
}

@MainActor
enum BrowserWebsiteAppHelperMain {
    static func main() {
        browserApp.main()
    }
}
''')
        source = Path(__file__).resolve().parents[1] / "astra/App/BrowserResources.swift"
        runtime_source = Path(__file__).resolve().parents[1] / "AstraWebsiteAppRuntime/AstraWebsiteAppRuntime.swift"
        binary = version / "AstraWebsiteAppRuntime"
        subprocess.run([
            "xcrun", "swiftc", "-emit-library", "-D", "ASTRA_WEBSITE_APP_RUNTIME",
            "-module-name", "AstraWebsiteAppRuntime", str(source), str(fixture), str(runtime_source),
            "-Xlinker", "-install_name", "-Xlinker",
            "@rpath/AstraWebsiteAppRuntime.framework/Versions/A/AstraWebsiteAppRuntime",
            "-Xlinker", "-exported_symbol", "-Xlinker", "_AstraWebsiteAppMain",
            "-Xlinker", "-exported_symbol", "-Xlinker", "_AstraBrowserMain",
            "-o", str(binary),
        ], check=True)
        subprocess.run(["strip", "-T", "-x", str(binary)], check=True)
        ctypes.CDLL(str(binary)).AstraWebsiteAppMain()
        ctypes.CDLL(str(binary)).AstraBrowserMain()
        launcher_source = Path(__file__).resolve().parents[1] / "AstraAppLauncher/AstraAppLauncher.c"
        executable = app / "Contents/MacOS/astra"
        executable.parent.mkdir(parents=True)
        subprocess.run([
            "xcrun", "clang", str(launcher_source), str(binary),
            "-Wl,-rpath,@executable_path/../Frameworks",
            "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True)
        validate(app)
        nested_runtime = runtime.parent / "Nested/AstraWebsiteAppRuntime.framework"
        shutil.copytree(runtime, nested_runtime, symlinks=True)
        subprocess.run([
            sys.executable, "-c", "import ctypes, sys; ctypes.CDLL(sys.argv[1]).AstraWebsiteAppMain()",
            str(nested_runtime / "AstraWebsiteAppRuntime"),
        ], check=True)
        main_info = app / "Contents/Info.plist"
        main_info.write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.omeriadon.astra",
            "CFBundlePackageType": "APPL",
        }))
        subprocess.run([str(executable)], check=True)
        duplicate_code = executable.parent / "astra.debug.dylib"
        duplicate_code.write_bytes(bytes(1024 * 1024 + 1))
        try:
            validate(app)
        except ValueError as error:
            assert "Host launcher exceeds" in str(error)
        else:
            raise AssertionError("Duplicated browser code passed")
        duplicate_code.unlink()
        package = host / PACKAGE_BUNDLES[0]
        package.rmdir()
        try:
            validate(app)
        except ValueError as error:
            assert "missing package resources" in str(error)
        else:
            raise AssertionError("Missing package bundle passed")
        package.mkdir()
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
