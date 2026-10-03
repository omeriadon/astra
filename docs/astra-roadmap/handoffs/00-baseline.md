# Task 00 baseline handoff

Task / selected scope: 00-baseline; full user-selected roadmap scope, with unsupported integrations retained as explicit capability gates.

Branch / worktree / baseline commit: `astra/roadmap/00-baseline`; `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/00-baseline`; `051e62ed742a12ae7f25a4e4c4a39fe6eb9d1ffb`.

Status: build verified for the `astra` app target. Runtime and hosted-test acceptance remain pending.

Commit: checkpoint created after primary preparation changes in `README.md`, `dispatch.md`, and `execution.md` were present in the worktree. Those primary-owned files are included unchanged in this checkpoint.

Changed files and behavior:

- `docs/astra-roadmap/contracts.md` records current owners, extension points, and protected normal/private, persistence, WebKit, and lifecycle behavior.
- `docs/astra-roadmap/capabilities.md` records source-backed status and next acceptance steps for Web Push, credentials, client certificates, capture, restoration, required PiP, audible state, spatial audio, blockers, extensions, sandboxed files, and Sparkle.
- `astra.xcodeproj/project.xcproj` removes the missing `astraInfrastructureTests` folder/target/product references.
- `astra.xcodeproj/xcshareddata/xcschemes/astra.xcscheme` removes the stale testable reference.
- The primary's `README.md`, `dispatch.md`, and `execution.md` changes establish the authorized all-packets execution and reviewed-stack workflow. Inventory wording now reflects that release workflow YAML files remain while their `scripts/release/` helpers are absent.

Acceptance evidence:

- Baseline HEAD matched the dispatched commit. Normal windows use shared session services; `BrowserWebSession` creates a nonpersistent store and separate permission/favicon/download services for each private window. `BrowserTab` excludes restoration blobs from private state. `BrowserPersistence` validates versioned state and writes atomically.
- Before correction, Xcode MCP resolved the app and a test target, while the test source directory did not exist. The post-change target list contains only `astra`; the shared `astra` scheme remains available without a testable.
- No prior source finding was treated as a current defect without checking the current source. The 1 October infrastructure ledger is the source baseline for already implemented work; this handoff keeps its runtime limitations separate.
- Xcode lists an `AstraWatch` shared scheme with an empty test action, but the project has no matching Watch target. This unrelated stale buildable reference remains unchanged.
- Source review found a lifecycle issue for task 01: `Browser.promotePeek` adopts `peek.controller`, then `BrowserTab.dismissPeek` calls `stopForClose()` on that same controller before the new tab is configured. This can stop playback/capture and invalidate active document/file state. It is reported for task 01 and not changed here.

Checks run:

- Opened `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/00-baseline/astra.xcodeproj` through Xcode MCP. Workspace `workspace-WEvxzz60cU`, scheme `astra`, destination `My Mac`.
- Baseline app-only `BuildProject` succeeded in 18.7 seconds with no errors.
- After project/scheme edits, Xcode MCP listed one target (`astra`), listed the shared `astra` scheme, and `BuildProject` succeeded in 1.5 seconds with no errors.
- XcodeUpdate could not address `project.xcproj` or the shared scheme through the Xcode project-organization file API. The stale references were therefore removed with a minimal filesystem patch, then verified by Xcode MCP target/scheme discovery and build.
- No tests were added, restored, built, or run. No fixture or missing release helper assets were restored. The committed release workflows were preserved. Astra was not launched.

Pending runtime acceptance: all capability-matrix provider, web-site, platform, hardware, private-isolation, screen-capture, media/PiP, persistence-recovery, and signed-release cases remain unrun as assigned by the project restrictions and owning packets.

Migration, compatibility, and private-data impact: none. The change only removes a test target whose source folder is absent and records contracts/capability evidence. The user's experimental Web Push files and existing normal/private behavior are preserved.

Capability gates / unresolved issues: Web Push currently relies on private selectors and an unavailable private entitlement. The persistent file bookmark and Sparkle installer entitlement were rejected by the available Xcode integration. PiP remains required and unimplemented; investigate validated public WebKit video presentation-mode/DOM actions as well as AVKit. See `capabilities.md` for owners and acceptance steps.

Merge prerequisites / follow-up ownership: no prerequisites. Task 01 owns the peek-promotion lifecycle issue. Later shared-file changes follow the ownership reservations in `dispatch.md`. User retains merge and integration control.
