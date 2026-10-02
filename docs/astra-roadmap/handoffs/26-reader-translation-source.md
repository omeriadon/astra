# 26-reader-translation-source

Task / selected scope: Packet26. Implement the supported view-source path against the current committed live document. Reader extraction and translation remain explicit capability/provider gates because no maintained extraction engine or approved translation provider/privacy contract is selected.

Branch / baseline: `astra/roadmap/26-reader-translation-source`; baseline packet25 HEAD `f35abd3a843142fd9b764415c42dabf95f8b8995`. Packet18 remains an integration prerequisite for any future per-site reader/translation preference work; this source-only implementation does not duplicate packet18.

Status: source implementation complete for Current DOM Source. Local macOS build/runtime verification remains pending.

Commits: source viewer `5178d9cd123c80b2c2d46e9cdfdd5b77a030cdcc`; command routing `724a00575f2417783363550df14d3b4ef2873e18`; export-format comparison `7f3d6d20f3f90bbcdf0abdc318bd7ecb8e9e6b63`; focused policy check `9d82be3667006c872f59c37b3834dd1241d8ea6e`.

Changed behavior:

- The existing page-source command now reads `document.documentElement.outerHTML` from the already committed, authenticated live `WKWebView` rather than issuing a second network request. Ownership checks from packet25 still require the same browser/tab/controller/web view/window/navigation generation before and after the async source read.
- The UI labels the result **Current DOM Source** to avoid claiming it is the byte-for-byte original HTTP response source. POST/authenticated state is therefore not re-requested or leaked to another URL fetch.
- Source is capped at 5 MiB by UTF-8 byte count. Empty/oversized results fail closed with a browser toast.
- The source viewer renders the string as inert selectable SwiftUI text; it is never loaded into a web view and cannot execute. It provides explicit Copy Source and Save Source controls.
- Save uses the existing exclusive-write/quarantine path and strips URL credentials before attribution.
- PDF and WebArchive export behavior remains unchanged.

Verification asset: `checks-26-reader-translation-source.swift` covers empty, boundary, over-boundary and multibyte UTF-8 source-size handling against the production `BrowserSourceDocumentPolicy`. It is left for the user's Mac alongside the app build.

Capability gates:

- Reader mode: no maintained installed/native extraction mechanism has been established in this branch. Adding ad-hoc readability JavaScript would create a fidelity/security maintenance surface, so reader remains gated rather than pretending broad support.
- Translation: no provider, language-detection contract, credentials, disclosure, retention/privacy terms or private-page policy is selected. No page text is sent remotely.
- Syntax highlighting is intentionally omitted; source remains plain inert text.

Pending Mac/runtime cases: compile the macOS target; open source on authenticated pages, redirected pages and large DOMs; navigate/close/switch tabs while capture is in flight and confirm stale results do not appear; verify copy/save and quarantine metadata.

Data/privacy impact: no source is persisted unless the user explicitly saves it. No source content enters history, sync, diagnostics or defaults.

Merge prerequisites: packet25 and packet18 before any later cumulative integration. User-controlled integration only.
