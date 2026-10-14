"""Prevent future releases from bundling third-party extensions or Apple system fonts."""

import argparse
import tempfile
from pathlib import Path

FORBIDDEN = {
    "darkreader-chrome-mv3.zip",
    "ublock-origin-lite-safari.zip",
    "SF-Mono-Regular.otf",
    "NewYorkSmall-Regular.otf",
}

SOURCE = Path("astra")


def source_check() -> None:
    for root in (SOURCE / "Extensions", SOURCE / "Resources/EaselFonts"):
        for name in FORBIDDEN:
            assert not (root / name).exists(), f"Forbidden bundled source: {root / name}"
    fonts = (SOURCE / "UI/Content/BrowserEaselFonts.swift").read_text()
    assert all(name not in fonts for name in ("SF-Mono-Regular.otf", "NewYorkSmall-Regular.otf"))
    manager = (SOURCE / "Web/Extensions/BrowserExtensionManager.swift").read_text()
    assert "private let bundledNames" not in manager
    assert "func installRecommended(" in manager
    assert "verifySHA256(" in manager


def bundle_check(app: Path) -> None:
    assert (app / "Contents").is_dir(), f"Invalid app bundle: {app}"
    for item in (app / "Contents").rglob("*"):
        if item.is_file() and item.name in FORBIDDEN:
            raise AssertionError(f"Disallowed extension/font resource in Astra: {item}")


def self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        app = Path(directory) / "astra.app"
        resources = app / "Contents/Resources"
        resources.mkdir(parents=True)
        bundle_check(app)
        for name in sorted(FORBIDDEN):
            asset = resources / name
            asset.touch()
            try:
                bundle_check(app)
            except AssertionError:
                pass
            else:
                raise AssertionError(f"Failed to detect forbidden asset {name}")
            finally:
                asset.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    source_check()
    if args.self_test:
        self_test()
    if args.app:
        bundle_check(args.app)
    print("Astra optional-extension and system-font packaging checks passed")
