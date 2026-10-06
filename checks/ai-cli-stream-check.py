"""Run: python3 checks/ai-cli-stream-check.py. Exercises the production CLI event accumulator."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "astra/AI/BrowserAICLI.swift").read_text()
start = source.index("nonisolated struct BrowserAICommandResponse")
end = source.index("\n#if os(macOS)", start)
checks = r'''
var codex = BrowserAICommandResponse()
assert(codex.consume(["method": "item/agentMessage/delta", "params": ["itemId": "a", "delta": "Hel"]], codex: true))
assert(codex.text == "Hel" && !codex.completed)
assert(codex.consume(["method": "item/agentMessage/delta", "params": ["itemId": "a", "delta": "lo"]], codex: true))
assert(codex.text == "Hello")
assert(!codex.consume(["method": "item/completed", "params": ["item": ["id": "a", "type": "agentMessage", "text": "Hello"]]], codex: true))
_ = codex.consume(["method": "turn/completed", "params": ["turn": ["status": "completed"]]], codex: true)
assert(codex.completed && codex.text == "Hello")
var failed = BrowserAICommandResponse()
_ = failed.consume(["method": "turn/completed", "params": ["turn": ["status": "failed", "error": ["message": "Permission denied"]]]], codex: true)
assert(!failed.completed && failed.failure == "Permission denied")
var claude = BrowserAICommandResponse()
_ = claude.consume(["type": "stream_event", "event": ["type": "content_block_delta", "delta": ["type": "text_delta", "text": "Hi"]]], codex: false)
assert(claude.text == "Hi" && !claude.completed)
_ = claude.consume(["type": "assistant", "message": ["content": [["type": "text", "text": "Hi"]]]], codex: false)
_ = claude.consume(["type": "result", "result": "Hi", "is_error": false], codex: false)
assert(claude.completed && claude.text == "Hi")
var claudeFailure = BrowserAICommandResponse()
_ = claudeFailure.consume(["type": "result", "is_error": true, "errors": ["Unavailable"]], codex: false)
assert(!claudeFailure.completed && claudeFailure.failure == "Unavailable")
print("CLI stream check passed")
'''
with tempfile.TemporaryDirectory() as directory:
    script = Path(directory) / "main.swift"
    script.write_text("import Foundation\n" + source[start:end] + checks)
    subprocess.run(["swift", str(script)], check=True)
