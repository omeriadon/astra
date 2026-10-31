"""Verify third-party extension archives and Apple system fonts stay out of Astra."""

import argparse
import tempfile
from pathlib import Path

SOURCE = Path("astra")
SYSTEM_FONT_FILES = {"SF-Mono-Regular.otf", "NewYorkSmall-Regular.otf"}


def source_check() -> None:
    extensions = SOURCE / "Extensions"
    assert not list(extensions.rglob("*.zip")), "Extension archives must not ship in Astra's sources"
    fonts = SOURCE / "Resources/EaselFonts"
    for name in SYSTEM_FONT_FILES:
        assert not (fonts / name).exists(), f"Apple system font should not be bundled: {name}"


def bundle_check(app: Path) -> None:
    resources = app / "Contents/Resources"
    assert resources.is_dir(), f"Invalid app bundle: {app}"
    for item in resources.rglob("*"):
        if item.is_file() and (item.suffix.lower() == ".zip" or item.name in SYSTEM_FONT_FILES):
            raise AssertionError(f"Disallowed bundled ZIP or Apple font: {item}")


def self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        app = Path(directory) / "astra.app"
        resources = app / "Contents/Resources"
        resources.mkdir(parents=True)
        bundle_check(app)
        for name in ("example-extension.zip", *sorted(SYSTEM_FONT_FILES)):
            item = resources / name
            item.touch()
            try:
                bundle_check(app)
            except AssertionError:
                pass
            else:
                raise AssertionError(f"Failed to detect forbidden resource: {name}")
            finally:
                item.unlink()


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
    print("Astra extension-free bundle and system-font check passed")
