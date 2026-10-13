#!/usr/bin/env python3
"""Verify Astra's strict compiler configuration and Swift 6.4 toolchain."""

import json
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "astra.xcodeproj" / "project.xcproj"
EXPECTED_TARGETS = {
    "astra",
    "AstraWebsiteAppTemplate",
    "AstraWebsiteAppInstaller",
    "AstraWebsiteAppRuntime",
    "AstraUpdaterRuntime",
}


def require(actual, expected, name):
    if actual != expected:
        raise RuntimeError(f"{name}: expected {expected!r}, got {actual!r}")


def main():
    # Xcode's text project has JSON-like syntax with trailing commas.
    data = json.loads(re.sub(r",\s*([}\]])", r"\1", PROJECT.read_text()))
    settings = data["build-settings"]

    require({target["name"] for target in data["targets"]}, EXPECTED_TARGETS, "project targets")
    require(settings["ENABLE_SECURITY_COMPILER_WARNINGS"], "YES", "Clang security warnings")
    require(settings["CLANG_WARN_UNSAFE_BUFFER_USAGE"], "YES", "unsafe-buffer warnings")
    require(settings["GCC_TREAT_WARNINGS_AS_ERRORS"], "NO", "Clang warnings remain warnings")
    require(settings["SWIFT_TREAT_WARNINGS_AS_ERRORS"], "NO", "Swift warnings remain warnings")
    require(settings["SWIFT_OPTIMIZATION_LEVEL[config=Debug]"], "-Onone", "Debug optimisations")
    require(settings["SWIFT_COMPILATION_MODE[config=Release]"], "wholemodule", "Release compilation")

    for target in data["targets"]:
        name = target["name"]
        build = target["build-settings"]
        for field, expected in (
            ("SWIFT_VERSION", "6.0"),
            ("SWIFT_STRICT_CONCURRENCY", "complete"),
            ("SWIFT_STRICT_MEMORY_SAFETY", "YES"),
            ("SWIFT_TREAT_WARNINGS_AS_ERRORS", "NO"),
        ):
            require(build.get(field), expected, f"{name} {field}")
        if build.get("SWIFT_OPTIMIZATION_LEVEL[config=Debug]") not in (None, "-Onone"):
            raise RuntimeError(f"{name}: Debug optimisation must remain off")

    # Swift compiler version 6.4 uses language mode 6; there is no '6.4' mode.
    if "--skip-toolchain-check" not in sys.argv[1:]:
        version = subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip()
        if not re.search(r"\bSwift version 6\.4(?:\.\d+)?\b", version):
            raise RuntimeError(f"Expected Swift 6.4 toolchain, got: {version}")
        print(f"Compiler: {version}")
    print("Strict Swift 6 compiler diagnostics verified; warnings remain warnings.")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
