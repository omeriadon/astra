# AI features

`BrowserAI.shared` runs isolated AI features with single and streaming responses. Only OpenRouter requires an Astra account session. On-device Foundation Models,
PCC, Codex, and Claude do not require Astra sign-in. On-device generation runs locally; PCC uses Apple’s private cloud;
OpenRouter runs through the configured Astra server. CLI overrides use their
existing signed-in account instead. Providers never switch automatically.
Signing out or changing servers invalidates pending results.

## Guides

- [Adding an AI feature](ai/adding-features.md)
- [Streaming and single responses](ai/streaming.md)

## Models

```swift
let local: BrowserAIModel = .appleIntelligence
let cloud: BrowserAIModel = .openRouter()
let selected: BrowserAIModel = .openRouter(modelID: "openai/gpt-4o-mini")
```

Shipped cloud feature presets use `openai/gpt-4o-mini` for image support and current
availability. The generic `.openRouter()` transport default remains
`inclusionai/ling-3.1-flash`; explicit Developer selections are preserved. The server must allow a
model ID before clients can use it. The app never contains an OpenRouter key.

## Adding a feature

Implement `BrowserAIFeature` under `astra/AI/Features`. Define its input and
output, default model, request instructions, prompt, output token limit, and
output validation. Then call the manager:

```swift
let stem = try await BrowserAI.shared.perform(
    BrowserDownloadNamingFeature(),
    input: .init(original: "report_2026", source: "example.com", fileType: "pdf")
)
```

The optional `model:` argument overrides a feature's default explicitly. A
feature owns decisions about what data may leave the device. Cloud features
must be deliberate user actions with clear data disclosure; do not silently
send private page content or automatically fall back from on-device to cloud.

OpenRouter prompts have a 16 MiB UTF-8 transport ceiling, with instructions limited
to 32 KiB and a 20 MiB encoded request-body ceiling. There is no app token cap for chat.
Provider context windows still apply. Output limits are
1–2,048 tokens. Handle `BrowserAIError`, provider errors, and task cancellation
at the feature's caller. Treat output as untrusted data; validation belongs in
`output(from:)`, before applying any change.

Default download naming remains on-device and retains the existing setting, filename
sanitization, extension preservation, collision handling, and private-download
exclusion. With the default preset, signed-out users keep the original downloaded filename.
An explicit Codex/Claude override also applies to download naming.

## Server

`POST /v1/ai/generate` and `POST /v1/ai/stream` use the existing Astra bearer session. Its JSON body is:

```json
{
  "modelID": "openai/gpt-4o-mini",
  "instructions": "Return a short filename stem.",
  "prompt": "Original filename: report_2026",
  "maximumResponseTokens": 128
}
```

The response is `{ "text": "Annual Report 2026" }`. The server owns provider
credentials, allowlisting, quotas, and provider error sanitization. See the
server README for configuration and deployment constraints.

## Browser features and settings

Settings → AI owns download naming, link previews, Today tab grouping, title
cleanup, Find answers, and the chat pane. Existing download naming preferences
retain their key. AI settings are device-local and participate in settings reset.
Private windows do not send page data or tab metadata to these features.

| Feature | Shipped preset | Context |
| --- | --- | --- |
| Download names | On-device Foundation Model | Filename, source, file type; existing filesystem safeguards |
| Link previews | OpenRouter | Destination rendered in a separate nonpersistent web view; up to 26K Apple tokens |
| Today groups | OpenRouter | Tab titles, URLs, IDs; validated complete membership |
| Find answers | OpenRouter | Rendered current-page text; optional 40K → 30K threshold rule |
| Chat | OpenRouter | Complete explicitly linked page text and conversation; no app token truncation |
| Today titles | On-device Foundation Model | Current title, URL, optional first 2K Apple tokens; seven-word maximum |

Link previews start after two seconds on the same link. Incomplete previews
cancel on unhover; completed previews remain selectable until scrolling, outside
clicks anywhere in the app, or navigation dismisses them. Hovering the card
reveals Copy Preview and, when chat is open, Add to Chat. The latter supplies
the full extracted page, rather than only the summary excerpt. Their JSON title/header/bullets are validated before rendering; the header is
bold and there are at most five 20-word bullets. Each bullet is a text/symbol
object. The model chooses from 360 CLI-validated SF Symbols, and unknown names
are rejected. Find
keeps literal matching, then debounces unmatched text for 750 ms before asking.
The threshold is strictly greater than 40,000 tokens. Native provider limits can
still reject an oversized request even when the optional cap is disabled.

`BrowserAIPageText` extracts rendered DOM text in an isolated content world,
including open shadow roots and same-origin frames. It excludes scripts, styles,
hidden subtrees, input controls, and editable drafts. It preserves repeated
facts and document order, normalizes whitespace, and never serializes HTML.
Cross-origin frames, closed shadow roots, unloaded lazy content, canvas text,
and PDF content are not available through this DOM extraction. Token budgets
use Apple's tokenizer, rather than estimating characters per token.

Today groups remain normal tabs, persist with the space, and are reconciled
against current membership. Cleanup validates outputs before changing tabs and
rejects stale title/URL results. Hibernated titles can use title/URL alone.
Chat suggests case-insensitive literal title matches from the current space;
an explicit `@Exact Page Title` can link another normal space/window. Private
sessions are excluded. Failed or canceled responses do not become committed
conversation turns. Saved conversations, their generated titles, complete page
context, and attachments stay in the local `ai-chats.json` archive, written
atomically with restricted permissions. They do not enter browser sync. Recent
Chats is a top-of-pane popover shared across normal windows.

## Provider experiment

The user chooses Default, Codex, or Claude for all features. Production settings
never expose preset model identities. Debug Developer settings can choose each
feature preset and the CLI override models. Catalogs are fetched afresh when
the selection popover opens: Codex `app-server` `model/list`, Claude's CLI
initialize control response, and OpenRouter's public catalog. OpenRouter models
must also be server-allowlisted. Chat presets permit OpenRouter or either CLI.

Codex generations use `codex exec` in an empty temporary directory with
read-only sandboxing, shell tools disabled, low reasoning, ignored user config,
and ephemeral sessions. Claude uses print mode, no tools or MCP servers, no
session persistence, and low effort. Inputs travel through stdin, never a shell
command. Both use the CLI's existing account and do not require Astra auth.
Images use Codex `--image` temporary files and native Claude stream-JSON image
blocks. Nonimage attachments supply extracted PDF, UTF-8/UTF-16, Word, or RTF
text. The composer shows image thumbnails and removable file chips above its
glass-backed field. Individual source files are limited to 20 MiB; at most eight
images totaling 10 MiB can be sent. The OpenRouter proxy preserves native image
content instead of treating base64 as text. These CLI calls are single responses; the streaming API emits their completed
response as one snapshot. Cancellation terminates the process. Claude must be
installed in PATH, Homebrew's bin directories, or `~/.local/bin`.

PCC uses `PrivateCloudComputeLanguageModel` and light reasoning on OS 27+.
Apple-managed access and a matching signing profile are required. The normal
development target retains `astra.entitlements` so an unapproved profile can
build. After approval, configure `CODE_SIGN_ENTITLEMENTS` to
`astra/Special/astra-pcc.entitlements`, which retains Sign in with Apple and
adds `com.apple.developer.private-cloud-compute`. Unavailable PCC fails visibly
without switching providers. The local server changes for large OpenRouter
inputs, images, and low reasoning have been deployed to production; the AI Nginx location
allows 20 MiB and disables response buffering.

Runnable checks: `python3 checks/ai-features-check.py`,
`bun checks/ai-page-text-check.mjs`, `bun checks/link-hover-check.mjs`, and
`bun checks/find-count-check.mjs`. The Swift check compiles production output
validators and CLI transport with type-only host stubs and fake CLI processes;
it verifies limits, ID coverage, exact mentions, live catalog parsing, long stdin,
low effort/tool restrictions, and cancellation without inference charges.


Sync scheduling now queues a follow-up while a sync is active instead of canceling
its own request during merge-triggered changes. Expected task and URLSession
cancellation stay out of Account & Sync's error label. Only paid OpenRouter
requests check Astra authentication; chat checks it before reading linked pages,
and its signed-out banner links to Account & Sync. HTTP errors retain bounded
server reasons. CLI failures distinguish missing tools, account access, unsupported
models/arguments, usage limits, large context, network errors, permissions, and
timeouts without exposing captured credentials.

Additional checks: `python3 checks/sync-cancellation-check.py` and
`python3 checks/ai-chat-archive-check.py`. The latter runs the production archive
and attachment reader in an isolated folder, including corrupt-file preservation.
