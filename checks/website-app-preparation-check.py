#!/usr/bin/env python3
"""Exercise the production website-app preparation validation without Dock access."""

import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


SOURCE = Path(__file__).parents[1] / "AstraWebsiteAppInstaller/AstraWebsiteAppInstallerApp.swift"


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def make_bundle(root: Path, name: str, executable: str = "fixture") -> Path:
    app = root / f"{name}.app"
    binary = app / "Contents/MacOS" / executable
    binary.parent.mkdir(parents=True)
    shutil.copy("/usr/bin/true", binary)
    binary.chmod(0o755)
    with (app / "Contents/Info.plist").open("wb") as stream:
        plistlib.dump(
            {
                "CFBundleIdentifier": "dev.omeriadon.astra.website.check",
                "CFBundleDisplayName": name,
                "CFBundleExecutable": executable,
            },
            stream,
        )
    run("/usr/bin/codesign", "--force", "--sign", "-", str(app))
    return app


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="astra-website-preparation-") as temporary:
        root = Path(temporary) / "Website Apps"
        root.mkdir()
        outside = Path(temporary) / "Outside"
        outside.mkdir()
        valid = make_bundle(root, "Valid")
        valid_binary = valid / "Contents/MacOS/fixture"
        run("/usr/bin/xattr", "-w", "com.apple.quarantine", "0081;00000000;Astra;https://example.com", str(valid))
        run("/usr/bin/xattr", "-w", "com.apple.quarantine", "0081;00000000;Astra;https://example.com", str(valid_binary))
        outside_app = make_bundle(outside, "Outside")
        traversal = make_bundle(root, "Traversal")
        with (traversal / "Contents/Info.plist").open("rb") as stream:
            traversal_info = plistlib.load(stream)
        traversal_info["CFBundleExecutable"] = "../escape"
        with (traversal / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(traversal_info, stream)
        tampered = make_bundle(root, "Tampered")
        with (tampered / "Contents/MacOS/fixture").open("ab") as stream:
            stream.write(b"tampered")

        source = SOURCE.read_text()
        source = source.replace("@main\nenum AstraWebsiteAppInstallerApp", "enum AstraWebsiteAppInstallerApp", 1)
        old_root = """\tprivate static var installationRoot: URL {
\t\tFileManager.default.homeDirectoryForCurrentUser
\t\t\t.appendingPathComponent(\"Library/Containers/com.omeriadon.astra/Data/Library/Application Support/Astra/Website Apps\", isDirectory: true)
\t\t\t.resolvingSymlinksInPath()
\t}"""
        root_literal = str(root).replace("\\", "\\\\").replace('"', '\\"')
        assert old_root in source, "Production installation root changed"
        source = source.replace(old_root, f'\tprivate static var installationRoot: URL {{ URL(fileURLWithPath: "{root_literal}") }}', 1)
        source += """

extension AstraWebsiteAppInstallerApp {
    static func testPrepareWebsiteApp(at url: URL) throws {
        _ = try prepareWebsiteApp(at: url)
    }
}

@main
@MainActor
struct WebsiteAppPreparationCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let valid = root.appendingPathComponent("Valid.app")
        let outside = URL(fileURLWithPath: CommandLine.arguments[2])
        let traversal = root.appendingPathComponent("Traversal.app")
        let tampered = root.appendingPathComponent("Tampered.app")
        try AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: valid)
        var value = [UInt8](repeating: 0, count: 256)
        precondition(getxattr(valid.path, "com.apple.quarantine", &value, value.count, 0, 0) == -1)
        precondition(getxattr(valid.appendingPathComponent("Contents/MacOS/fixture").path, "com.apple.quarantine", &value, value.count, 0, 0) == -1)
        try AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: valid)
        precondition((try? AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: outside)) == nil)
        precondition((try? AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: traversal)) == nil)
        precondition((try? AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: tampered)) == nil)
        print("website-app preparation validation passed")
    }
}
"""
        generated = Path(temporary) / "WebsiteAppPreparationCheck.swift"
        generated.write_text(source)
        binary = Path(temporary) / "WebsiteAppPreparationCheck"
        run("swiftc", "-parse-as-library", str(generated), "-o", str(binary))
        subprocess.run([str(binary), str(root), str(outside_app)], check=True)


if __name__ == "__main__":
    main()
