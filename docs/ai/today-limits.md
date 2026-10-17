# Today grouping and AI limits

Audited from the Astra client and the local `browser_server` source on 2026-10-08. Client response-budget and instruction-size ceilings described below were removed. The server changes must be deployed before the default cloud grouping path can rely on omitted response budgets.

## Today sections

| Restriction | Current behavior | Source |
| --- | --- | --- |
| Minimum tab count | Sort appears only with more than six Today tabs. This counts internal tabs too, before filtering. | `BrowserAITabDivider.swift` |
| Eligible input | Only normal tabs with a URL and no internal page are supplied. Private browsing and disabled AI block grouping. | `BrowserShellControls.swift` |
| Response budget | Grouping and repair leave the response budget unset. Other features continue to request their own budgets. Explicit nonpositive budgets are rejected. | `BrowserPageFeatures.swift`, `BrowserShellControls.swift`, `BrowserAI.swift` |
| Instructions | No client instruction-byte ceiling in the shared validator. | `BrowserAI.swift` |
| Empty prompt | Whitespace-only prompts are rejected. An empty encoded tab array is not rejected here. | `BrowserAI.swift` |
| Repair | One additional request after an invalid response; the previous streaming output is passed without a client prefix truncation. Other errors do not trigger repair. | `BrowserShellControls.swift` |
| Requested name length | Prompt asks for one to four words and no more than 30 characters. | `BrowserAIPrompts.swift` |
| Accepted names | Nonempty, one line, no control characters, at most 30 Swift characters. Exact names must be unique. | `BrowserPageFeatures.swift` |
| Sections | Nonempty result and nonempty membership in every section. No hard maximum section count. Prompt discourages one section per tab. | `BrowserPageFeatures.swift`, `BrowserAIPrompts.swift` |
| Tab assignments | Every supplied UUID exactly once; no omitted, duplicated, or unknown UUIDs. | `BrowserPageFeatures.swift` |
| Stale results | Titles and URLs must match the snapshot; applying groups also requires unchanged normal-tab membership and order. | `BrowserShellControls.swift`, `Browser.swift` |

There is no explicit client maximum tab count, title length in grouping input, grouping URL length, or prompt byte length in `BrowserAI.validate`. Model context and provider response capacity still constrain how many tabs can be grouped.

## Shared transport and adjacent AI features

| Restriction | Current client behavior | Source |
| --- | --- | --- |
| Response tokens | Shared validator accepts an omitted budget or any positive explicit budget. | `BrowserAI.swift` |
| Default model identifier | Nonempty and at most 200 UTF-8 bytes. | `BrowserAI.swift` |
| Default AI streaming body | Client encoded JSON at most 20 MiB, including base64 images; the deployed server route also collects at most 20 MB. | `BrowserSync.swift`, `browser_server/Sources/brower_server/AI/BrowserAIService.swift` |
| Default AI timeout | Client timeout is 90 seconds; the server provider request and streaming upstream execution timeout are 75 seconds. Generation POST is not automatically retried. | `BrowserSync.swift`, `browser_server/Sources/brower_server/AI/BrowserAIService.swift` |
| Nonstreaming response | Client generic request helper rejects response bodies above 16 MiB; the server accepts provider completion bodies up to 262,144 bytes. No corresponding cumulative stream-text cap found. | `BrowserSync.swift`, `browser_server/Sources/brower_server/AI/BrowserAIService.swift` |
| CLI timeout | 180 seconds per command. Token budget is supplied as a textual instruction to CLI providers. | `BrowserAICLI.swift` |
| Images | At most eight and at most 10 MiB total, including images retained in the chat transcript. Each imported encoded PNG must fit 10 MiB. | `BrowserAIChat.swift`, `BrowserAIAttachment.swift` |
| Image dimensions | macOS imports resize the longest side to at most 2,048 pixels. The iOS import branch does not perform this resize. | `BrowserAIAttachment.swift` |
| Attachment name | First 200 Swift characters. No original source-file byte cap found in the current attachment reader. | `BrowserAIAttachment.swift` |
| Provider capabilities | Apple on-device and PCC reject images. Files without extracted text require Codex or Claude. Default requires Astra authentication. | `BrowserAI.swift` |
| Server quotas | Per subject: 100 requests per day, 10 per minute, and 2 active requests. Process-wide: 8 active requests. The process tracks at most 10,000 subjects. Quotas reset with process restart. | `browser_server/Sources/brower_server/AI/BrowserAIService.swift` |
| Tool loop | Five model rounds per user turn; up to five actions per round. Thus up to 25 actions may execute before the loop reports its limit. | `BrowserAIChat.swift`, `BrowserAITools.swift` |
| Tool arguments | Up to eight arguments per action, each value at most 8,192 UTF-8 bytes. Folder/bookmark names are separately capped at 500 bytes; tool tab renames truncate to 200 characters. | `BrowserAITools.swift` |
| Tool access | Per-action settings, destructive-action defaults, space checks, and private browsing restrictions apply. | `BrowserAITools.swift` |
| Today title context | Page text is limited to 2,000 Apple tokens. Output budget is 64 tokens. Prompt asks for seven words; validator permits 40 words and 1,024 bytes. | `BrowserShellControls.swift`, `BrowserPageFeatures.swift`, `BrowserAIPrompts.swift` |
| Bookmark title | 64 response tokens; seven-word prompt guidance and the shared 40-word/1,024-byte line validation. | `BrowserBookmarkTitleFeature.swift` |
| Chat title | Input excerpts: 2,000 question characters and 6,000 answer characters. Output: 48 tokens, seven-word prompt guidance, 40-word/1,024-byte validation. Fallback title truncates the question to 70 characters. | `BrowserChatTitleFeature.swift`, `BrowserAIChat.swift` |
| Link preview context | On-device: 1,000 Apple tokens. Other providers: first 26,000 characters. Output: 512 tokens and at most five displayed bullets. Prompt requests a 25-word header and 20-word bullets, without enforcing those word counts in validation. | `BrowserAIPageText.swift`, `BrowserPageFeatures.swift`, `BrowserAIPrompts.swift` |
| Page loading | URL request timeout and loader watchdog: 20 seconds. Only permitted HTTP(S) HTML pages are loaded. Text extraction stops beyond DOM depth 200 and excludes hidden/editable/form content. | `BrowserAIPageText.swift` |
| Download naming | Input excerpts: 500 filename, 253 website, 50 file-type characters. Output budget: 128 tokens. Sanitized filename stem truncates to 100 characters. | `BrowserDownloadNamingFeature.swift` |

Provider context windows, subscription quotas, and server model allowlists remain external. The local server source documents the request, image, response, timeout, and process-local quota limits listed above; deployed configuration may differ.

Existing `ai-features.md` and `adding-features.md` describe a 16 MiB prompt cap and a 20 MiB original attachment-file cap. Those caps were not found in the current client validator or attachment reader; the streaming encoded-body cap remains enforced.
