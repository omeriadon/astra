"""Compile the selected AI validators with minimal production collaborators."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
ai = (root / "astra/AI/BrowserAI.swift").read_text()
features = (root / "astra/AI/Features/BrowserPageFeatures.swift").read_text()


def extract(source, signature):
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError(signature)


validate = extract(ai, "private func validate(_ request: BrowserAIRequest)").replace("private func validate", "func validate", 1)
valid_name = extract(features, "static func validSectionName")
cloud_request = ai[ai.index("nonisolated struct BrowserAICloudRequest"):ai.index("/// Features own prompts")]

harness = r'''
import Foundation

enum BrowserAIError: Error { case invalidRequest }
struct BrowserAIRequest {
    let instructions: String
    let prompt: String
    let maximumResponseTokens: Int?
}
struct BrowserAIImage: Encodable {}
CLOUD_REQUEST
struct BrowserAIOutput {
    VALID_NAME
}
final class BrowserAI {
    VALIDATE
}

@main
struct Check {
    static func main() throws {
        let browser = BrowserAI()
        let omitted = try! JSONEncoder().encode(BrowserAICloudRequest(modelID: "model", instructions: "i", prompt: "p", maximumResponseTokens: nil, images: nil, webSearch: nil))
        assert(!String(decoding: omitted, as: UTF8.self).contains("maximumResponseTokens"))
        let encoded = try! JSONEncoder().encode(BrowserAICloudRequest(modelID: "model", instructions: "i", prompt: "p", maximumResponseTokens: 50_000, images: nil, webSearch: nil))
        assert(String(decoding: encoded, as: UTF8.self).contains("maximumResponseTokens"))
        try browser.validate(BrowserAIRequest(instructions: String(repeating: "i", count: 100_000), prompt: "data", maximumResponseTokens: nil))
        try browser.validate(BrowserAIRequest(instructions: "data", prompt: "data", maximumResponseTokens: 50_000))
        for invalid in [0, -1] {
            do {
                try browser.validate(BrowserAIRequest(instructions: "data", prompt: "data", maximumResponseTokens: invalid))
                assertionFailure("nonpositive token budget accepted")
            } catch BrowserAIError.invalidRequest { }
        }
        do {
            try browser.validate(BrowserAIRequest(instructions: "data", prompt: "   ", maximumResponseTokens: nil))
            assertionFailure("empty prompt accepted")
        } catch BrowserAIError.invalidRequest { }
        assert(BrowserAIOutput.validSectionName("A section") )
        assert(BrowserAIOutput.validSectionName(String(repeating: "a", count: 30)))
        assert(!BrowserAIOutput.validSectionName(String(repeating: "a", count: 31)))
        assert(!BrowserAIOutput.validSectionName("line\nbreak"))
        assert(!BrowserAIOutput.validSectionName("   "))
        print("Today AI limit checks passed")
    }
}
'''.replace("VALIDATE", validate).replace("VALID_NAME", valid_name).replace("CLOUD_REQUEST", cloud_request)

with tempfile.TemporaryDirectory() as directory:
    check = Path(directory) / "today-ai-limits-check.swift"
    binary = Path(directory) / "today-ai-limits-check"
    check.write_text(harness)
    subprocess.run(["swiftc", "-Onone", "-parse-as-library", "-o", str(binary), str(check)], check=True)
    subprocess.run([str(binary)], check=True)
