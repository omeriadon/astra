"""Run: python3 checks/ai-cli-permissions-check.py. Checks the production command runner."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "astra/AI/BrowserAICLI.swift").read_text()
runner = source[source.index("\t@MainActor\n\tprivate final class BrowserAICommand"):source.rindex("\n#endif")]
checks = r'''
enum BrowserAIError: Error {
    case commandMissing(String)
    case commandFailed(String, String)
    case commandTimedOut(String)
}
struct BrowserAIFile {
    let name: String
    let mediaType: String
    let data: Data
}
struct BrowserAIImage {
    let mediaType: String
    let data: Data
}
@main struct Checks {
    @MainActor static func main() async throws {
        UserDefaults.standard.setVolatileDomain([
            "ai-command-executable-codex": CommandLine.arguments[1]
        ], forName: UserDefaults.argumentDomain)
        for arguments in [["app-server"], ["app-server", "--disable", "shell_tool", "--disable", "multi_agent"]] {
            let command = try BrowserAICommand(name: "codex", arguments: arguments)
            defer { command.stop() }
            try command.start(input: "", closeInput: true)
            var allowed = false
            for try await line in command.lines {
                allowed = line == "allowed"
            }
            guard allowed else { throw command.failure() }
        }
        print("Codex generation and catalog tool isolation passed")
    }
}
'''
fake = '''#!/usr/bin/python3
import sys
args = sys.argv[1:]
overrides = dict(value.split("=", 1) for index, value in enumerate(args) if index > 0 and args[index - 1] == "-c")
# Simulate inherited tools trying to launch helpers forbidden by Astra's sandbox.
for feature in ["computer_use", "browser_use", "apps", "plugins", "hooks", "shell_snapshot"]:
    if overrides.get("features." + feature) != "false":
        sys.stderr.write("Operation not permitted launching inherited " + feature + " helper")
        sys.exit(1)
print("allowed", flush=True)
'''
with tempfile.TemporaryDirectory(prefix="astra-cli-permissions-") as temporary:
    directory = Path(temporary)
    command = directory / "codex"
    command.write_text(fake)
    command.chmod(0o700)
    swift = directory / "Checks.swift"
    swift.write_text("import Foundation\nimport Darwin\n" + runner + checks)
    binary = directory / "checks"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(command)], check=True, timeout=15)
