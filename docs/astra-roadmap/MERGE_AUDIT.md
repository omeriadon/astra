# Roadmap merge audit — 4 October 2026

This audit compares the completed PR11 merge `3cdb4cbe4d59794a6f23b0d5044d0a6b3603c15c`, the 30 surviving local roadmap refs, and subsequent local commits through `9bf21d266c9b145a13acd6686a70f651b197cd87`. It uses ancestry, patch equivalence, production-file inventories, selected subsystem source inspection, Xcode settings and built-artifact checks. It is not runtime acceptance, and it does not establish that every alternate implementation is merged.

## Confirmed Dock defects and provenance

- The PR11 merge included `AstraWebsiteAppTemplate`, shared-source membership, its dependency and signed embedding in Astra Resources. The target remained present in `6ea7475`.
- Later local commit `9bf21d2` removed those declarations. This is a post-merge project regression, not evidence of lost source in PR11. No production Swift source files were deleted between PR11 and the current committed head.
- PR11 already contained a separate integration defect: the installer wrote `AstraWebsiteAppURL`, while the helper read `AstraWebsiteAppLaunchURL`. The current repair writes both keys.
- PR11 also used Finder custom-icon metadata. A production installer check reproduced signing rejection from resource-fork/Finder detritus. The repair writes a signed ICNS resource instead.
- Recreating the target with Xcode initially introduced generated multi-platform and capability defaults. The audit restored macOS-only support, Hardened Runtime, network, selected/download file access, camera, microphone and location settings from the original helper configuration. Existing entitlement source and main-app signing/Sparkle configuration remain in use.

The helper is restored locally. Add Website to Dock requests creation, launch and reveal; permanent pinning remains macOS Options → Keep in Dock. Neither this audit nor the installer check launched a website app or verified sandboxed installation from the running Astra process.

## Preserved implementation exceptions

These are substantive local branch differences, not merely old branch names. None of their refs or worktrees were deleted by this audit.

| Local branch | Additional work not in the completed merge | Current integration decision/evidence |
| --- | --- | --- |
| `astra/roadmap/22-extensions` | `24f3107`, `2d2728c` and `c7469a6`: expanded ZIP/payload validation, extension identity/update handling and isolated private extension hosting/UI. | The integrated handoff selects WebKit-owned ZIP handling with a 50 MB input ceiling and excludes private extension hosting and update feeds. Private isolation is still the current contract. The additional archive-validation and identity work is preserved but cannot be described as fully merged or proven redundant. |
| `astra/roadmap/26-reader-translation-source` | `7e3d4b0`, `888d044` and `b3aee78`: article/main DOM extraction, native Translation presentation/preferences, alternate source/page-export model; also inherits the extension exceptions above. | The integrated handoff explicitly keeps reader/translation gated and implements bounded inert Current DOM Source using the committed live document. The local alternative remains preserved; it was not silently restored over the selected source-only implementation. |
| `astra/roadmap/31-macos-automation-webapps` | `ad422d7` and `a2a8fd2`: a second `WebsiteAppInstaller`/configuration/settings/helper architecture and `OpenWebsiteAppIntent`. | The integrated `83e9a93` implementation supplies the BrowserWebsiteApp registry/helper/settings/menu architecture and later signing safeguards. It replaces the installer architecture; the optional App Intent is absent from main and preserved locally. The actual installed helper is now restored and tested. |

Cancelled iOS/iPadOS, Watch and fake Profiles work was not reinstated. An old file being absent is not by itself proof of lost functionality when the integrated implementation has a replacement. Conversely, ancestry alone does not prove a divergent branch was fully integrated.

## Local branch inventory

| Branch | Audited head | Classification |
| --- | --- | --- |
| `astra/roadmap/00-baseline` | `d1210af3ef5b` | Head is an ancestor of the completed merge. |
| `astra/roadmap/01-lifecycle` | `7b8ced584d78` | Head is an ancestor of the completed merge. |
| `astra/roadmap/02-navigation-policy` | `044a92516986` | Non-merge patches are equivalent to patches in the completed merge; later integrated edits differ. |
| `astra/roadmap/03-persistence-restoration` | `e5bb2ba77685` | Head is an ancestor of the completed merge. |
| `astra/roadmap/04-private-browsing` | `1c3b55e9c9e8` | Remaining unmatched commits are roadmap/handoff bookkeeping; production work is represented. |
| `astra/roadmap/05-permissions` | `c470518f9f95` | Remaining unmatched commits are roadmap/handoff bookkeeping; production work is represented. |
| `astra/roadmap/06-failures-offline` | `42a1274a4894` | Non-merge patches are equivalent to patches in the completed merge; later integrated edits differ. |
| `astra/roadmap/07-tabs-spaces` | `32b2fc2ebc97` | Remaining unmatched commits are roadmap/handoff bookkeeping; production work is represented. |
| `astra/roadmap/08-windows-os-restoration` | `2486cc1fa82f` | Non-merge patches are equivalent to patches in the completed merge; later integrated edits differ. |
| `astra/roadmap/09-history` | `a9e94778fd51` | Head is an ancestor of the completed merge. |
| `astra/roadmap/10-bookmarks-reading-list` | `c59f6ebaa252` | Head is an ancestor of the completed merge. |
| `astra/roadmap/11-favicons` | `948f8fa1c8e7` | Non-merge patches are equivalent to patches in the completed merge; later integrated edits differ. |
| `astra/roadmap/12-downloads` | `647c3ea33ee5` | Non-merge patches are equivalent to patches in the completed merge; later integrated edits differ. |
| `astra/roadmap/13-uploads-auth-challenges` | `6f3132ca73ea` | Head is an ancestor of the completed merge. |
| `astra/roadmap/14-address-search-config` | `152613c29b85` | Head is an ancestor of the completed merge. |
| `astra/roadmap/15-address-intelligence` | `39e65303ebf7` | Head is an ancestor of the completed merge. |
| `astra/roadmap/16-chrome-find-zoom` | `d9aeeb55e9ce` | Head is an ancestor of the completed merge. |
| `astra/roadmap/17-keyboard-menus` | `32f26ace2348` | Head is an ancestor of the completed merge. |
| `astra/roadmap/18-site-data-preferences` | `062eb5931c3c` | Head is an ancestor of the completed merge. |
| `astra/roadmap/19-start-page` | `cd98a0c68072` | Head is an ancestor of the completed merge. |
| `astra/roadmap/20-security-reputation` | `6d0385273f0f` | Head is an ancestor of the completed merge. |
| `astra/roadmap/21-content-blocking` | `97b0375add43` | Remaining unmatched commits are roadmap/handoff bookkeeping; production work is represented. |
| `astra/roadmap/22-extensions` | `ca4f2c314817` | Additional implementation remains outside the completed merge; see exceptions below. Local ref preserved. |
| `astra/roadmap/23-credentials-browser-auth` | `ea29d26bb066` | Head is an ancestor of the completed merge. |
| `astra/roadmap/24-media` | `7255d12c7df5` | Non-merge patches are equivalent to patches in the completed merge; later integrated edits differ. |
| `astra/roadmap/24a-picture-in-picture` | `d6be8c0f66d9` | Head is an ancestor of the completed merge. |
| `astra/roadmap/25-page-tools-context-drag` | `f35abd3a8431` | Head is an ancestor of the completed merge. |
| `astra/roadmap/26-reader-translation-source` | `da28cd8ea107` | Additional implementation remains outside the completed merge; see exceptions below. Local ref preserved. |
| `astra/roadmap/29-sync` | `b0fdebfc88b9` | Head is an ancestor of the completed merge. |
| `astra/roadmap/31-macos-automation-webapps` | `a92d15443306` | Additional implementation remains outside the completed merge; see exceptions below. Local ref preserved. |

## Verification and limits

- Final Xcode MCP build: `astra` / `My Mac`, success, zero errors, 8.599 seconds. Log: `/var/folders/s_/ms68q0zx137_d7r08rxtnp9w0000gq/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261004-220431.txt`.
- Xcode effective settings confirm build 3 for main and helper, the helper-only `ASTRA_WEBSITE_APP_HELPER` flag, macOS helper platform and `SKIP_INSTALL=YES`.
- Built helper identity, matching version/build, executable and absence of main-app URL handlers passed `checks/website-app-bundle-check.py`; negative self-tests reject a missing helper, wrong identity/build, unsafe or missing executable and inherited URL handlers.
- `Validate Release` now invokes this bundle check on its archived app. This local workflow edit has not been pushed or run in GitHub Actions; no new CI success is claimed.
- Production temporary installer: install, URL metadata, persistence/reload, rename and icon-update signing passed against the rebuilt helper. Original embedded helper strict signature verification passed. Existing user installations were untouched.
- Production checks passed for Chrome package parsing, native content-rule validation with per-site preference compatibility, website-app URL/name/navigation policy, Start Page preferences/projection, and window ownership/transfer/close/private isolation.
- Production JavaScript checks passed for Find count/current/wrap/reset, media activity, mute, hover previews and PiP eligibility/actions.
- An attempted standalone settings-schema check could not import the app's Defaults package. It was not counted as a test pass; settings compiled in the app build. Initial standalone blocking/Start Page commands omitted their production dependencies; reruns with those dependencies passed.
- `git diff --check` passed before this report was added. No commits, pushes, branch deletions, user-data resets or app operation were performed during this audit.

Manual checks remain in [RUNTIME_VERIFICATION.md](RUNTIME_VERIFICATION.md). A source merge, a passing build and package checks do not prove window animation quality, actual Dock launch, provider behavior, sandbox permissions, or the complete roadmap runtime checklist.

## Full packet audit — subsequent pass

The initial branch audit was not enough to establish integration coverage. This pass also checked every one of the 37 roadmap packet definitions, the 33 available handoffs, implementation commit provenance, current feature entry points and shared-service wiring. The execution ledger and original capability ledger are historical documents: queued rows or missing handoffs do not automatically mean source is absent, and old completion labels do not certify runtime behavior.

Every resolvable implementation/checkpoint commit mentioned by the integrated handoffs is either an ancestor of current HEAD or has an exact stable patch equivalent in HEAD. This includes original packet06,08,11,12 commits that were cherry-picked rather than merged by identity. This finding concerns the selected integrated handoffs; it does not include every alternate implementation on the preserved local branches listed above.

### Defects corrected in this pass

- **Diagnostics integration:** `BrowserDiagnosticEventStore` existed without production writers. Navigation/WebContent failure assignments, native/download failure transitions and extension load-error changes now record bounded events. Records use an allowlisted failure kind or a fixed code, not URLs, filenames, page text, extension names or localized error text. The central record boundary rejects private events; navigation recording additionally excludes authentication sessions. Application crash collection remains unimplemented, rather than inferring a crash from an unclean shutdown.
- **Internal route consistency:** settings routes now include Developer and macOS Website Apps. Unknown, empty or missing explicit page values fail closed instead of falling through to generic settings. The trusted/untrusted source boundary is unchanged. This parser is still not registered as an OS URL handler or connected to generic website/address navigation; its integrated handoff explicitly leaves activation gated.
- **Preview cleanup:** memory-pressure cleanup now releases the newer inactive-window mirror image as well as the original preview. This does not hibernate or close the live WebView and does not establish a measured memory/performance improvement.
- **Conflicting checks:** the old navigation check now expects rejected JavaScript and malformed explicit HTTPS input, matching the integrated address policy. The old sync check now expects persisted envelope version3 and packet09's `.distantPast` timestamp for legacy records lacking an update time. Production sync behavior was retained. The window-restoration check now compiles the real production models rather than obsolete substitute model definitions.
- **Stale documentation entry point:** README no longer points to the intentionally removed CONTINUE.md.

### Packet coverage

“Checked” below means source integration inspection and the stated compiler/model evidence. It does not mean browser/runtime acceptance.

| Packet | Current integrated source / wiring checked | Evidence and remaining boundary |
| --- | --- | --- |
| 00 Baseline | App scheme/target cleanup; real source/resources; helper dependency/embedding; cancelled Watch metadata | Xcode `astra` build and helper bundle check passed. Missing historical hosted tests were not fabricated. |
| 01 Lifecycle | Tab/controller teardown, invalidation, peek promotion, hibernate guards, deferred close and memory-pressure cleanup | Shared-owner check and app compile passed; actual WebView identity/teardown/dirty-form/media behavior remains manual. Mirror cleanup corrected above. |
| 02 Navigation | Address parser → controller load/delegates → external-scheme policy and selected-window prompts | Production parser checks passed; restricted schemes remain rejected. Native POST/popup/external-app behavior is manual. |
| 03 Persistence | Startup hydration, shutdown marker, versioned atomic state/backup, preserved unreadable/future snapshots, restoration fallback | Production persistence/recovery checks passed in temporary directories. Keychain/WebKit interaction-state restoration is manual. |
| 04 Private browsing | Independent nonpersistent store, downloads/favicon/permissions/preferences/blocking/toast services; cleanup and persistence/sync exclusions | Permission/owner/model checks and source guards checked. Broad cookie/storage/session isolation remains manual. |
| 05 Permissions | Controller/document/top-origin scoped grants, prompt ownership, revocation, synchronous repeated-download reservation | Production permission suite passed using a disposable defaults suite. Device/iframe/OS permissions and capture are manual; unsupported delegates remain explicit limits. |
| 06 Failures/offline | Controller failure/retry entry points, original request retention, body-free GET/HEAD retry and repeated termination tracker | Production failure checks passed; original implementation patches have exact equivalents. Actual network/process failures remain manual. |
| 07 Tabs/spaces | Stable IDs, workspace membership, close/reopen/archive, pins/folders/reordering, shared-state publication | Workspace helper and owner-transfer checks passed. Home space was not operated on; drag/drop/selection UI remains manual. |
| 08 Windows/restoration | Registry/window records, geometry clamps, queued OS URL/Dock reopen, normal/private lifetime and shared-controller handoff | Real-model restoration and registry checks passed; original patches have exact equivalents. Native windows/animation/monitor behavior is manual. |
| 09 History | Visit recording/title callbacks, deterministic legacy identity, clear/tombstone filtering, UI deletion and backup scrubbing | History policy and persistence checks passed; legacy migration cannot defeat a clear marker. UI and relaunch acceptance is manual. |
| 10 Bookmarks/reading list | Native views/actions, folder/order/read-state edits, JSON/HTML import/export, bounded offline archives and stale capture guards | Production import/archive/durability/concurrency checks passed in temporary directories. Actual WebArchive rendering/capture and sandbox UI are manual. |
| 11 Favicons | Session-scoped origin keys, bounded fetch/decode/cache, hydration/controller guards and sidebar/site icons | Key checks passed; original implementation has an exact equivalent patch. Site fetch/appearance remains manual. |
| 12 Downloads | Delegate destinations, resume/segmented state, preserved header-sensitive WebKit path, quarantine, collision/scoped file operations and sidebar/settings hooks | Production download/file checks passed; original implementation patches have exact equivalents. Native transfers/permissions/resume and AI rename are manual. |
| 13 Upload/auth challenges | Ordered owned website prompts, upload URL scopes, authentication policy and exactly-once completion paths | Authentication policy checks passed; real upload picker/server/provider acceptance remains manual. Client-certificate support remains gated. |
| 14 Address/search configuration | Typed input, engine/private engine/custom templates/keywords, persisted configuration, GitHub toggle and URL display | Production address/search checks passed, including old config decoding and GitHub enabled/disabled behavior. Provider network/focus UI is manual. |
| 15 Address intelligence | Result ranking/deduplication, suggestion cancellation/privacy, history/bookmark/open-tab/action routing and quick-search destination behavior | Production ranking/suggestion checks passed. Rapid UI typing/selection/focus and provider responses remain manual. |
| 16 Chrome/find/zoom | Selected controller bindings, Find focus/count/current/wrap/generation, zoom bounds/reset/per-site hooks | Production zoom/find-generation and actual Find JavaScript checks passed. Native selection/layout/PDF fallback remains manual. |
| 17 Keyboard/menus | Focused target ownership, Control-Tab/IME rules, menu validation, inspector gate, reopen and explicit address prompts | Production keyboard/menu policy checks passed. Keyboard stress and actual menu/responder behavior on the changed build remain manual. |
| 18 Site data/preferences | Canonical origins, scoped services, date-range/grouped clearing UI, same-origin zoom application, local UA/content mode and portable zoom merge | Production site-preference/sync compatibility checks passed. WebKit deletion scope, redirects and live propagation remain manual. |
| 19 Start Page | Module preferences/projection, history/favourite/closed-tab action sources, customization and native view sizing | Production preferences/projection checks passed. Sheet layout and actions remain manual. |
| 20 Security/reputation | Committed navigation security snapshot, certificate summary, site panel, HTTPS-first/GPC/fraud warning and capture UI | Production security/capture presentation checks passed. Actual TLS/provider/reputation/capture behavior remains manual. No fake reputation service added. |
| 21 Content blocking | Bounded native rule source → store compilation/readiness → controller rule attachment → per-site exceptions → settings/private cleanup | Production rule/source/preference compatibility checks passed. Real request blocking, import/update failure and WebKit compilation remain manual. |
| 22 Extensions | Bundled resources, Safari discovery/Chrome import, WebKit contexts, approvals/host/file permissions, enable/remove, toolbar/window/tab adapters and private exclusion | Production package checks passed; app compiles. The separate expanded validation/update/private-hosting implementation remains unincorporated and preserved, as listed above. Compatibility is manual. |
| 23 Credentials/browser auth | Browser authentication session callbacks, current navigation/request ownership, isolated session cleanup and no browser-owned password vault | Production auth-session policy checks passed. Apple sign-in, AutoFill/passkeys/OAuth/client certificates remain provider/manual gates. |
| 24 Media | Controller activity/mute/player actions and sidebar controls; independent audible/video protection and background scheduling | Actual production media/mute JavaScript checks passed. Web Audio, iframe, hardware/output/provider and lag behavior remain manual. |
| 24a PiP | Eligibility/actions, controller state, menus, restoration callback and media/hibernate/close protection | Production policy and PiP JavaScript checks passed. Real PiP entry/exit, provider refusals and background/window lifecycle remain manual. |
| 25 Page tools/context/drag | Focused print/export/share ownership, exclusive writes/quarantine, native macOS menu preservation and download drag-file lifetime | Production export/drag checks passed. Actual share/print/native context menu/drag/sandbox behavior is manual. |
| 26 Reader/translation/source | Current DOM Source reads the owned committed live document and displays inert native text; copy/save routes retain ownership/size limits | Extracted production source-size policy check passed; full viewer compiled. Reader/Translation alternate implementation remains preserved outside main. Native source UI and provider/fidelity gates remain. |
| 27 Internal URLs | Strict namespace/source parser, native page identity/content rendering, private native-page restrictions | Production parser check passed with browser/view boundary fixtures; real types compiled in app. New settings route cases and invalid-value rejection corrected. OS/generic navigation activation remains intentionally absent. |
| 28 Settings | Feature-owned page views, Defaults schema/reset, portable/device-only allowlist, reset through Advanced and Developer grouping | Production schema check passed against the built Defaults package. Reset was not invoked; live propagation and preservation remain manual. |
| 29 Sync | Cached local document, endpoint-bound token transport, timestamp/conflict/tombstone merging, local-only preservation and opaque/future settings handling | Production address/model/persistence suites passed. Actual auth/server/multi-device convergence/E2EE remain gates; no server was changed. |
| 30 Profiles | Spaces remain organization over existing session ownership; no fake profile selector or duplicated credential model | Explicit integrated product gate retained. No profile work reinstated. |
| 31 macOS/website apps | Main menu → registry → signed embedded helper → launch URL/window/settings management; independent generated identity | Helper build/bundle/metadata/signature and temporary install/rename/icon/persistence checks passed. Separate installer/App Intent is preserved outside main. Actual running-app sandbox/install/Dock launch is manual. |
| 32 iOS integration | Existing conditional glue stays in source; no new mobile implementation enabled or tested | Cancelled product scope retained. No iOS/iPadOS or Watch build/runtime claim. |
| 33 Updates/distribution | Sparkle manager/user-driver UI, feed/key/build metadata, release validation/signing helpers and workflows | Validator self-test, built metadata rules and helper checks passed. Production signing/notarization/update installation/publication remain external/manual gates. Local workflow edit has not run on GitHub. |
| 34 Diagnostics/performance | Versioned bounded redacted report, failure event store/writers, private export exclusion, bounded previews and baseline document | Production diagnostic privacy/bounds check passed; missing event writers fixed. Application crash capture and Instruments/performance measurements remain open. |
| 35 Accessibility/integration | Selected controller/session/native page wiring, labels/IDs, hidden inactive mirror hit/accessibility exclusion, reduce-motion paths, progress/toast announcements and acceptance ledger | Full app compiled; 33 standalone checks passed. VoiceOver/focus/contrast/scaling and all real browser/provider/hardware acceptance remain manual. |

### Verification performed in the full pass

- `astra` / `My Mac` Xcode MCP build succeeded with zero errors in 48.967 seconds. Log: `/var/folders/s_/ms68q0zx137_d7r08rxtnp9w0000gq/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261004-221423.txt`.
- Thirty existing standalone production/helper suites passed: navigation, persistence, permissions, offline/failures, workspace, history, history persistence, bookmarks/archives, favicon keys, downloads, HTTP auth, address configuration, address intelligence, find/zoom, keyboard, site-preference/sync models, Start Page, security, native blocking, extension package parser, browser auth, PiP, export, file drag, sync endpoint, sync/persistence, website-app policy, diagnostic privacy/bounds, window ownership and real-model window restoration.
- Three additional suites passed: production internal URL parser with boundary fixtures; extracted production source-size policy; production settings schema linked against Xcode's built `Defaults.o`/module and the real Defaults/site-preference model files. Boundary fixtures do not verify browser UI behavior.
- Five existing production JavaScript checks passed: Find count/current/wrap/reset, media activity, mute, hover URL/corner/deduplication, and PiP.
- Release validator self-test and its metadata rules passed against the built app. Helper bundle positive/negative checks, strict embedded-helper signature verification and the temporary production installer check passed against the changed build.
- Initial standalone compile failures from omitted source dependencies were corrected in the command sets and rerun. The final checks above passed. Stale contract assertions were reconciled explicitly rather than changing the integrated privacy or schema behavior to satisfy them.
- No app was launched or operated, no user space/data was changed, no local branch was deleted, and no commit/push/remote release update was performed in this pass. Build remains 3. These corrections exist locally and have no new GitHub CI evidence.

This establishes source/build/model integration coverage across the roadmap. It does not establish that every optional branch implementation is in main, that every gate is resolved, or that compiled features work at runtime. The preserved exceptions remain substantive and visible above.
