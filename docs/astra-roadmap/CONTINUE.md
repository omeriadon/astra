# Continue Astra browser implementation

This is the single handoff entry point for a new primary agent. The user requested finishing the active work and recording the next resume point. Continue the authorized roadmap; do not restart it or claim the whole browser is complete.

## Start here

- Working directory: `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/07-tabs-spaces`.
- Branch: `astra/roadmap/07-tabs-spaces`.
- Tabs/spaces source checkpoint: `03da6a0a870011aeaaa3c3b12564b5d7427adfa3`; source-review handoff checkpoint: `de86f6c1a88759e8de196acfdf76565cf92b785b`. It is based on cumulative PiP/docs checkpoint `d6be8c0f66d9aa5fbfcf270e6c2120ad7948dc05`. Use this worktree's final documentation close-out checkpoint as the next baseline. It contains reviewed packets **00, 01, 02, 03, 04, 05, 06, 07, 11, 14, 24, 24a, 29**. **Do not reapply them.** Reviewed14 was combined exactly once through baseline `a9ba5cbb38c82dd9c00c480593adaa1b565b37b7`.
- **Thirteen packets are source-reviewed; twenty-four remain.** Packet07's production-model check, Swift source parsing and diff check passed. Xcode MCP transport closed before app diagnostics/build, so its app compile gate is open. No app/runtime checks ran. PiP's Mac build passed; its runtime/provider/iOS gates remain open. Preserve all worktrees and branches.
- Packet12 is being implemented in a separate worktree from `d6be8c0`; it is not reviewed or included in this cumulative branch yet. Resume packet07's required Mac app build once Xcode MCP transport is available, while packet12 continues. After packet12 close-out, dispatch the next unstarted queue item [13-uploads-auth-challenges](tasks/13-uploads-auth-challenges.md). Packet12 is combined exactly once in the later packet08 worktree after its primary review and compiler gate. See [priority-order.md](priority-order.md).

Read [execution.md](execution.md), [README.md](README.md), [dispatch.md](dispatch.md), [contracts.md](contracts.md), and [capabilities.md](capabilities.md), then the selected next packet. Per-packet reports are under [handoffs/](handoffs/). The reports contain exact source changes/check commands and runtime limitations.

The original project is `/Users/omeriadon/Documents/Xcode_App_Library/browser`, branch `release/0.1+3`. The initial snapshot base was `8ba68083157ede8bca2cac8ea01712aebc02f86b`; the original checkout advanced independently to `e04717d` when worktrees were last listed. We did not merge, push, or apply the implementation there. Recheck before any later integration; never assume the original working copy matches this cumulative branch.

## User authorization and constraints

The user explicitly requested all roadmap work, separate worktrees for each packet, and **`gpt-6-luna`** instead of 5.6 Luna. That session authorization overrides the older Browser-specific no-subagent/no-Git rules for this workflow. Use the primary Sol agent for requirements, architecture, review and reporting. Delegate meaningful implementation to one `gpt-6-luna` worker with medium reasoning, or two only for genuinely disjoint reserved files. With collaboration tools, use `fork_turns: "none"`, include full task context, and do not select a fixed-model role that overrides the requested model.

Keep all actual edits/checks in the assigned absolute worktree. Agents share a filesystem and tools may default to the original checkout; pass `workdir` or absolute paths. Workers are not alone; preserve others' edits. Reserve shared-file writes and serialize Xcode workspace/scheme/build mutations. Read the global `~/.codex/AGENTS.md`; never create repository-specific agent instruction files.

- No push, deployment, original-checkout merge, destructive reset/stash or worktree deletion. The user merges later.
- Native/existing mechanisms first. No speculative framework, database rewrite, private API expansion, unrelated refactor or formatting-only change.
- The repository commit hook runs SwiftFormat. **Every checkpoint must bypass it:** `git -c core.hooksPath=/dev/null commit ...`. One initial snapshot commit triggered the hook; a follow-up restored exact original source bytes. Preserve that restoration. Commit messages use simple lowercase phrasing, consistent with inspected history. Commit only bounded implementation/review checkpoints.
- **Never invoke `xcodebuild`.** Use Xcode MCP for required app diagnostics/builds. No app launch, computer-use interaction or hosted tests. Written app checks may be compiled. Pure non-app production-helper checks were permitted and used; preserve source/build versus runtime evidence distinctions. Use Bun for JS/TS. For actual Swift packages, use the required `pipefail`/`xcsift` Swift build/test pipeline.
- Keep verification proportional: no ceremonial full build for a trivial UI-only edit. Data/model/delegate/schema changes do need relevant compiler evidence. Tests must exercise real helpers/models, not assert implementation text or restore deleted historical suites.
- Swift code uses ordinary multiline declarations/assignments. Follow adjacent SwiftUI layouts/pickers/backgrounds. Use `List`/sections, symbol button labels, accessibility labels/identifiers, confirm role with `.glassProminent`, cancel role, small sheet fractions 0.5–0.7 and host-owned matched source/zoom transitions where applicable.
- Existing experimental Web Push bridge/entitlement source was already in the user's snapshot. Preserve it; do not expand private APIs or advertise unsupported public Web Push.

## Completed work to preserve

| Packet | Result / source checkpoint |
| --- | --- |
| 00 baseline | `d1210af`; contracts/capabilities, removed stale references to deliberately deleted hosted test target |
| 01 lifecycle | `7b8ced5`; peek promotion transfers controller without teardown; restored peeks retain session; idempotent cleanup/invalidation and non-destructive pressure policy |
| 02 navigation | `044a925`; centralized restricted/external scheme policy, typed app URLs, corrected host:port ambiguity, throttle/stale ownership guards; selected-tab prompt hook supplied by05; blank-tab ownership follow-ups remain08/17/32, iOS generic external confirmation belongs32 |
| 03 persistence | `e5bb2ba`; local formatv3, startup restore/new-tab/homepage preserves tabs and all workspace organization, shared once-per-process clean/unclean marker, validated window records and future-state preservation |
| 04 private | `49d35738`, `668efe0`, `1d89883d105266a1e30e3fa9ca5f50f35ea6ea54`; session-isolated private toasts for downloads/zoom/external app/export/diagnostic events; private data/services remain per-window and ephemeral |
| 05 permissions | `75905077`, `f1315876`; controller/top-document temporary grants, persistent site decisions, selected active-controller prompts, same-session capture revocation and top-site multiple-download policy; Mac build5.913s passes; see handoff for limits |
| 06 failures/offline | `42a1274`; retained failure requests, one body-free GET/HEAD network-return retry, no closed-controller reload, repeat-crash tracking across reloads; preserves non-idempotent replay restrictions |
| 11 favicons | `948f8fa`; canonical origins, bounded actual requests/bytes/decodes/cache, stale hydration and cancellation checks, weak/bounded request tracking |
| 14 address/search | separate branch source `f63f5b57487034b0a0be9bf53cbc6be6646b2654`, review HEAD `9fa4963eeb3469feaf0425cdd6a1015b7790ea17`; provider/private choices, custom HTTPS templates, keyword shortcuts, bounded suggestions, timestamped portable setting; Mac build20.732s passes before final parser guard, whose real helper checks pass |
| 24 media | `7255d12`; native playback/pause observation, honest scoped HTML-player resume/mute and restore state, bounded detached-node tracking; no full-tab audible/WebAudio/spatial claim |
| 29 sync | `b0fdebf` after `99b26b7`, `c726905`, `4fcb508`; priority repair described below |

Branch hashes in the table refer to their original reviewed branches. Cherry-picked copies have different hashes in this cumulative branch. Read current source and handoffs rather than reapplying historical commits.

## Mandatory local cache / timestamp contract

The user reported `Enter a valid HTTPS sync server URL`, missing settings, and required **all synchronized content to be cached on device and carry last-updated conflict protection**: history, bookmarks, spaces, settings and every other synced entity/metadata scope. This requirement applies to all future packets.

Preserve the current implementation:

1. Local state remains usable without an account/network. Sync starts only after successful hydration. A changed startup placeholder merges complete cached and live local records; failed hydration cannot publish an empty replacement. Blank/homepage startup retains existing tabs/spaces/pins/folders, selecting an added tab.
2. Endpoint normalization accepts case-insensitive HTTPS, omitted scheme, IPv6/valid ports, rejects malformed/credential-bearing/query/fragment configurations and production HTTP, with debug loopback-only HTTP. Session tokens bind to a nonnil canonical endpoint. Endpoint/auth generations are rechecked across awaits; a response from server A cannot be bound/sent to server B.
3. Persisted `modifiedAt`/`favouritesModifiedAt` and selection/order/deletion clocks drive entity-level merges. Missing legacy timestamps are deterministic unknown/past, not freshly stamped on decode. Restored navigation/scroll callbacks compare actual state before advancing freshness. Real title/custom-title/other edits still stamp updates.
4. Timestamped tombstones and history-clear metadata preserve delete semantics, including legacy ID tombstones. A missing tombstone never deletes an unknown-age record. Equal-date winners/order are deterministic; applying a merged setting/reset honors its equal-time winner.
5. Recheck latest local and same-session peer state after network/merge awaits. Peer publication uses the same LWW merge and carries all deletion/update metadata while retaining each window's selection.
6. Portable projection excludes file tabs/bookmarks/memberships, access bookmarks, interaction state and known local-only tombstones. Applying remote data preserves those local records/memberships; same-URL metadata updates retain controller/native back-forward state. Internal tab IDs are deduplicated, with uniqueness assertion.
7. History is selected for sync. Private data is excluded. Register future portable settings/metadata with the timestamp/cache schema; explicitly document device-only exclusions. All local settings still use device storage. Do not revert history to the old local-only policy.
8. Outgoing sync documents are **v3**, reading v1/v2/v3. Local persistence is now **v3** after task03, reading supported legacy versions and rejecting/preserving unknown future formats. Window records and shutdown metadata are separately versioned. Older clients need upgrade for v3 sync. No server edits/deployment occurred; E2EE is still unresolved, not implemented.

Source and tests: `BrowserSync.swift`, `SyncServerAddress.swift`, `BrowserSyncDocument.swift`, `Browser.swift`, persisted model files, `BrowserPersistence.swift`, `docs/astra-roadmap/checks-29-sync.swift`, `checks-29-sync-models.swift`, `checks-03-persistence.swift`. Use reports for full runnable commands.

Evidence about the reported URL error: the exact prior production validation guard rejected uppercase `HTTPS://203.17.177.58:9644` and bare host:port; the new real helper handles both. The source default endpoint was checked anonymously with native TLS: HEAD `https://203.17.177.58:9644/v1/sync` returned HTTP401, TLS verification0. No token was used. The user's actual active URL remains unproven. Read-only sandbox preference checks found local settings/update caches but no explicit string URL. Never dump user defaults, Keychain tokens, page contents or credentials, or edit real app data to test.

## Next work

Historical handoff before the resumed task: packets05 and14 were closed out, and no later packet had started. Original checkout, task branches and worktrees remain intact. No push or original-checkout integration occurred.

Packet24a is source/build reviewed. It adds WebKit-owned main-frame HTML video PiP controls and conservative playback protection. The user-initiated browser action may still be rejected by WebKit/provider activation policy; native site controls remain available. Browser state/controls do not observe iframe PiP, so playing and paused media are conservatively retained/protected. Automatic focus from the system PiP return action is not established; users can explicitly select “Show Picture in Picture Tab.” Runtime PiP, provider/DRM, background/view-detachment and iOS scene/audio behavior remain pending. The minimal Navigation menu action was added ahead of17; it does not complete17.

Packet07 is source complete and primary reviewed. Its standalone production-model check compiles the actual `BrowserSpace` and `BrowserWorkspace` algorithms with small stand-ins for unrelated `BrowserTheme` and `OpenTab` dependencies; it passed. `swiftc -frontend -parse` passed on the changed Browser/model/drag files, and `git diff --check` passed. The Xcode MCP transport closed during entitlement setup and again when the primary opened the packet07 workspace. The primary explicitly stopped further attempts. No packet07 app diagnostics/build or runtime verification occurred; keep the app compile gate open. See [the packet07 handoff](handoffs/07-tabs-spaces.md).

Permission05 follow-ups remain explicit: grants use the top-level document generation, not separate iframe document identity; native non-user-activated popups remain blocked before the delegate; per-origin autoplay is unavailable; download decisions are intentionally top-site scoped and first attempts are per controller. Native OS/capture/iframe/dialog behavior and iOS compilation remain unverified. Audit blank-tab external app prompts and copied-mailto ownership in08/17/32: a new-tab controller may have no mounted WebView/window. These limits are recorded work, not evidence that the affected runtime cases passed.

Packet14's complete source is in `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/14-address-search-config`, branch `astra/roadmap/14-address-search-config`. Its five integration checkpoints, in order, are `23be171834f77b8cc0d556d3df2c53ac19e28d2e`, `cba6b412fd8ce1fba6a829a5422c238d009feb05`, `2a75812f82c6d387aa25421ae35241c321638482`, `f63f5b57487034b0a0be9bf53cbc6be6646b2654`, and `9fa4963eeb3469feaf0425cdd6a1015b7790ea17`. They were combined once into this worktree; production-helper checks passed after the dotted-scheme parser guard. Suggestions are Google/DuckDuckGo only; Bing/custom search works without remote suggestions. Private suggestions require explicit opt-in and remain off by default.

Shared Controller/Browser writes stay serialized. Packet12 is active in its separate unreviewed worktree. The ranked queue and dependency reasons are in [priority-order.md](priority-order.md). Packet31 has required selected scope for independent website Dock apps, as detailed in its task; do not treat it as implemented.

Remaining packets:

- [08-windows-os-restoration](tasks/08-windows-os-restoration.md)
- [09-history](tasks/09-history.md)
- [10-bookmarks-reading-list](tasks/10-bookmarks-reading-list.md)
- [12-downloads](tasks/12-downloads.md)
- [13-uploads-auth-challenges](tasks/13-uploads-auth-challenges.md)
- [15-address-intelligence](tasks/15-address-intelligence.md)
- [16-chrome-find-zoom](tasks/16-chrome-find-zoom.md)
- [17-keyboard-menus](tasks/17-keyboard-menus.md)
- [18-site-data-preferences](tasks/18-site-data-preferences.md)
- [19-start-page](tasks/19-start-page.md)
- [20-security-reputation](tasks/20-security-reputation.md)
- [21-content-blocking](tasks/21-content-blocking.md)
- [22-extensions](tasks/22-extensions.md)
- [23-credentials-browser-auth](tasks/23-credentials-browser-auth.md)
- [25-page-tools-context-drag](tasks/25-page-tools-context-drag.md)
- [26-reader-translation-source](tasks/26-reader-translation-source.md)
- [27-internal-urls](tasks/27-internal-urls.md)
- [28-settings](tasks/28-settings.md)
- [30-profiles](tasks/30-profiles.md)
- [31-macos-automation-webapps](tasks/31-macos-automation-webapps.md)
- [32-ios-integration](tasks/32-ios-integration.md)
- [33-updates-distribution](tasks/33-updates-distribution.md)
- [34-diagnostics-performance](tasks/34-diagnostics-performance.md)
- [35-accessibility-integration](tasks/35-accessibility-integration.md)

These are unimplemented packets, not just verification items. User selected optional product scopes too. The numbered inventory is not the execution order; follow [priority-order.md](priority-order.md). A genuine provider/credential/public-API barrier needs a precise gate report; do not use “optional” as blanket permission to skip implementation that is feasible.

## Next worktree dispatch

Create packet13's worktree from the latest reviewed cumulative commit, including this priority-order checkpoint. Packet12 remains active and must close before packet13 starts. Resolve packet07's Mac app build gate when Xcode MCP transport becomes available. Do not branch from the old original snapshot.

```sh
cd /Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/07-tabs-spaces
baseline_commit=$(git rev-parse HEAD)
task_id='13-uploads-auth-challenges'
git worktree add -b "astra/roadmap/$task_id" "../$task_id" "$baseline_commit"
```

Before dispatch, verify the new worktree is clean and inspect the packet13 packet and source baseline. Packet14 is already included; do not cherry-pick it again. Keep original and task worktrees intact. Packet12's reviewed commits are integrated exactly once into the later packet08 worktree, after its primary review and compiler gate.

Worker prompt: implement the selected packet plus user cache/timestamp contract; give absolute worktree, exact branch/base, prerequisites, reserved files, selected scope and verification. Use `gpt-6-luna`, medium reasoning and no inherited history (`fork_turns: "none"`), with complete task context. Worker writes `handoffs/<packet>.md`, checkpoints with disabled hooks, reports changed files/checks/real gates. Primary reviews actual diffs and regression cases before dependent work.

Independent branches are combined by cherry-picking reviewed commits into a later **task worktree**, retaining all original task branches and leaving the original checkout untouched. Check staged/dirty files before combining; avoid applying another worker's staged edits. No original checkout merge is authorized. Current cumulative24a includes reviewed packet14 through baseline `a9ba5cb`; do not combine packet14 again.

## PiP implementation evidence and limits

Prefer WebKit-owned web video; do not recreate arbitrary webpage media in an app-owned AVPlayer. Apple documents public HTML-video presentation controls: [Adding Picture in Picture to Safari media controls](https://developer.apple.com/documentation/webkitjs/adding_picture_in_picture_to_your_safari_media_controls). Capability-check `webkitSupportsPresentationMode`/`webkitSetPresentationMode` and standard PiP methods per eligible video. API presence is not a passing browser result; handle user-activation, iframe, DRM and provider failures honestly.

Installed SDK inspection found `allowsPictureInPictureMediaPlayback` inside `#if TARGET_OS_IPHONE`; it remains guarded. Task24a now has eligibility/state controls, exact explicit source selection, lifecycle protection and macOS menu controls. Browser eligibility/state inspection is main-frame HTML video only; unknown iframe PiP is covered by protecting playing or paused media conservatively. WebAudio/audible/spatial state is unknown. Spatial HRTF, Atmos and AirPods fixed/head-tracked output remain distinct hardware tests, not implemented audio effects.

## Verification / environment

- Combined baseline03 Xcode build passed in29.643s before03 implementation.
- Startup03 post-correction initially failed before compilation with missing package products. Closing/reopening **only its task workspace** changed IDE state; a fresh My Mac build then passed in25.27s. Do not repeatedly retry unchanged infrastructure failures.
- Privacy04 workspace `workspace-TCrgxqwcPt`, project `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/04-private-browsing/astra.xcodeproj`, `astra` / `My Mac`: build passed20.65s. The final one-line diagnostics notification correction parsed and refreshed Xcode diagnostics with zero issues; no ceremonial full rebuild was run for that line.
- Media24 workspace `workspace-pHwbirs8o4` was closed after its successful build and diagnostics. Its production JS check runs with Bun: `bun checks/media-mute-check.mjs`. No actual web playback ran.
- The last task03 reopened workspace is `workspace-t3MHJjUIwC`. IDs can change: list/open and verify the exact task path before using one. Serialize all Xcode mutations/builds. Preserve original user workspaces (`browser`, `browser-mini-astra`, `browser-new-tab-search`); close only task workspaces opened for your check.
- Existing iOS build blocker: unresolved **Sparkle** import in `BrowserUpdateSheet.swift`; task32/33 must apply platform guards and verify iOS. Do not rerun unchanged iOS builds. Current Mac builds do not prove iOS parity.
- Historical hosted tests, browser fixtures and release helper scripts were deliberately absent from the user snapshot. Task00 removed missing test-target references. Release workflows remain and need reconciliation with absent helper scripts in33. Do not blindly resurrect old suites/helpers as unrelated work; add only selected required assets.
- Current source is not runtime-certified. No app was launched/operated, no hosted test ran. Authenticated multi-device sync, providers, private isolation, navigation, PiP/capture/DRM, mobile scenes, signed updates and accessibility still need later authorized runtime checks.
- Original experimental Web Push is private/entitlement-dependent; native notifications are not a substitute for web push. Sandbox bookmark/Sparkle installer capabilities and signing/notarization are explicit gates. No release was published, no secrets provisioned, no server deployed.

## Close-out status

Thirteen packets are source-reviewed in this cumulative07 branch; twenty-four remain. Packet12 is active on an independent, unreviewed branch. This cumulative07 branch includes packet14 and PiP. Packet07's Xcode app-build gate and all applicable runtime gates remain open. The current continuation checkpoint is the next resume base, not a production release. All edits are isolated from the original checkout. Final reporting must distinguish source-check evidence from compile and runtime/provider/hardware gates and must not claim all37 are finished.

## Latest verification

- Permission05: final Xcode MCP `astra` / `My Mac` build passed in5.913s; zero diagnostics in eight changed production files. Task workspace `workspace-3MHijM2I3R` was closed. Actual production model/policy check passes, including synchronous download reservations, temporary/private non-persistence, legacy migration and future/malformed-data preservation. See `handoffs/05-permissions.md`.
- Search14: Xcode MCP `astra` / `My Mac` build passed in20.732s; zero diagnostics in eight changed Swift files. Task workspace `workspace-l7ivJ1QAez` was closed. Subsequent small dotted-scheme parser correction passed production-helper compilation/checks and source parsing; no ceremonial full rebuild was run. See its separate worktree's `handoffs/14-address-search-config.md` for exact commands.
- No app launch, hosted tests, provider operation, real user-data edits, server changes, pushes, merges or worktree deletion occurred. Both implementation workers finished.
- PiP source checks passed: `bun run checks/picture-in-picture-check.mjs`, the standalone Swift policy check, combined packet14 production-helper checks and the final `astra` / `My Mac` Xcode MCP build (8.871s, zero issues in five changed Swift files). Runtime fixtures were not launched; see [24a handoff](handoffs/24a-picture-in-picture.md).
- Tabs/spaces packet07: `swiftc -o /tmp/astra-tabs-spaces-check astra/Models/Spaces/BrowserSpace.swift astra/Models/Spaces/BrowserWorkspace.swift docs/astra-roadmap/checks-07-tabs-spaces.swift && /tmp/astra-tabs-spaces-check` passed. Swift frontend parsing and `git diff --check` passed. Xcode MCP transport failed before diagnostics/build; do not claim app compilation. No runtime tests ran. See [07 handoff](handoffs/07-tabs-spaces.md).
