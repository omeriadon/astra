#!/usr/bin/env python3
"""Exercise the production website-app preparation validation without Dock access."""

import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


SOURCE = Path(__file__).parents[1] / "AstraWebsiteAppInstaller/AstraWebsiteAppInstallerApp.swift"


def check_registration_boundary() -> None:
    """Prevent moving Launch Services registration back into Astra's sandbox."""
    root = Path(__file__).parents[1]
    worker = (root / "astra/App/BrowserWebsiteAppFileWorker.swift").read_text()
    registry = (root / "astra/App/BrowserWebsiteAppRegistry.swift").read_text()
    helper = SOURCE.read_text()
    project = (root / "astra.xcodeproj/project.xcproj").read_text()
    installer_target = project.split('"name": "AstraWebsiteAppInstaller"', 1)[1].split(
        '"name": "AstraWebsiteAppRuntime"', 1
    )[0]

    assert "LSRegisterURL(" not in worker
    assert "LSRegisterURL(" not in registry
    assert helper.count("LSRegisterURL(") == 1
    assert '"ENABLE_APP_SANDBOX": "NO"' in installer_target
    assert helper.count("try registerWebsiteApp(at: websiteApp.url)") == 2
    assert helper.index("let websiteApp = try prepareWebsiteApp(at: appURL)") < helper.index(
        "try registerWebsiteApp(at: websiteApp.url)"
    )
    assert 'try await runInstaller(operation: "--prepare", appURL: url)' in worker
    assert "try await registerGeneratedApp(at: appURL)" in worker
    assert "try await registerGeneratedApp(at: original)" in worker
    assert "try await fileWorker.uninstall(installation, nextRegistry: next)" in registry


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
                "CFBundleIdentifier": f"dev.omeriadon.astra.website.check.{name.lower()}",
                "CFBundleDisplayName": name,
                "CFBundleExecutable": executable,
            },
            stream,
        )
    run("/usr/bin/codesign", "--force", "--sign", "-", str(app))
    return app


def main() -> None:
    check_registration_boundary()
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

import CoreServices
import Synchronization

// Intercept Launch Services so validation can verify registration and errors
// without mutating the CI runner's system registration database.
nonisolated enum RegistrationProbe {
    nonisolated struct State {
        var calls = 0
        var failureStatus: OSStatus?
    }
    static let state = Mutex(State())
    static var calls: Int { state.withLock { $0.calls } }
    static var failureStatus: OSStatus? {
        get { state.withLock { $0.failureStatus } }
        set { state.withLock { $0.failureStatus = newValue } }
    }
}

func LSRegisterURL(_ url: CFURL, _ update: Bool) -> OSStatus {
    RegistrationProbe.state.withLock { state in
        state.calls += 1
        return state.failureStatus ?? noErr
    }
}

extension AstraWebsiteAppInstallerApp {
    static func testPrepareWebsiteApp(at url: URL) throws {
        let websiteApp = try prepareWebsiteApp(at: url)
        try registerWebsiteApp(at: websiteApp.url)
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
        precondition(RegistrationProbe.calls == 1, "Preparation must register the website app")
        var value = [UInt8](repeating: 0, count: 256)
        precondition(getxattr(valid.path, "com.apple.quarantine", &value, value.count, 0, 0) == -1)
        precondition(getxattr(valid.appendingPathComponent("Contents/MacOS/fixture").path, "com.apple.quarantine", &value, value.count, 0, 0) == -1)
        try AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: valid)
        precondition((try? AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: outside)) == nil)
        precondition((try? AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: traversal)) == nil)
        precondition((try? AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: tampered)) == nil)
        precondition(RegistrationProbe.calls == 2, "Invalid apps must be rejected before registration")
        RegistrationProbe.failureStatus = -10819
        do {
            try AstraWebsiteAppInstallerApp.testPrepareWebsiteApp(at: valid)
            preconditionFailure("Registration errors must be propagated")
        } catch {
            precondition(error.localizedDescription.contains("-10819"))
        }
        precondition(RegistrationProbe.calls == 3)
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
