# Task 12: Downloads

Task / selected optional scope: destination folder and Ask Where to Save preferences; accessible byte progress and explicit retry/cancel actions; dangerous-file confirmation before opening known executable/package types. Speed and ETA projections were not added.
Branch / worktree / baseline commit: `astra/roadmap/12-downloads` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/12-downloads` / `d6be8c0f66d9aa5fbfcf270e6c2120ad7948dc05`.
Status: source complete; Xcode app build gated by unavailable MCP transport; sandbox and WebKit runtime behavior pending.
Commit(s), or explicit uncommitted state: `add download destination and recovery handling` (includes this handoff); primary review pending.

Changed files and behavior:

- `astra/Web/Downloads/BrowserDownloadManager.swift`: stages transfers in app-owned storage, then copies into an exclusive final destination under the active security scope. Ask Where to Save uses `NSSavePanel` and retains the selected-file scope through finalization; fixed destinations use a user-selected folder bookmark or the existing Downloads folder capability. Names use WebKit's suggested filename, sanitized and byte-bounded. Folder destinations select collision-free suffixes; file-panel destinations fail safely if another file occupies the chosen path. Quarantine metadata is written to the staged and final file. Failed downloads can retry only when the original request is a body-free GET without Authorization credentials; supported WebKit resume data remains the resume path. Network failures without resume data remove staging bytes. Segmented requests that redirect fall back to WebKit, preserving its redirect prompt. Dangerous executable and installer types require confirmation before opening. Unreadable `downloads.json` is left untouched and future writes are blocked for that manager instance.
- `astra/Web/Downloads/SegmentedDownloadEngine.swift`: any HTTP redirect stops segmented transfer and falls back to WebKit's native download flow.
- `astra/Models/Library/BrowserDownload.swift`: exposes byte totals, status summaries, retry eligibility, safe UTF-8-bounded filenames and shared collision selection. New persisted properties are optional for older records. Selected file and folder bookmarks remain local download metadata.
- `astra/UI/Chrome/DownloadsSidebarView.swift`: shows byte totals and state, accessible cancel/retry actions, and labels completed-record removal separately from deleting a partial download.
- `astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift` and `astra/UI/Settings/BrowserSettingsView.swift`: adds the portable Ask Where to Save toggle and local folder selection in General settings.
- `astra/Storage/BrowserDefaults.swift`: registers the timestamped portable boolean; bookmark data remains outside `syncedSettingNames`.
- `astra.xcodeproj/project.xcproj`: changes `ENABLE_USER_SELECTED_FILES` to `readwrite`. The existing `ENABLE_FILE_ACCESS_DOWNLOADS_FOLDER` is already `readwrite`; no entitlement-file entry changed.
- `checks/checks-12-downloads.swift`: exercises production filename/collision helpers, legacy-record decoding, and quarantine metadata on a temporary file and its copy.

Acceptance cases satisfied, with evidence: path components and invalid filename characters are removed; UTF-8 output names stay at most 180 bytes; collision selection distinguishes existing and reserved names. The model check passed against actual production helpers and decodes a legacy JSON record after removing only the newly optional keys. Source inspection confirms user-selected file access stays on the exact NSSavePanel URL, fixed folder access uses a folder scope, and final copies do not overwrite existing files. Completed-file removal leaves the file in place; private cleanup removes staging data and records. Retry rejects bodies and Authorization credentials, resume uses WebKit resume data, and failed transfers without resume data do not claim they can resume.

Checks run, scheme/destination/workspace and results:

- `swiftc astra/Models/Library/BrowserDownload.swift astra/Web/Downloads/BrowserDownloadedFile.swift checks/checks-12-downloads.swift -o /tmp/astra-checks-12-downloads && /tmp/astra-checks-12-downloads` passed.
- `swiftc -frontend -parse` passed for all changed Swift files and the check source. This is syntax evidence, not app type-check or build evidence.
- `git diff --check` passed.
- Xcode MCP opened the task project as workspace `workspace-oFvJ00OiKD`, scheme `astra`, destination `My Mac`. Documentation search confirmed public user-selected read/write and Downloads folder access capabilities. The `AddEntitlement` Xcode MCP call failed with `Transport closed`; the project already had Downloads-folder read/write configured, so only the documented `ENABLE_USER_SELECTED_FILES=readwrite` setting was changed in the task project. Xcode MCP later became unavailable, so no app build or diagnostics ran. No `xcodebuild` fallback was used.
- No hosted tests, app launch, or downloaded-file launch were performed.

Checks written but not executed: the existing hosted-test target is unavailable by roadmap contract. Xcode app compilation and runtime checks remain pending.

Pending runtime/hardware/provider cases: verify signed sandbox access for Downloads and user-selected folders/files; save-panel cancellation and resumed downloads across relaunch; file bookmarks after rename/move; exact-file collision handling; large-file finalization; WKDownload authentication and resume behavior; redirect confirmation for native fallback; segmented validators/range handling; quarantine and Gatekeeper metadata; dangerous-file prompts; private-window cleanup with two private sessions. iOS continues to save in the app Documents directory; the macOS Ask Where to Save and folder-picker controls are not exposed on iOS.

Migration, compatibility and private-data impact: no cache format version bump. Added record fields are optional and legacy decoding is covered. A failed download-cache read cannot replace the existing unreadable file with an empty snapshot. Download records, destination paths, bookmarks and resume data remain device-only and are not synchronized. `downloadsAskWhereToSave` uses the existing timestamped settings sync path. Private records remain memory-only; incomplete private staging lives under a per-manager temporary directory and is removed at session close. Files explicitly saved by a person remain on disk after private-session cleanup.

Capability gates / unresolved issues: the changed app sources have not been Xcode type-checked or built because the MCP transport closed. Sandbox and security-scoped bookmark behavior must be verified in a signed app. Source checks do not establish WebKit resume, quarantine, security-scope, or alert behavior on device.

Merge prerequisites / follow-up ownership: primary source review and an Xcode MCP app build are required before integration. No `BrowserController.swift` or shared roadmap contract edits were made.
