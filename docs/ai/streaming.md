# Streaming and single responses

[AI documentation](../ai-features.md) · [Adding a feature](adding-features.md)

| API | Result | Progress |
| --- | --- | --- |
| `perform(feature, input:model:)` | Validated feature output | None |
| `performStreaming(feature, input:model:onSnapshot:)` | Validated feature output | Cumulative text snapshots |
| `generate(request, model:)` | Complete raw text | None |
| `stream(request, model:onSnapshot:)` | Complete raw text | Cumulative text snapshots |

Each call owns a fresh Apple model session or cloud request. Calls do not
share conversation transcripts. The single-response path uses native
`respond` or the server JSON endpoint; streaming uses native `streamResponse`
or the server SSE endpoint. Streaming does not wait for a complete response
and then split it into artificial chunks.

## Snapshot semantics

Apple returns cumulative snapshots. The proxy converts OpenRouter deltas to
the same cumulative form. For text `Hello world`, callbacks might receive
`Hello`, then `Hello world`. Replace the preview with each snapshot.

`onSnapshot` is a synchronous main-actor callback. The async method returns
only after successful completion. `performStreaming` then calls
`output(from:)` once on complete text, giving the same validation as `perform`.

Do not validate or commit each snapshot as if it were a complete answer.
Provider chunk sizes and callback counts are not fixed. Final text may also
arrive as the last callback, so duplicate text is permitted.

## Cancellation and errors

Run generation inside a task owned by the view or operation. Cancel that
task when the operation is abandoned. Cancellation checks occur during
iteration; cloud sessions are invalidated when the call exits. The server
writes with backpressure and drops its upstream body when the downstream
stream stops. Provider-side cancellation and billing depend on the selected
provider.

Signing out or changing servers prevents further snapshots and final output
once the next stream event is processed. A provider timeout bounds an idle
cloud connection. HTTP 500/502/503/504 errors before streaming starts are retried with 1s and 3s backoff. Other HTTP errors throw normally. A
midstream error is a terminal SSE error; the client throws and does not
return partial text as a successful result. EOF without a final event also
throws. A stream that has begun (including a provider error event, malformed event, or premature EOF) is **never replayed**, because browser tools may already have executed. Non-streaming cloud POST requests use the same bounded pre-response transient-failure retries. Calls never silently switch providers.

## Server wire format

`POST /v1/ai/generate` and `POST /v1/ai/stream` accept the same authenticated
JSON request. The first returns `{ "text": "Hello world" }`.
The second returns `Content-Type: text/event-stream`:

```text
data: {"text":"Hello","isFinal":false}

data: {"text":"Hello world","isFinal":false}

data: {"text":"Hello world","isFinal":true}

```

An error after the HTTP 200 headers is sent as:

```text
data: {"error":"Cloud AI generation failed."}

```

A final event means the provider reported a normal stop and its `[DONE]`
marker was received. Truncated, empty, malformed, and error responses fail.
Never inspect only HTTP status when judging a streaming result.

The proxy ignores OpenRouter comments and supports multiline SSE fields,
CR/LF delimiters, split UTF-8, and repeated finish reasons in usage frames.
It emits only the normalized event fields above; credentials, provider error
details, and usage identifiers are not forwarded.

## Debug diagnostics

Astra logs a shared operation UUID from the feature invocation through HTTP
attempts, response status, duration, and server request ID (when provided).
Debug builds additionally log the server's error body (up to 8 KiB), model,
prompt metadata and content, SSE event progression, chat context sizes, tool
execution and final output previews. Release builds redact user content and
never log authorization header values or token-bearing request bodies.
HTTP 5xx from both AI and Sync can indicate a shared service problem; retries
do not fix a persistent server outage. Debug logs can contain private page
content and should not be shared publicly.
