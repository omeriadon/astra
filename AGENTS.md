# Global Xcode restriction

- Never open, invoke, control, build with, run, or otherwise interact with Xcode or any Xcode MCP tool.
- For Xcode projects, limit work to source edits and non-Xcode static inspection. Never use `xcodebuild`.

# Task Group: Passionfruit Apple catalogue data, schemas, UI, and bookmark-service handoff

scope: maintain the local Apple catalogue foundation, independent category schemas, iPad accessories, Fumadocs catalog UI, and separate Vapor/PostgreSQL bookmark API.
applies_to: cwd=/Users/omeriadon/Documents/passionfruit; reuse_rule=recheck branch/worktree and current schemas before edits; data work is local-source-only, while UI and server details apply to their separate listed repositories.

## Task 1: Consolidate catalogue data into independent schemas and validated accessories, success

### rollout_summary_files

- rollout_summaries/2026-08-23T11-20-22-eSsT-passionfruit_data_schema_ui_vapor_handoff.md (cwd=/Users/omeriadon/Documents/passionfruit, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/23/rollout-2026-08-23T19-20-22-01a02e59-a82a-7753-a7f4-185035efb737.jsonl, updated_at=2026-08-24T03:36:10+00:00, thread_id=01a02e59-a82a-7753-a7f4-185035efb737, canonical schemas, data, and accessories validated)

### keywords

- passionfruit, add-data, public/data, data/tmp, data/status, scripts/validate-data.mjs, independent category schemas, Ajv, Apple Pencil, Magic Keyboard, 161 primary devices, 9 accessories, 485 image references, Husky, prettier --write .

## Task 2: Extract and normalize multi-section Apple device data, superseded by Task 1 validation

### rollout_summary_files

- rollout_summaries/2026-08-22T09-44-34-m0XR-apple_product_data_extraction_orchestration.md (cwd=/Users/omeriadon/Documents/passionfruit, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T17-44-34-01a028db-9664-7e13-a6f1-36f8e8d3e04f.jsonl, updated_at=2026-08-23T11:17:02+00:00, thread_id=01a028db-9664-7e13-a6f1-36f8e8d3e04f, initial local extraction and bounded orchestration)

### keywords

- Apple AU DevTools HTML, parse5, .scratch/checkpoints, .scratch/heartbeats, 429 Too Many Requests, accessoryId, lowercase hyphenated IDs

## Task 3: Build the Fumadocs catalog interface and original bookmark-service handoff, partial/success

### rollout_summary_files

- rollout_summaries/2026-08-23T11-20-22-eSsT-passionfruit_data_schema_ui_vapor_handoff.md (cwd=/Users/omeriadon/Documents/passionfruit, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/23/rollout-2026-08-23T19-20-22-01a02e59-a82a-7753-a7f4-185035efb737.jsonl, updated_at=2026-08-24T03:36:10+00:00, UI browser submission remains unperformed; Vapor API verified)

### keywords

- passionfruit-first-ui, data/first-ui, AGENT_HANDOFF.md, Fumadocs, /docs, device-notes, hydration, NEXT_PUBLIC_BOOKMARKS_API_URL, passionfruit-bookmarks-server, PostgreSQL, GET /health, /api/v1/bookmarks, port 8081, superseded by /Users/omeriadon/Documents/server, port 8082

## Task 4: Deliver official Fumadocs catalogue navigation, renamed server API, and PR/data readiness, success

### rollout_summary_files

- rollout_summaries/2026-08-24T03-36-12-8gPa-passionfruit_ui_server_deployment_and_agent_workflow.md (cwd=/Users/omeriadon/Documents/passionfruit, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/24/rollout-2026-08-24T11-36-12-01a031d7-0c0c-7d73-ba70-98f4d1bbb344.jsonl, updated_at=2026-08-24T13:14:08+00:00, thread_id=01a031d7-0c0c-7d73-ba70-98f4d1bbb344, official UI restored; isolated server deployment and data/PR gates passed)

### keywords

- passionfruit-first-ui, Fumadocs Glass, getCatalogPageTree, meta.json, root true, data/first-ui, d92589c, f0dd8e2, af337c1, /Users/omeriadon/Documents/server, passionfruit-server, passionfruit-api.adonis.pt, 127.0.0.1:8082, e214268, /api/v1/auth/me, idempotent deletion, PR #2, ajv, 0024770, /Users/omeriadon/.codex/AGENTS.md, Vercel batching

## Task 5: Research supported Fumadocs Glass top-tab patterns, success

### rollout_summary_files

- rollout_summaries/2026-08-26T12-33-55-8ncq-fumadocs_glass_devices_account_navigation.md (cwd=/Users/omeriadon/Documents/passionfruit, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/26/rollout-2026-08-26T20-33-55-01a03e10-11e6-7401-9fa8-14c2e0b50c0e.jsonl, updated_at=2026-08-26T13:17:05+00:00, thread_id=01a03e10-11e6-7401-9fa8-14c2e0b50c0e, official docs and installed Fumadocs 16.14.5 source/types checked)

### keywords

- Fumadocs, DocsLayout, GlassLayout, tabMode, getLayoutTabs, getCatalogPageTree, root true, docs/research/fumadocs-top-tabs.md, f4fabb2

## Task 6: Replace category header links with Devices and Account navigation, partial

### rollout_summary_files

- rollout_summaries/2026-08-26T12-33-55-8ncq-fumadocs_glass_devices_account_navigation.md (cwd=/Users/omeriadon/Documents/passionfruit, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/26/rollout-2026-08-26T20-33-55-01a03e10-11e6-7401-9fa8-14c2e0b50c0e.jsonl, updated_at=2026-08-26T13:17:05+00:00, thread_id=01a03e10-11e6-7401-9fa8-14c2e0b50c0e, Account MDX placeholders and header restructure committed)

### keywords

- GlassAccountHeader, AccountButton, Devices, Account, bookmarks, settings, content/docs/account/meta.json, ScrollArea, ScrollViewport, ScrollBar, 9d8064c

## Task 7: Make the Glass Devices/Account pill content-sized and unclipped, success with limited verification

### rollout_summary_files

- rollout_summaries/2026-08-26T12-33-55-8ncq-fumadocs_glass_devices_account_navigation.md (cwd=/Users/omeriadon/Documents/passionfruit, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/26/rollout-2026-08-26T20-33-55-01a03e10-11e6-7401-9fa8-14c2e0b50c0e.jsonl, updated_at=2026-08-26T13:17:05+00:00, thread_id=01a03e10-11e6-7401-9fa8-14c2e0b50c0e, focused formatting/diff checks only; final visual/runtime validation unperformed)

### keywords

- GlassAccountHeader, flex-1, shrink-0, clipped tab pill, bunx prettier, git diff --check, 55f8143, bun run types:check, bun run build

## User preferences

- when orchestrating extraction, the user said “you are only the orchestrator,” “limit to 3 agents,” and “do not start background terminals, always foreground exec” -> delegate bounded, non-overlapping work to at most three workers, foreground-poll it, and resume from repo-local checkpoints. [Task 2]
- when the user required “put true tone: true, promotion: false, port: .usbC” and later required each device type be “treated completely separately” -> preserve facts as typed, category-specific fields; do not retreat to universal schemas or free-text summary lists. [Task 1][Task 2]
- when cleaning `.scratch`, the user required raw HTML, rules, status files, canonical data, schemas, images, and provenance to survive -> use explicit manifests and conservative deletion. [Task 1]
- when building the UI, preserve `/`, use `/docs/<category>/<device-id>` with top-level Fumadocs tabs, and nest iPad accessories under iPad. [Task 3]
- when custom navigation broke the layout, the user said to use “the special tab component that fumadocs supplies” and “use the tabs layout provided here” -> use official Fumadocs Glass/Docs layout, tabs, root folders, and page-tree APIs rather than custom navigation components. [Task 4]
- when researching Fumadocs, the user asked to “look through the fumadocs docs” -> check official documentation plus installed package source/types instead of guessing from generic tabs APIs. [Task 5]
- when specifying the header, the user said tabs “shouldnt be all the devices, it should be these: devices ... account,” wanted “bookmarks and then settings under that,” and said to “remove he account thing in the top bar” -> use broad Devices/Account product sections, Account sidebar children, and no duplicate account popover. [Task 6]
- when the supplied screenshot showed the pill, the user said it “shouldnt be full width” and its bottom was clipped -> make the control content-sized and verify complete rounded borders against the screenshot. [Task 7]
- when deploying, the user required “do not go and do anything destructive” and “do not restart the entire server” -> preserve unrelated services with isolated port/process/database and targeted Nginx reloads only. [Task 4]
- when a repository-local instruction file was added, the user corrected: “edit the global agents.md file” -> put cross-repository workflow rules in `/Users/omeriadon/.codex/AGENTS.md`; batch coherent validated Vercel pushes because each push triggers a deployment. [Task 4]

## Reusable knowledge

- Canonical data is `public/data/<section>/<section>.json`; raw Apple HTML is `data/tmp/`; `data/status/` is source-of-truth. Runtime validation is `node scripts/validate-data.mjs`, which uses each category’s schema beside its canonical JSON, not `.scratch/strict/data-model-contract.schema.json`. [Task 1]
- The final recorded data gate passed 12 datasets: 161 primary devices, 9 accessories, 3 additional products, 485 image references, and zero invalid image files. Mac is 53 canonical records (four evidence-backed non-Intel MacBook Pro additions); Apple TV HD and Intel Macs are excluded. [Task 1]
- Apple Pencil has four records at `public/data/other/apple-pencil/apple-pencil.json`; Magic Keyboard has five products and 84 image references. Their group-local schemas passed Ajv and all iPad compatibility IDs resolved. [Task 1]
- Stage category migration as schema-only, then canonical data, then repeated category-specific Ajv validation. Keep IDs lowercase-hyphenated; use repository-relative image paths and retain canonical Apple URLs plus exact local image canvases. [Task 1][Task 2]
- UI worktree is `/Users/omeriadon/Documents/passionfruit-first-ui` on `data/first-ui`; inspect `AGENT_HANDOFF.md` first. Typecheck/build and route matrix passed after replacing invalid nested `dt`/`dd` rendering with valid labelled rows; browser credential submission was not performed. [Task 3]
- Historical handoff used `/Users/omeriadon/Documents/passionfruit-bookmarks-server`, port 8081, and direct auth/bookmark values. Treat those details as superseded by the Task 4 rename/contract unless explicitly working from that archived checkout. [Task 3][Task 4]
- In `/Users/omeriadon/Documents/passionfruit-first-ui`, `src/app/docs/layout.tsx` uses the official Glass layout and `fumadocs-ui/css/generated/glass.css`; `getCatalogPageTree()` augments JSON-backed devices absent from the MDX tree. Add `{ "root": true }` `meta.json` under each primary content folder to scope the sidebar to the active category. [Task 4]
- Detail routes must be detail-only, while category routes retain tables/cards. `d92589c` fixed `CatalogCategory`, `AccessoryCatalog`, and `OtherCatalog`; `bun run types:check`, `bun run build` (217 pages), route/DOM checks, and `git diff --check` passed. [Task 4]
- Renamed backend: local `/Users/omeriadon/Documents/server`, GitHub `omeriadon/server`; deployed API is `https://passionfruit-api.adonis.pt`, PM2 `passionfruit-server`, bound to `127.0.0.1:8082`. Contract `e214268` has wrapped auth/bookmark responses, `/api/v1/auth/me`, PUT/DELETE by category/device, and user-scoped idempotent deletion; health and public auth/CRUD/isolation probe passed. [Task 4]
- `ajv` is required by `scripts/validate-data.mjs`; `ajv-draft-04` was unused and removed in `0024770`. Current recorded validator gate remains 12 datasets, 161 devices, 9 accessories, 3 products, 485 image references, zero invalid references. [Task 4]
- `DocsLayout` supports first-party horizontal tabs through `tabs={catalogTabs}` and `tabMode="top"`; `GlassLayout` accepts tabs but renders a dropdown, so desktop horizontal tabs with Glass need a custom header strip. Derive route-aware tab data from `getLayoutTabs(getCatalogPageTree())`; roots are `root: true` `content/docs/<category>/meta.json`. Do not use ordinary content Tabs for top-level navigation. [Task 5]
- The compact final header uses explicit Devices/Account links in `src/components/auth/GlassAccountHeader.tsx`; Account is a root `content/docs/account/meta.json` with `bookmarks.mdx` and `settings.mdx` children. Fumadocs exports `ScrollArea`, `ScrollViewport`, and `ScrollBar`, but the final fixed two-tab header removes that wrapper because it does not overflow. [Task 6]
- For this two-tab pill, replace `flex-1` with `shrink-0` and remove the unnecessary scroll container to size to content and avoid clipping. Focused `bunx prettier --write src/components/auth/GlassAccountHeader.tsx` and `git diff --check` passed. [Task 7]

## Failures and how to do differently

- Symptom: repeated `429 Too Many Requests`. Cause: excessive parallel workers. Fix: cap concurrency early, foreground-poll, and restart from `.scratch` checkpoints. [Task 2]
- Symptom: universal-schema validation masks category errors or migrations stall with thousands of errors. Cause: category contracts and data changes overlap. Fix: split schema/data ownership, migrate mechanically only from evidence, remove unsupported nulls/legacy shapes, then run category Ajv. [Task 1]
- Symptom: broad Prettier/Husky hooks rewrite canonical JSON or unrelated files. Cause: repository-wide `prettier --write .`. Fix: Husky is removed; format and stage focused paths atomically, inspect cached files, and avoid global formatting. [Task 1]
- Symptom: a route/component exists but catalog UI is still wrong, or auth testing fails. Cause: source-only confidence or assumed API envelopes. Fix: inspect rendered DOM/browser errors and compare client calls with Vapor routes before auth testing. [Task 3]
- Symptom: Fumadocs grid/sidebar is broken or empty. Cause: official sidebar was disabled or nested URL matching removed. Fix: restore default Fumadocs behavior (`f0dd8e2`); do not add explicit device links because they duplicate the page tree (`af337c1`). [Task 4]
- Symptom: initial production release build stalls with partial state. Cause: infrastructure provisioning completed before release build. Fix: resume from the existing database/repo/checkout/environment checkpoints rather than recreating or overwriting them. Store deployment credentials only in restricted external environment files; do not copy legacy PM2 configs containing plaintext secrets. [Task 4]
- Symptom: workers/agents stall or status messages loop. Cause: unbounded research/waiting and stale reporting. Fix: give bounded implementation asks, reassign stalled work, and state a real blocker once. [Task 1][Task 3]
- Symptom: attempting to use ordinary content Tabs or assuming Glass will show horizontal layout tabs. Cause: confusing content tabs, `DocsLayout`, and `GlassLayout` behavior. Fix: use page-tree/layout tabs for `DocsLayout`; implement a custom Glass header only when horizontal desktop tabs are actually required. [Task 5]
- Symptom: final header is claimed to have working Bookmarks/Settings or the Fumadocs scrollbar. Cause: placeholder MDX was mistaken for functional account UI, and the temporary scroll wrapper was removed. Fix: describe account functionality as unimplemented and reintroduce Fumadocs scroll primitives only if tabs can overflow. `devicesHref` falls back to `/docs/ipad` from Account; consider a dedicated Devices landing route if that return destination matters. [Task 6]
- Symptom: code-level clipping fix is treated as browser-verified. Cause: no browser screenshot, `bun run types:check`, or `bun run build` followed final commit `55f8143`. Fix: retain the limited-validation boundary and run those gates before claiming runtime/visual success. [Task 7]

# Task Group: Timetable repository orientation and feature discovery

scope: provide a source-confirmed, categorized inventory of implemented Timetable surfaces and targets; use for orientation, planning, or feature-list requests, not as proof of runtime behavior.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=reinspect current source for feature names, routes, and role visibility; this inventory is source-confirmed and was not exhaustively runtime-tested.

## Task 1: Inventory implemented Timetable app features, success

### rollout_summary_files

- rollout_summaries/2026-08-24T08-59-44-ltN1-timetable_app_feature_inventory.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/24/rollout-2026-08-24T16-59-44-01a032ff-4370-7502-9191-2e1680e496cb.jsonl, updated_at=2026-08-24T09:01:10+00:00, thread_id=01a032ff-4370-7502-9191-2e1680e496cb, read-only source inventory)

### keywords

- Timetable, SwiftUI, iOS, iPadOS, macOS, Mac Catalyst, watchOS, widgets, Live Activities, App Intents, Siri, Today, Week, Planner, friends, grades, administration, system owner, Main/Navigation/AppRouter.swift, TimetableShortcuts.swift

## User preferences

- when the user asked for “a bullet list of all the features of this app” -> provide a categorized, comprehensive inventory rather than a short README summary. [Task 1]

## Reusable knowledge

- Timetable is a multi-target school-timetable app for iOS/iPadOS, macOS via Mac Catalyst, and watchOS; the Watch app is a read-focused companion dependent on iPhone provisioning. It requires OS 26 or later and is optimized for one school’s timetable structure. [Task 1]
- Primary timetable surfaces are Today, Week, and Planner: current/next classes, breaks/free periods/school-out states, editing, calendar events, term dates, pupil-free days, weather, archived events, and timetable comparison. [Task 1]
- Account/sync covers email verification, session restoration, server-backed timetable/profile/settings/calendar/friends/grades/notification sync, iPhone-to-Watch provisioning, sign-out/deletion, offline-aware controls, and sync diagnostics. Friends, grades, notifications, widgets/Live Activities, Shortcuts/App Intents, profiles/settings, and role-gated administration are implemented as distinct feature families. Search representative sources first: `Main/Tabs/`, `Main/Backend/`, `App Intents/TimetableShortcuts.swift`, `Widget/Widget Shared/`, and `Watch/Tabs/`. [Task 1]
- System owners additionally manage administrators, app versions, contributors, profile storage/R2 reconciliation, special badges, development access, and test email; admins manage users, moderation, school content, notifications, email logs, statistics, and font-width testing. [Task 1]

## Failures and how to do differently

- Symptom: a feature inventory is presented as if every surface was manually exercised. Cause: source inspection was mistaken for runtime validation. Fix: describe it as implemented/source-confirmed capability and re-inspect current source before a future inventory. [Task 1]

# Task Group: Timetable SwiftUI/UIKit tab-switch crash investigation and stabilization

scope: audit and harden the iPhone UIKit-backed tab path under rapid switching, including historical fixes, stable controller identity, dynamic Admin visibility, and evidence-aware runtime conclusions.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=reinspect the current `UIKitTabView`/router implementation and test target before reuse; this guidance is specific to the UIKit-backed iPhone shell and iOS 26 tab-bar behavior.

## Task 1: Audit prior fixes and harden rapid UIKit tab switching, success

### rollout_summary_files

- rollout_summaries/2026-08-22T13-29-23-6Nl9-stabilize_uikit_tab_switching_crash.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T21-29-23-01a029a9-6893-7d41-beee-2c396aaa7643.jsonl, updated_at=2026-08-22T13:39:38+00:00, thread_id=01a029a9-6893-7d41-beee-2c396aaa7643, build/diff checks and user rapid-switch logs showed no crash)

### keywords

- UIKitTabView, UITabBarController, MainTab, UIHostingController, CompactAppShell, AppRouter, TabTransitionAnimator, tabBarMinimizeBehavior, Admin visibility, stale callback, f325cf78, 5599096d, b92b56bb, rapid tab switching, cannot add handler to 0 from 0 - dropping, NSURLErrorDomain Code=-999

## Task 2: Diagnose switch-specific crash risks, remove the animator, and repair coordinator identity mapping, success

### rollout_summary_files

- rollout_summaries/2026-08-22T12-46-46-Vmcd-timetable_iphone_tab_crash_diagnosis_and_hardening.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T20-46-46-01a02982-6508-7e40-950b-0b501979b845.jsonl, updated_at=2026-08-22T13:27:36+00:00, thread_id=01a02982-6508-7e40-950b-0b501979b845, source inspection, Xcode builds, commits, and handoff brief completed)

### keywords

- UIKitTabView, CompactAppShell, AppRouter, MainTab, TabTransitionAnimator, tabBarMinimizeBehavior, iOS 26, UIHostingController, updateItems, AppFontDesign, e35451c6, f325cf78, 5599096d, tab-crash-agent-brief.md, _UITabBarVisualProvider_Floating

## User preferences

- when investigating a crash, the user asked to “continue to inspect that tabview until you are satisfied that it will not crash at all” and requested an audit of already-made commits -> inspect current code, relevant history, and stress/runtime evidence rather than only supplying a new patch. [Task 1]
- when the user supplied rapid-switching logs after testing -> treat runtime logs and stress behavior as material evidence in addition to a successful build. [Task 1]
- when the user said “remove the animator” and explicitly kept the minimize-behaviour modifier -> make the narrowest crash-focused change and preserve explicitly accepted behavior. [Task 2]
- when the user asked to “really nitpick” because only tab switching crashed -> focus on switch lifecycle, transition, OS-version, and state interactions rather than generic UI inspection. [Task 2]

## Reusable knowledge

- `f325cf78` removed the unsafe custom `TabTransitionAnimator`, which manually inserted transition views while iOS 26 floating/minimizing tab-bar behavior was active; `5599096d` refreshed coordinator identities but remained positional. [Task 1]
- In `Main/Navigation/UIKitTabView.swift`, map controllers by stable `MainTab` identity, reuse existing `UIHostingController` instances, update tab metadata without routine `rootView` replacement, avoid randomized `hashValue` tags, reject stale callbacks, defer delegate-to-SwiftUI selection writes with a main-actor task, and normalize persisted selections that target hidden tabs. [Task 1]
- Admin visibility can change the tab list, so positional controller/item assumptions are unsafe during that transition. Commit `b92b56bb` implemented the identity-based hardening. [Task 1]
- Validation recorded a successful Timetable Xcode-scheme build, zero diagnostics in `UIKitTabView.swift`, passing `git diff --check`, pushed `b92b56bb`, and user rapid-switch logs with no crash, exception, assertion, termination, or UIKit containment failure. [Task 1]
- On iPhone, `CompactAppShell` selects `UIKitTabView`; wider platforms use native SwiftUI navigation. `UIKitTabView` hosts each tab in a `UIHostingController<AnyView>` containing its own `NavigationStack`. [Task 2]
- The system-font path uses `UIFont.systemFont` with `.monospaced`, `.rounded`, or `.default`; failed `fontDescriptor.withDesign` conversion falls back to the base system font, with no bundled-font lookup or force unwrap. [Task 2]
- The handoff brief is `/Users/omeriadon/Documents/Xcode_App_Library/Timetable/tab-crash-agent-brief.md`; if the issue recurs, collect exact device/iOS and symbolicated frames such as `_UITabBarVisualProvider_Floating`, `tabScreenComponentView`, `UITabBarItem._updateViewAndPositionItems`, or “Can't add self as subview”. [Task 2]

## Failures and how to do differently

- Symptom: build/static review looks clean but cannot prove every rapid-switch runtime path. Cause: the available iOS 26.5.2 physical device was unsupported by the interaction tool. Fix: retain the runtime caveat; if it recurs, obtain the exact device/OS, reproduction steps, and symbolicated stack rather than claiming absolute safety. [Task 1]
- Symptom: repeated `cannot add handler to 0 from 0 - dropping` during rapid switching. Cause: not established; no crash followed. Fix: monitor it as an abnormal system/UI diagnostic, not proof of the original crash. [Task 1]
- Symptom: `NSURLErrorDomain Code=-999 "cancelled"` appears in tab logs. Cause: cancelled tab-scoped requests. Fix: treat as non-fatal unless correlated with an actual failure. [Task 1]

# Task Group: Codex CLI OpenRouter profile repair, Desktop limitation, and reasoning configuration

scope: configure and validate a Codex 0.149.0 OpenRouter CLI profile without storing credentials, distinguish file-based CLI profiles from unsupported Desktop model use, and preserve the unverified reasoning-effort boundary.
applies_to: cwd=/Users/omeriadon/Documents/Codex/2026-08-22/last-login-sat-aug-22-17 with configuration under /Users/omeriadon/.codex; reuse_rule=recheck the installed Codex version, provider schema, and model support before reuse; do not reuse this as proof of Codex Desktop support.

## Task 1: Repair OpenRouter provider and migrate to file-based profile, success

### rollout_summary_files

- rollout_summaries/2026-08-22T09-35-02-8FwO-codex_openrouter_profile_fix_desktop_limit_and_reasoning.md (cwd=/Users/omeriadon/Documents/Codex/2026-08-22/last-login-sat-aug-22-17, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T17-35-02-01a028d2-dd0b-7131-bb45-2e4c6e372726.jsonl, updated_at=2026-08-22T09:44:26+00:00, thread_id=01a028d2-dd0b-7131-bb45-2e4c6e372726, strict config and profile-load validation passed)

### keywords

- Codex 0.149.0, OpenRouter, stealth/ox-alpha, model_providers, OPENROUTER_API_KEY, wire_api = "responses", requires_openai_auth = false, ox_alpha_profile.config.toml, legacy [profiles.ox_alpha_profile], codex --strict-config doctor --summary --no-color, codex -p ox_alpha_profile exec --help

## Task 2: Establish Desktop limitation and reasoning-effort boundary, partial

### rollout_summary_files

- rollout_summaries/2026-08-22T09-35-02-8FwO-codex_openrouter_profile_fix_desktop_limit_and_reasoning.md (cwd=/Users/omeriadon/Documents/Codex/2026-08-22/last-login-sat-aug-22-17, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T17-35-02-01a028d2-dd0b-7131-bb45-2e4c6e372726.jsonl, updated_at=2026-08-22T09:44:26+00:00, thread_id=01a028d2-dd0b-7131-bb45-2e4c6e372726, Desktop unsupported; reasoning syntax unverified)

### keywords

- Codex Desktop, ChatGPT account, invalid_request_error, openrouter/stealth/ox-alpha, model is not supported, model_reasoning_effort, low, medium, high, xhigh, codex -p ox_alpha_profile -c

## User preferences

- after a Codex config parse error, the user asked to “fix it” -> directly repair the configuration and validate the exact invocation rather than only explaining the syntax. [Task 1]
- the user supplied a plaintext API key in the conversation -> never reproduce it; treat it as compromised, recommend rotation, and retain only the `OPENROUTER_API_KEY` environment-variable reference. [Task 1]
- after the Desktop restriction, the user concluded “ok ill just use the cli” -> route this custom model to the validated CLI profile, not Codex Desktop. [Task 2]

## Reusable knowledge

- Define `[model_providers.openrouter]` in `~/.codex/config.toml` with `base_url = "https://openrouter.ai/api/v1"`, `wire_api = "responses"`, `requires_openai_auth = false`, and `env_key = "OPENROUTER_API_KEY"`; never place the key in configuration or memory. [Task 1]
- For `-p ox_alpha_profile`, use `~/.codex/ox_alpha_profile.config.toml` with `model_provider = "openrouter"` and `model = "stealth/ox-alpha"`; do not prefix that profile value with `openrouter/`. Validation that passed: `codex --strict-config doctor --summary --no-color` and `codex -p ox_alpha_profile exec --help`. [Task 1]
- The user-observed Desktop response was `The 'openrouter/stealth/ox-alpha' model is not supported when using Codex with a ChatGPT account.` Sharing config does not establish Desktop support for arbitrary third-party models. [Task 2]
- `model_reasoning_effort = "high"` and the one-session `codex -p ox_alpha_profile -c 'model_reasoning_effort="xhigh"'` are recorded syntax guidance only; the rollout did not write/test it or confirm OpenRouter model support. [Task 2]

## Failures and how to do differently

- Symptom: `--profile ... cannot be used while ... config.toml contains legacy ... [profiles.ox_alpha_profile] config`. Cause: a legacy profile table was added to the base config. Fix: remove it and place overrides in `~/.codex/<name>.config.toml`. [Task 1]
- Symptom: attempting `--profile` with `codex doctor` or `codex debug models`. Cause: those commands do not accept it. Fix: test runtime loading with `codex`, `codex exec`, or `codex -p ox_alpha_profile exec --help`. [Task 1]
- Symptom: Desktop rejects the model with HTTP 400. Cause: ChatGPT-account/Desktop model support restriction. Fix: use the validated CLI profile; do not imply top-level model settings bypass it. [Task 2]

# Task Group: Passionfruit one-time local iPad data extraction requirements

scope: prepare a deliberately simple static iPad dataset extraction from user-supplied Apple DevTools HTML, preserving canonical image URLs and exact Apple image canvases.
applies_to: cwd=/Users/omeriadon/Documents/passionfruit; reuse_rule=use only when the user supplies local HTML under `tmp/`; do not generalize this into a live Apple scraper or reusable ingestion service without new authorization.

## Task 1: Define local HTML extraction workflow and data branch, success

### rollout_summary_files

- rollout_summaries/2026-08-22T08-43-29-DhZA-ipad_html_data_extraction_plan.md (cwd=/Users/omeriadon/Documents/passionfruit, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T16-43-29-01a028a3-a7b5-7352-ab6e-df821f624c26.jsonl, updated_at=2026-08-22T09:05:25+00:00, thread_id=01a028a3-a7b5-7352-ab6e-df821f624c26, requirements and branch prepared; no extractor implementation recorded)

### keywords

- passionfruit, iPad, Apple DevTools HTML, tmp/, public/data/ipad/, apple-compare, image-canvas, transparent-png, local assets, data/ipad, Add iPad info, Next.js 16, Fumadocs

## User preferences

- when the user said “dont overthink it” and clarified a one-time scrape -> implement the smallest local extraction requested; do not introduce browser automation, live scraping, retries, resumability, persistence, or generalized scraper infrastructure. [Task 1]
- when the user said the HTML will be placed in `/tmp` -> inspect only supplied local files and do not fetch Apple’s live compare site for product discovery. [Task 1]
- when the user requested Apple image links plus local copies and emphasized fixed canvas/transparent padding -> retain the canonical URL and matching local asset without cropping, resizing, flattening, or regeneration. [Task 1]
- when the user requested all iPad colours, models, configurations/storage, specifications, and image variants -> make completeness checks explicit across each requested dimension. [Task 1]

## Reusable knowledge

- This is a minimal Next.js/Fumadocs project with no existing scraping infrastructure; intended source and output locations are `tmp/` and `public/data/ipad/`. [Task 1]
- The requested working branch is exactly `data/ipad` (corrected from `codex/add-ipad-info`), and the planned PR title is `Add iPad info`. [Task 1]

## Failures and how to do differently

- Symptom: planning drifts into a durable scraper pipeline. Cause: treating a one-shot local HTML import as a generalized product. Fix: begin with the narrow static dataset workflow and expand only on explicit request. [Task 1]

# Task Group: Passionfruit shared non-aborting repository-wide Prettier Git hooks

scope: maintain simple tracked Git hooks that format the whole Bun repository, stage formatting changes, and continue commits while respecting the requested main-branch delivery path.
applies_to: cwd=/Users/omeriadon/Documents/passionfruit; reuse_rule=recheck current hooks, `package.json`, worktree ownership, and branch/remote before changing them; this behavior intentionally stages all files and is not a generic safe default for unrelated repositories.

## Task 1: Replace Husky with shared native hooks and deliver on main, success

### rollout_summary_files

- rollout_summaries/2026-08-22T08-50-32-oEHv-shared_prettier_hooks_main.md (cwd=/Users/omeriadon/Documents/passionfruit, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T16-50-32-01a028aa-1ee2-7e63-ae55-029bfee23479.jsonl, updated_at=2026-08-22T09:01:33+00:00, thread_id=01a028aa-1ee2-7e63-ae55-029bfee23479, hooks verified, committed, and pushed to main)

### keywords

- prettier, git-hooks, .githooks, Husky, bun, bun.lock, core.hooksPath, pre-commit, pre-push, format-all, git add -A, prettier --ignore-unknown --write ., b2e9d98, main, data/ipad, force-with-lease

## User preferences

- when the user said “no hooks shouldnt abort, they should format the entire repo, re git add everything, and continue the comit” -> use a non-aborting whole-repository formatter that runs `git add -A`; do not stop merely because formatting changed files. [Task 1]
- when the user asked “wtf is husky” -> prefer simple tracked `.githooks` and `core.hooksPath` rather than adding Husky when a framework is unnecessary. [Task 1]
- when the user corrected “it should be from mai and pushed to main” -> verify active branch and requested push target before committing or pushing. [Task 1]

## Reusable knowledge

- `package.json` provides `"format": "prettier --ignore-unknown --write ."` and `"prepare": "git config core.hooksPath .githooks"`; collaborators install the hook path through `bun install`. [Task 1]
- The tracked executable files are `.githooks/format-all`, `.githooks/pre-commit`, and `.githooks/pre-push`. `format-all` runs `bun run format`, warns but continues on formatter failure, then runs `git add -A`. [Task 1]
- Project formatting uses `.prettierrc` tabs with `tabWidth: 2`. Recorded checks included repeated whole-repository formatting, `git diff --check`, `git config --get core.hooksPath` returning `.githooks`, and clean `main...origin/main` after commit `b2e9d98`. [Task 1]

## Failures and how to do differently

- Symptom: Husky hook aborts after Prettier changes files. Cause: the initial implementation contradicted the requested commit flow. Fix: use tracked `.githooks`, continue after format changes, and stage the whole repository. [Task 1]
- Symptom: correct hook implementation reaches `data/ipad` instead of `main`. Cause: branch placement was not checked before commit/push. Fix: confirm branch and target first; the accidental branch commit was restored with a force-with-lease push. [Task 1]
- Symptom: pushes report that `apple-tracker` moved to `omeriadon/passionfruit`. Cause: stale remote URL. Fix: existing remote still pushed successfully, but consider updating it before future remote work. [Task 1]
# Task Group: Timetable, pmstt, and website authentication email-policy consistency

scope: relax school-domain signup restrictions across the SwiftUI client, Vapor API, and website without weakening validated email/security constraints; distinguish uncommitted source work from deployment.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling /Users/omeriadon/Documents/Xcode_App_Library/pmstt and /Users/omeriadon/Documents/timetable-website; reuse_rule=recheck all three current auth surfaces and repository/deployment status before reuse because this rollout left the auth change uncommitted.

## Task 1: Accept any valid email for signup and account-email updates, partial

### rollout_summary_files

- rollout_summaries/2026-08-22T01-06-15-VVq7-cross_project_auth_policy_and_contributor_administration.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T09-06-17-01a02701-0e88-7153-903e-7b55224a79cf.jsonl, updated_at=2026-08-22T05:19:39+00:00, thread_id=01a02701-0e88-7153-903e-7b55224a79cf, source changes validated partly but uncommitted/undeployed)

### keywords

- normalizedEmail, normalizedSchoolEmail, SchoolEmailAddress.swift, AuthController, AccountController, AccountAuthenticationModel, request-code, verify-code-register, /web-api/auth/[action], maxLength={100}, CreateReceivedPassMirror, AddContentRevisionToReceivedPassMirror

## User preferences

- when the user requested “allow any email to sign up” while retaining valid-email and maximum-length constraints -> preserve syntax validation, normalization, the 100-character limit, uniqueness, verification codes, rate limits, and password/code protocol limits rather than broadly weakening validation. [Task 1]
- when asked about the shared account-update validator, the user selected “Signup and updates” -> keep signup and authenticated profile email policy consistent. [Task 1]
- when the user selected pmstt-only production deployment -> do not push website production without renewed authorization. [Task 1]

## Reusable knowledge

- General validation is `normalizedEmail` in pmstt `Sources/pmstt/Functions/SchoolEmailAddress.swift`: trim and lowercase; require a two-part address with dotted domain; reject whitespace; enforce at most 100 characters. The obsolete `normalizedSchoolEmail` added school-domain/firstname-lastname enforcement. [Task 1]
- Trace both `POST /v1/auth/request-code` / `POST /v1/auth/verify-code-register` in `AuthController.swift` and `AccountController.updateAccount`; leaving the latter on `normalizedSchoolEmail` creates inconsistent signup versus profile updates. SwiftUI entry is `Main/Backend/AccountAuthenticationModel.swift`; website auth UI is `src/app/login/page.tsx`, proxied by `/web-api/auth/[action]`. [Task 1]
- The recorded implementation swapped backend calls to `normalizedEmail`, removed the SwiftUI “Use your school email address” error, changed the website label to `Email address`, added `maxLength={100}` to email/password, and added `testNormalizedEmailAcceptsNonSchoolAddressesAndRetainsValidationLimits`. [Task 1]

## Failures and how to do differently

- Symptom: `swift test` fails before test execution with `cannot find 'CreateReceivedPassMirror' in scope` and `cannot find 'AddContentRevisionToReceivedPassMirror' in scope` from `Tests/pmsttTests/MigrationTests.swift`. Cause: pre-existing missing migration-test symbols. Fix: report `swift build` separately and do not claim a green suite until that baseline is repaired. [Task 1]
- The auth implementation was not committed or deployed in the visible rollout; before resuming, inspect each repository status and the production remotes. Preserve pre-existing website landing-page edits and unrelated Xcode-generated `Special/Localizable.xcstrings`. [Task 1]

# Task Group: Timetable contributor administration across SwiftUI, pmstt, and website

scope: system-owner contributor CRUD/reorder parity and website System Administration navigation.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling pmstt and timetable-website checkouts; reuse_rule=reuse the established system-owner contract and route patterns only while the named endpoints and navigation structure remain current.

## Task 1: Add SwiftUI contributor editor and move website entry to System Administration, success

### rollout_summary_files

- rollout_summaries/2026-08-22T01-06-15-VVq7-cross_project_auth_policy_and_contributor_administration.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T09-06-17-01a02701-0e88-7153-903e-7b55224a79cf.jsonl, updated_at=2026-08-22T05:19:39+00:00, thread_id=01a02701-0e88-7153-903e-7b55224a79cf, builds/checks passed; commits pushed to GitHub only)

### keywords

- AboutController, /v1/administration/about-contributors, /order, AboutContributor, AdministrationAboutContributorsView, AdministrationService, AdministrationRoute.aboutContributors, systemOwner, AdminAboutContributorsEditor, e38c924, f832b25

## User preferences

- when the user clarified “you need to add it to the swiftui app for admins too” -> deliver a real SwiftUI admin route/editor, not website-only support. [Task 1]
- when the user said “move it to the system admin section not the admin section” -> place privileged contributor management in the system-owner-only System Administration grouping. [Task 1]

## Reusable knowledge

- pmstt `Sources/pmstt/Controllers/AboutController.swift` owns public read-only `GET /v1/about` and system-owner-protected contributor GET/POST/PUT/DELETE at `/v1/administration/about-contributors`, plus PUT `/order`. [Task 1]
- SwiftUI surfaces: DTOs in `App Shared/Networking/AccountDTOs.swift`; methods/endpoints in `Main/Backend/AdministrationService.swift`; `AdministrationRoute.aboutContributors` with compact/wide mappings; editor at `Main/Tabs/Administration/AdministrationAboutContributorsView.swift`. The view has server-backed loading, add/edit/delete, optimistic reorder rollback, confirmation, accessibility labels, and sheet zoom transitions; link visibility is `authority == .systemOwner`. [Task 1]
- Website navigation is `src/app/administration/page.tsx`, section rendering is `src/app/administration/[section]/page.tsx`, and the existing editor is `src/components/administration/AdminAboutContributorsEditor/AdminAboutContributorsEditor.tsx`. The row move changes placement, not the editor. [Task 1]
- Validation evidence: Xcode `The project built successfully.`; website Prettier, `npx tsc --noEmit --pretty false`, `git diff --check`, and `npm run build` passed. SwiftUI `e38c924` and website `f832b25` were pushed to GitHub `origin`; neither production remote was deployed. [Task 1]

## Failures and how to do differently

- Symptom: Prettier fails on `src/app/administration/page.tsx`. Fix: run `npx prettier --write src/app/administration/page.tsx` before the final type/build gate. [Task 1]
- `npm run build` can modify tracked `next-env.d.ts` and generate `tsconfig.tsbuildinfo`; restore the tracked generated-file change and remove the cache artifact before committing. An `origin` push is not a production deployment. [Task 1]

# Task Group: Timetable palette lookup from project sources

scope: answer color-value questions by locating actual SwiftUI definitions/usages.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=re-search current source for palette changes rather than treating these values as a global design-token contract.

## Task 1: Identify commonly used brown colors, success

### rollout_summary_files

- rollout_summaries/2026-08-22T01-06-15-VVq7-cross_project_auth_policy_and_contributor_administration.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T09-06-17-01a02701-0e88-7153-903e-7b55224a79cf.jsonl, updated_at=2026-08-22T05:19:39+00:00, thread_id=01a02701-0e88-7153-903e-7b55224a79cf, source lookup)

### keywords

- #D1B38C, #997554, Color.brown, OnboardingBackground.swift, SettingsView.swift, AboutView.swift, TimetableView.swift, FriendDetailView.swift

## User preferences

- when the user asked for two brown colors “i use ehre alot” -> search actual project definitions/usages instead of inventing approximate colors. [Task 1]

## Reusable knowledge

- Recurring warm tan: `#D1B38C` from `Color(red: 0.82, green: 0.70, blue: 0.55)`; medium brown: `#997554` from `Color(red: 0.60, green: 0.46, blue: 0.33)`. Semantic `Color.brown` also appears in settings, timetable, friends, and grades surfaces. [Task 1]

# Task Group: Timetable project identity verification and focused wrong-project reverts

scope: prevent edits in a sibling/related Xcode project and recover a rejected commit without disturbing other work.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=apply across related checkouts: confirm repository, target, and requested surface before any edit; commit IDs are historical only.

## Task 1: Revert incorrect About gradient work and return the original request, success

### rollout_summary_files

- rollout_summaries/2026-08-22T05-32-41-9OtF-wrong_project_about_gradient_reverted.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T13-32-41-01a027f4-fa67-7e70-a203-cd81e521a0ef.jsonl, updated_at=2026-08-22T05:42:15+00:00, thread_id=01a027f4-fa67-7e70-a203-cd81e521a0ef, wrong-project commit reverted and pushed)

### keywords

- wrong-project, project-verification, AboutView, gradient-background, pointer-interaction, git revert, dce0cfc7, 6e8b1a33, git diff --check, origin/main

## User preferences

- when the user said “you are working in teh wrong project” -> verify the exact intended repository/project before editing, especially where related Xcode projects coexist. [Task 1]
- when the user asked to “revert these background things you did, and then give me back teh same prompt i gave you” -> make a focused revert, verify the worktree and push, then reproduce the original wording rather than continuing implementation. [Task 1]

## Reusable knowledge

- The rejected implementation touched `Main/Navigation/AppRouter.swift`, `Main/Navigation/WideAppShell.swift`, `Main/Tabs/Settings/AboutView.swift`, and `Main/TimetableApp.swift`; it was `dce0cfc7` despite a successful Xcode build. `git revert --no-edit dce0cfc7` produced `6e8b1a33`; `git diff --check` passed and the revert reached `origin/main`. [Task 1]
- Related skill: `skills/timetable-change-verify-loop/SKILL.md`. [Task 1]

## Failures and how to do differently

- A successful build does not establish task success: confirm repository/project identity and target first, then perform runtime visual verification for UI changes. [Task 1]

# Task Group: Timetable website About gradient behind app chrome and pointer interaction

scope: page-scoped About gradient layering behind toolbar/sidebar/content while retaining cursor-driven interaction through foreground surfaces.
applies_to: cwd=/Users/omeriadon/Documents/timetable-website; reuse_rule=apply only to the requested page and recheck current AppShell/GradientBlinds layering before reuse.

## Task 1: Make the About gradient global to that page and interactive, success

### rollout_summary_files

- rollout_summaries/2026-08-22T05-54-52-jNpw-about_gradient_behind_app_chrome.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T13-54-53-01a02809-4bb1-7c63-ae31-9d50a880924a.jsonl, updated_at=2026-08-22T05:59:31+00:00, thread_id=01a02809-4bb1-7c63-ae31-9d50a880924a, browser interaction verified; full build not evidenced)

### keywords

- AboutEditor, AppShell, GradientBlinds, pointer-events, window pointer tracking, layout.module.css, AboutEditor.module.css, tsconfig.tsbuildinfo, 6f2a70d, put about gradient behind app chrome

## User preferences

- when the user asked for “this one page” and named “the toolbar, the sidebar, everything” -> keep the visual change scoped to the requested page, while placing the gradient behind all of that page’s app chrome. [Task 1]
- when the user said foreground About content inhibited cursor interaction -> verify interaction over content and sidebar, not only exposed background. [Task 1]

## Reusable knowledge

- Relevant surfaces are `src/app/layout.module.css`, `src/components/AppShell/AppShell.tsx`, `src/components/GradientBlinds.jsx`, and `src/components/settings/AboutEditor/AboutEditor.module.css` / `AboutEditor.tsx`. Make About shell/content transparent while retaining a usable foreground sidebar. [Task 1]
- Move pointer tracking to the window level when foreground content intercepts events intended for the gradient. Local browser verification covered full-viewport appearance and movement over sidebar/content. `6f2a70d put about gradient behind app chrome` was pushed and `main` ended synchronized with `origin/main`. [Task 1]

## Failures and how to do differently

- Remove generated `tsconfig.tsbuildinfo` before staging. Browser/static checks do not prove a full production build; state that boundary explicitly when no complete build output is recorded. [Task 1]

# Task Group: Timetable SwiftUI onboarding calendar-import skip action

scope: add an explicit, non-confirming opt-out to calendar import while preserving intentional DEBUG progression and narrow commit boundaries.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=recheck the current onboarding progression contract before reuse; this skip behavior is validated in the named checkout.

## Task 1: Add small red clear-glass “Skip Import” action, success

### rollout_summary_files

- rollout_summaries/2026-08-22T01-43-43-Fui0-add_calendar_import_skip_action.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/22/rollout-2026-08-22T09-43-43-01a02723-5a9e-76b0-b968-e92cd4d8e79c.jsonl, updated_at=2026-08-22T01:55:38+00:00, thread_id=01a02723-5a9e-76b0-b968-e92cd4d8e79c, built, committed, and pushed)

### keywords

- CalendarImport.swift, CalendarImportView, OnboardingPageContext, Skip Import, canSkipImport, canAdvance, DEBUG, .buttonStyle(.glass), a692363, Special/Localizable.xcstrings, commit hook

## User preferences

- when the user corrected “no the debug bypass is on purpose.” -> preserve explicitly intentional DEBUG-only progression rather than treating it as a bug. [Task 1]
- when the user requested “a small red button (clear glass but the text is red) called skip import,” “dont show an alert to confirm that,” and placement “at the bottom, like the no notifications button” -> match existing onboarding secondary controls and do not add confirmation UI. [Task 1]

## Reusable knowledge

- `Main/Views/Onboarding/Views/CalendarImport.swift` owns the wrapper and `OnboardingPageContext`; `canSkipImport` is false while import runs, true initially/after failure, and remains false on success. Skip calls `context.configure(canAdvance: true, isWorking: false, statusMessage: "Calendar import skipped.")`. [Task 1]
- The control is `.buttonStyle(.glass)`, `.foregroundStyle(.red)`, `.controlSize(.small)`, with accessibility hint `Continues without importing your timetable`. `a692363` built successfully and was pushed. [Task 1]
- Release import failure normally leaves `canAdvance` false; the explicit skip is the intended opt-out. Successful import awaits `ServerSyncCoordinator.shared.saveOwnerTimetable(updatedSubjects)` before reporting success. [Task 1]

## Failures and how to do differently

- Symptom: a narrow commit captures localization changes. Cause: the SwiftFormat hook modified pre-existing `Special/Localizable.xcstrings`. Fix: inspect `git show --name-status HEAD` after hooks, restore unrelated paths, then amend narrowly; the validated amend used `--no-verify`. [Task 1]

# Task Group: Timetable website testing page coverage, Base UI composition, and CSS token/theme cleanup

scope: audit the `/testing` surface against shared components and declared fonts, use Base UI compound components correctly, and clean CSS tokens without claiming theme runtime wiring from static checks.
applies_to: cwd=/Users/omeriadon/Documents/timetable-website; reuse_rule=recheck current component exports, token consumers, and root theme state before reuse; keep page-local CSS ownership. [ad-hoc note]

## Task 1: Expand `/testing` shared-component coverage and repair `MenuGroupContext`, partial

### rollout_summary_files

- rollout_summaries/2026-08-21T09-58-05-SoV2-expand_testing_page_and_fix_menu_group_context.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/21/rollout-2026-08-21T17-58-05-01a023c1-9a13-7af0-b84a-d6e1db322600.jsonl, updated_at=2026-08-21T10:09:13+00:00, thread_id=01a023c1-9a13-7af0-b84a-d6e1db322600, coverage pushed; menu fix unverified/uncommitted)

### keywords

- /testing, src/components/ui, ProfilePicture, Symbol, SettingToggle, DropdownMenuLabel, DropdownMenuGroup, MenuGroupContext is missing, MenuPrimitive.GroupLabel, port 3000, Playwright default export, 5b97d37

## Task 2: Render all declared fonts and multi-open accordion demos, success

### rollout_summary_files

- rollout_summaries/2026-08-21T11-39-56-PiAV-testing_page_fonts_and_multi_open_accordions.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/21/rollout-2026-08-21T19-39-56-01a0241e-d8fe-7603-ba43-baea58cd74e1.jsonl, updated_at=2026-08-21T11:45:58+00:00, thread_id=01a0241e-d8fe-7603-ba43-baea58cd74e1, build passed and changes pushed)

### keywords

- declaredFonts, fontSizes, SF Pro Display, SF Mono, SF Rounded, SF Pro, SF Pro Expanded, Accordion multiple, according.module.css, 29ae3bb, 7a34785, 3a37012

## Task 3: Clean CSS design tokens and add unverified light-mode CSS, success/partial

### rollout_summary_files

- rollout_summaries/2026-08-21T12-10-28-fIBI-css_token_cleanup_and_light_mode.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/21/rollout-2026-08-21T20-10-28-01a0243a-cddf-7e30-a173-c681a165fdca.jsonl, updated_at=2026-08-21T12:35:51+00:00, thread_id=01a0243a-cddf-7e30-a173-c681a165fdca, token cleanup pushed; theme switching unverified)

### keywords

- design-tokens.css, globals.css, CSS variables, --ds-color-text-accent, --ds-drawer-blur, --font-heading, ThemeSettingsSync, className="dark font-sans", .light, 8209677, rg -- pattern

## User preferences

- when the user asked to “go through all of the shared components and just add it to [the testing page]” -> audit the entire shared component tree and expose missing modules, variants, and compound parts rather than a few examples. [Task 1]
- when the user supplied `MenuGroupContext is missing` -> make the narrowest composition fix against the reported runtime symptom. [Task 1]
- when the user asked for “all the fonts i declare,” then “at multiple sizes please,” and “put each one in accordions” with multiple panels open plus a demo -> enumerate every declared face, show explicit size variants, and make every section independently expandable with a nested component demonstration. [Task 2]
- when the user asked to “delete all the vars that arent used,” “preferably dont create new ones,” “dedupe the vars,” “clean up the naming,” and keep token comments split -> delete/reuse established semantic tokens and retain clear token-group comments. [Task 3]

## Reusable knowledge

- Shared modules live in `src/components/ui`; reusable controls include `ProfilePicture`, `Symbol`, and `SettingToggle`. The coverage change is route-local to `src/app/testing/page.tsx` and `src/app/testing/page.module.css`. [Task 1]
- `DropdownMenuLabel` wraps Base UI `MenuPrimitive.GroupLabel`: it must live inside `DropdownMenuGroup` with grouped items, not directly under `DropdownMenuContent`. [Task 1]
- `src/app/globals.css` declares SF Pro Display, SF Mono, SF Rounded, SF Pro, and SF Pro Expanded. The testing page uses `declaredFonts` and `fontSizes = [12, 18, 28, 40]`. Base UI allows multi-open panels through `<Accordion multiple>`; the tracked stylesheet is intentionally `src/components/ui/according.module.css`. [Task 2]
- Token cleanup replaced `--ds-color-text-accent` with `--ds-color-accent`, sidebar/overlay blur with `--ds-drawer-blur`, and `--font-heading` with `--ds-font-body`; it changed token references only in sensitive Sidebar/toolbar surfaces. `.light` overrides exist, but `layout.tsx` still hardcodes `dark` and `ThemeSettingsSync` does not apply a theme class. [Task 3]

## Failures and how to do differently

- Symptom: the menu label throws `Base UI: MenuGroupContext is missing`. Cause: `DropdownMenuLabel` lacks a valid group context. Fix: move it into `DropdownMenuGroup`, then load `/testing`, open the menu, and confirm visible `Menu controls` with no page error. The applied fix had no completed browser/format/commit verification because Playwright failed with `The requested module './index.js' does not provide an export named 'default'` and the follow-up was aborted. [Task 1]
- Symptom: a pre-existing accordion cannot build. Cause: `accordion.tsx` imports nonexistent `./accordion.module.css`. Fix: use the tracked misspelled `./according.module.css`; run Prettier before validation to repair JSX indentation drift. [Task 2]
- Symptom: a token audit gives `unrecognized flag` or `No such file` noise. Cause: `rg` receives glob/pattern arguments in the wrong order or treats a `--` token name as an option. Fix: put `--glob` before the pattern and use `rg ... -- pattern`. Static checks do not prove light mode: wire root class/theme state and visually test the cascade before calling support complete. [Task 3]

# Task Group: Timetable website SwiftUI/Vapor parity audit and incremental feature slices

scope: Continue the requested full website parity effort without claiming completion from code/build checks; preserve system components, global CSS, Sidebar boundaries, and unrelated dirty landing-page edits.
applies_to: cwd=/Users/omeriadon/Documents/timetable-website; reuse_rule=use the SwiftUI app and sibling pmstt server as implementation references when parity is requested; verify live browser behavior separately from static/build evidence.

## Task 1: Audit parity and ship verified comparison, clock, location, and friend-status slices, partial

### rollout_summary_files

- rollout_summaries/2026-08-21T13-30-43-dAbn-timetable_website_swiftui_parity_audit_incremental_slices.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/21/rollout-2026-08-21T21-30-43-01a02484-472d-70b3-a056-4e0ee44dde19.jsonl, updated_at=2026-08-21T15:24:11+00:00, thread_id=01a02484-472d-70b3-a056-4e0ee44dde19, parity objective remains incomplete)

### keywords

- full app parity, system components, global CSS, Sidebar, SwiftUI, Vapor, friendSchedule.ts, AboutController, v1/about, 9514231, 2bae0c1, dac565a, 21a3b61, c38b498, port 3001

## User preferences

- when the user required “full app parity and consistency,” reuse existing components where possible, make no changes to system components/global CSS, and verify parity requirement-by-requirement rather than treating a passing build as completion. [Task 1]

## Reusable knowledge

- Use `/Users/omeriadon/Documents/Xcode_App_Library/Timetable` as the SwiftUI reference and `/Users/omeriadon/Documents/Xcode_App_Library/pmstt` for Vapor contracts. Website contributor work routes through `v1/about` and `v1/administration/about-contributors`; Vapor owns `Sources/pmstt/Controllers/AboutController.swift`. [Task 1]
- Verified slices: class comparison `9514231`; debug-adjusted friend and date-editor clocks `2bae0c1`/`dac565a`; browser location status with SwiftUI radii 225 m, 1.5 km, 3.5 km `21a3b61`; friend current/next/free/school-out state `c38b498`. Friend schedule logic was being consolidated in `src/features/timetable/friendSchedule.ts`, but final commit evidence is absent. [Task 1]
- The verified static gates were `git diff --check`, `npx tsc --noEmit --pretty false`, and `npm run build`; website `origin` is GitHub, and `production` must not be pushed without explicit need. [Task 1]

## Failures and how to do differently

- Symptom: parity is described as complete after incremental commits. Cause: browser runtime was unavailable and the large requirement set remained active. Fix: resume the audit from missing SwiftUI features and server contracts; require live DOM/screenshot checks before calling interactive parity complete. [Task 1]
- Symptom: browser checks hit the wrong server. Cause: port 3000 was occupied and dev server selected 3001. Fix: determine the actual listener before browser inspection. Preserve generated `next-env.d.ts`/`tsconfig.tsbuildinfo` and unrelated landing-page edits separately. [Task 1]

# Task Group: Timetable website repository workflow, routing, CSS ownership, and development tooling

scope: Use Bun/tab formatting, orient the Next.js repository, keep route and CSS ownership explicit, repair known Turbopack/CSS failures, and bundle dirty worktree changes safely.
applies_to: cwd=/Users/omeriadon/Documents/timetable-website; reuse_rule=checkout-specific commands/configuration are safe while `bun.lock`, `.prettierrc`, Next.js routing, and the stated remotes remain present; inspect current source before applying old UI conclusions.

## Task 1: Configure whole-codebase Prettier tabs, success

### rollout_summary_files

- rollout_summaries/2026-08-19T02-21-38-vUri-configure_prettier_tabs_with_bun.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T10-21-38-01a017d2-fcd9-7d40-8935-2ca6afb85ff4.jsonl, updated_at=2026-08-19T02:24:35+00:00, thread_id=01a017d2-fcd9-7d40-8935-2ca6afb85ff4, pushed b6a40a9)

### keywords

- bun.lock, bun add --dev prettier, bunx prettier --write ., bun run format, .prettierrc, useTabs, tabWidth, git diff --check, b6a40a9

## Task 2: Orient repository and configure local Markdown agent workflow, success

### rollout_summary_files

- rollout_summaries/2026-08-19T12-02-16-d7og-timetable_website_folder_inventory.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T20-02-16-01a019e6-9329-7bc1-bc44-b9d5efbf4694.jsonl, updated_at=2026-08-19T12:05:35+00:00, thread_id=01a019e6-9329-7bc1-bc44-b9d5efbf4694, read-only inventory)
- rollout_summaries/2026-08-19T11-39-58-9Nvj-configure_matt_pocock_skills_local_markdown.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T19-39-58-01a019d2-29a9-7b73-af21-521703a98251.jsonl, updated_at=2026-08-19T11:45:13+00:00, thread_id=01a019d2-29a9-7b73-af21-521703a98251, pushed db8e577)

### keywords

- src/app, src/components, src/features, src/lib, public/icons, deploy, AGENTS.md, .scratch, local-markdown, docs/agents, db8e577

## Task 3: Split dedicated routes and page-owned styles, success

### rollout_summary_files

- rollout_summaries/2026-08-19T13-24-21-58Jt-timetable_route_split_and_page_css_ownership.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T21-24-21-01a01a31-b788-7792-90d0-409a5581300b.jsonl, updated_at=2026-08-19T13:47:33+00:00, thread_id=01a01a31-b788-7792-90d0-409a5581300b, build and push succeeded)
- rollout_summaries/2026-08-19T14-01-47-bXC2-split_monolithic_css_styles_by_feature.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T22-01-47-01a01a53-fea9-7e51-99b1-284a70e787ca.jsonl, updated_at=2026-08-19T14:15:42+00:00, thread_id=01a01a53-fea9-7e51-99b1-284a70e787ca, static audit only)

### keywords

- /today, /week, /planner, SessionGate, useDashboard, resetDashboardCache, page.module.css, timetable.module.css, TimetableRoute.module.css, IOSScreen.module.css, 879f8bd, c1dc41a, 728a58b

## Task 4: Repair Turbopack HMR and bundle existing changes, success

### rollout_summary_files

- rollout_summaries/2026-08-19T12-59-43-nO8w-turbopack_hmr_panic_fixed_by_disabling_dev_cache.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T20-59-43-01a01a1b-2ae5-7ef3-ba2a-e66e97d33fe0.jsonl, updated_at=2026-08-19T13:17:30+00:00, thread_id=01a01a1b-2ae5-7ef3-ba2a-e66e97d33fe0, pushed 040079b)
- rollout_summaries/2026-08-19T10-09-23-DABQ-bundle_current_timetable_website_changes_into_commits.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T18-09-23-01a0197f-3b2e-7551-bf66-8dfd7bdda242.jsonl, updated_at=2026-08-19T10:17:57+00:00, thread_id=01a0197f-3b2e-7551-bf66-8dfd7bdda242, origin-only push)

### keywords

- Turbopack, EcmascriptMergedChunkVersion, turbopackFileSystemCacheForDev, next.config.ts, .next, 040079b, git status --short --branch, public/icons, origin, production, faf2b10

## User preferences

- when the user corrected “shouldnt you be using bun not npm” and said “i want to edit it such that it uses tabs” -> use Bun/Bunx and retain `.prettierrc` tabs for this project. [Task 1]
- when the user said “no github issue tracker. i dont do that” and selected “agents.” -> use `.scratch/<feature-slug>/` local Markdown issues and prefer `AGENTS.md` for this repository. [Task 2]
- when the user said “stop making multiple seperate stuff use the same css file” -> each page/route owns its CSS module; share styles only through an explicitly shared feature stylesheet or owning component. [Task 3]
- when the user preferred Turbopack, “you have to do something cant just replace with webpack” -> preserve Turbopack and investigate cache/project causes before changing bundlers. [Task 4]

## Reusable knowledge

- `.prettierrc` is `{ "useTabs": true, "tabWidth": 2 }`; use `bun run format`, then repeat it for idempotence and run `git diff --check`. [Task 1]
- Authored architecture: `src/app` routes/global CSS, `src/components` UI, `src/features` models/hooks, `src/lib` API/auth/server proxy, `public/icons` SF Symbols, and `deploy` Nginx/post-receive. `.next` and `node_modules` are generated/vendor. [Task 2]
- Dedicated `/today`, `/week`, `/planner` pages retain client navigation because `SessionGate` does not reset by pathname and `useDashboard` caches requests. `src/app/page.module.css` is home-only; route/timetable styles are colocated or feature-owned. [Task 3]
- Fix `EcmascriptMergedChunkVersion ... no longer exists` by setting `experimental: { turbopackFileSystemCacheForDev: false }` in `next.config.ts`, moving stale `.next` aside, restarting, and touching a source file to observe HMR. [Task 4]
- `origin` is GitHub and `production` is the server remote. For existing dirty work, stage coherent path groups, re-scan `git status --short` and `public/icons`, then verify `git diff --check origin/main..HEAD` plus remote alignment; an origin push is not deployment. [Task 4]

## Failures and how to do differently

- Symptom: `find` output is dominated/truncated. Cause: generated/vendor trees. Fix: exclude `.git`, `.next`, and `node_modules`; macOS `find` lacks GNU `-printf`. [Task 2]
- Symptom: route/CSS repair is called complete after source audits. Cause: `IOSScreen.module.css` split did not rerun `next build`, and later builds were blocked by unrelated Popover casing/deletion changes. Fix: distinguish static audit, successful build, and blocked baseline precisely. [Task 3]
- Symptom: `next dev -- --webpack` behaves as a directory. Cause: malformed argument forwarding. Fix: permanent script is `next dev --webpack`; one-off Bun form is `bun run dev -- --webpack`, but do not default to it. [Task 4]

# Task Group: Code metrics, Git hygiene, and Codex/Open Design setup

scope: Reuse source-only cloc counting, focused nested-repo/history cleanup, and documented agent/plugin setup boundaries.
applies_to: cwd=multi-project workflows under /Users/omeriadon/Documents and /Users/omeriadon; reuse_rule=commands are context-sensitive: resolve the actual Git root/work-tree and user choices before performing mutations.

## Task 1: Produce a source-only multi-project cloc count, success

### rollout_summary_files

- rollout_summaries/2026-08-19T02-13-06-XO2o-cloc_allowlist_multi_project_source_count.md (cwd=/Users/omeriadon/Documents/Codex/2026-08-19/can, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T10-13-06-01a017cb-2d78-7433-bef9-7907a9121274.jsonl, updated_at=2026-08-19T02:18:07+00:00, thread_id=01a017cb-2d78-7433-bef9-7907a9121274, verified 55,916 lines)

### keywords

- cloc, --include-lang, --exclude-dir, .next, node_modules, pmstt, Timetable, timetable-website, 55,916

## Task 2: Remove accidental Git links and oversized ignored runtime assets, success

### rollout_summary_files

- rollout_summaries/2026-08-19T11-39-01-MyAc-remove_accidental_zephyr_gitlink.md (cwd=/Users/omeriadon/Documents/Codex, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T19-39-01-01a019d1-4b08-7190-8fed-30fafbb33f9c.jsonl, updated_at=2026-08-19T11:40:45+00:00, thread_id=01a019d1-4b08-7190-8fed-30fafbb33f9c, pushed 29a6cf6)
- rollout_summaries/2026-08-19T11-42-04-B6IL-clean_dotfiles_buzz_model_history_and_push.md (cwd=/Users/omeriadon, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T19-42-04-01a019d4-1684-7fc2-af87-406fc87468f7.jsonl, updated_at=2026-08-19T11:51:54+00:00, thread_id=01a019d4-1684-7fc2-af87-406fc87468f7, history cleanup pushed)

### keywords

- gitlink, mode 160000, git rm --cached, Zephyr, .dotfiles.git, --git-dir, --work-tree, .buzz/models, GH001, git filter-branch

## Task 3: Install skills and Open Design, partial setup boundaries recorded

### rollout_summary_files

- rollout_summaries/2026-08-19T11-36-30-0MxO-matt_pocock_skills_install_and_setup_paused.md (cwd=/Users/omeriadon/Documents/Codex/2026-08-19/setup-matt-pocock-skills, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T19-36-30-01a019ce-fac9-7f81-8458-39b2e41f5120.jsonl, updated_at=2026-08-19T11:39:26+00:00, thread_id=01a019ce-fac9-7f81-8458-39b2e41f5120, setup awaits choices)
- rollout_summaries/2026-08-21T14-26-19-kHAP-opendesign_codex_install_partial_task_setup.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/21/rollout-2026-08-21T22-26-19-01a024b7-2db8-73c3-9e83-bee3ffb54c17.jsonl, updated_at=2026-08-21T14:29:45+00:00, thread_id=01a024b7-2db8-73c3-9e83-bee3ffb54c17, plugin/MCP installed; new task incomplete)
- rollout_summaries/2026-08-21T14-29-30-2Tza-start_opendesign_cloud_brief_workflow.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/21/rollout-2026-08-21T22-29-30-01a024ba-18c9-7282-9908-e88c7fbf8960.jsonl, updated_at=2026-08-21T14:29:44+00:00, thread_id=01a024ba-18c9-7282-9908-e88c7fbf8960, Cloud brief not reached)

### keywords

- npx skills, YAML parse error, setup-matt-pocock-skills, Open Design, codex plugin, open-design MCP, collect_brief, OpenDesign Cloud, open-design-mode, plugin cache

## User preferences

- when the user said “instead of exclude its include. that should make more sense” and requested absolute paths -> use an explicit source-language allowlist and absolute project paths for code counts. [Task 1]
- when the user asked to “delete the things i should not have pushed, like some of .buzz. and then go push again” -> remove generated/runtime payloads from history while preserving local useful files and unrelated changes. [Task 2]
- when the user says to run a requested setup skill after installation -> continue into the skill workflow rather than stopping at prerequisite installation. [Task 3]
- when the user said “Use OpenDesign Cloud by default” and “begin the brief workflow” -> use Cloud unless another backend is specified, and begin the brief rather than jumping to generation. [Task 3]

## Reusable knowledge

- For source counting, exclude `.next` along with dependencies/build trees; the verified `cloc --include-lang` command over pmstt, Timetable, and timetable-website returned 644 files and 55,916 lines. `docker-compose.yml`, `Dockerfile`, and `deploy/post-receive` are legitimate source/config files. [Task 1]
- A nested checkout tracked as mode `160000` without `.gitmodules` is an accidental gitlink: resolve the outer root, use `git rm --cached -- <path>`, add the exact ignore rule, and verify nested status; never delete the nested checkout. [Task 2]
- Dotfiles uses `--git-dir=/Users/omeriadon/.dotfiles.git --work-tree=/Users/omeriadon`; remove `.buzz/models` from history in a temporary clean clone, retain local ignored models, and verify no reachable large blobs before pushing. [Task 2]
- The Matt Pocock installer can skip malformed YAML frontmatter; inspect warnings and fetch/load a requested skipped skill manually. Open Design plugin `0.5.3` and its local stdio MCP were verified installed, but no brief/generation task was completed. Its discovered installed workflow is `/Users/omeriadon/.codex/plugins/cache/open-design/open-design/0.5.3/skills/open-design-mode/SKILL.md`; use OpenDesign Cloud by default and wait for brief confirmation. [Task 3]

## Failures and how to do differently

- Symptom: source totals approach a million Next.js lines. Cause: `.next` was not excluded. Fix: use `--include-lang` plus generated/cache exclusions, not `node_modules` exclusion alone. [Task 1]
- Symptom: target repo/path cannot be found from a rollout subdirectory. Cause: it is not the actual root. Fix: run `git rev-parse --show-toplevel`; for dotfiles use explicit Git dir/work tree. [Task 2]
- Symptom: setup installer says complete but the requested skill is absent, or a new Open Design task is claimed ready. Cause: skipped YAML parse errors, an incorrect plugin-cache path, or incomplete MCP/fork startup. Fix: inspect warnings; use the nested `open-design/open-design/0.5.3` cache path (or search it), then confirm the requested skill/`collect_brief` state before proceeding. [Task 3]

# Task Group: Timetable website Base UI migration, neutral foundations, and interaction boundaries

scope: Apply the current Base UI/drawer direction across the unreleased Next.js website, preserve the Sidebar, use route-owned CSS, and keep known-good component interactions rather than reviving rejected gestures.
applies_to: cwd=/Users/omeriadon/Documents/timetable-website; reuse_rule=this checkout is unreleased and may be broadly rewritten when needed, but preserve explicitly excluded Sidebar files, unrelated dirty work, and user-owned unstaged edits; split CSS ownership with routes. [ad-hoc note]

## Task 1: Move Today event rows into the shared Base UI drawer, success

### rollout_summary_files

- rollout_summaries/2026-08-19T15-29-14-xvks-timetable_website_drawer_migration_and_app_unstyling.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T23-29-14-01a01aa4-108b-7da1-8f2d-265f460de558.jsonl, updated_at=2026-08-20T01:12:12+00:00, thread_id=01a01aa4-108b-7da1-8f2d-265f460de558, Today drawer shipped; broader cleanup remains partial)

### keywords

- Base UI, drawer, useDrawer, EventRow, TodayView, CalendarEventSheet, presentation="drawer", onClose, showHeader, 849602f

## Task 2: Unstyle non-sidebar UI and move toward direct Base UI primitives, partial

### rollout_summary_files

- rollout_summaries/2026-08-19T15-29-14-xvks-timetable_website_drawer_migration_and_app_unstyling.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T23-29-14-01a01aa4-108b-7da1-8f2d-265f460de558.jsonl, updated_at=2026-08-20T01:12:12+00:00, thread_id=01a01aa4-108b-7da1-8f2d-265f460de558, source/type/format checks passed; complete wrapper removal and runtime validation unverified)

### keywords

- unstyled, @base-ui/react, useSheet, SheetProvider, SheetTrigger, SheetActionButton, Button, LiquidGlass, Sidebar, swipeDirection, de4e8f5, npx tsc --noEmit

## Task 3: Repair neutral shared components, composition-driven List, and restore the switch baseline, partial

### rollout_summary_files

- rollout_summaries/2026-08-20T01-12-22-yNL3-timetable_website_component_ui_repair_and_switch_revert.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/20/rollout-2026-08-20T09-12-22-01a01cb9-eee4-7852-966e-590213dee179.jsonl, updated_at=2026-08-20T08:59:49+00:00, thread_id=01a01cb9-eee4-7852-966e-590213dee179, List/components shipped; switch drag was rejected and reverted)

### keywords

- Next.js 16, Base UI, List.tsx, ListSection, Card, Switch.tsx, Switch.module.css, :active, aria-checked, dark tokens, 565c101, 7d26c9f, e64056f, aad64c3

## Task 4: Audit and partially migrate installed-but-unused Base UI into token-backed wrappers, partial

### rollout_summary_files

- rollout_summaries/2026-08-19T02-28-09-y0Bu-base_ui_design_language_migration_partial.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T10-28-09-01a017d8-f3d3-7df1-bbb9-647e623ebcf4.jsonl, updated_at=2026-08-19T12:01:26+00:00, thread_id=01a017d8-f3d3-7df1-bbb9-647e623ebcf4, authenticated routes unverified)

### keywords

- @base-ui/react, design-tokens.css, primitives.module.css, --ds-popover, --ds-menu, currentTimetableDayIndex, PlannerView, CSS module audit

## Task 5: Simplify design tokens and align Today view with iOS, success

### rollout_summary_files

- rollout_summaries/2026-08-19T12-22-41-FdT4-simplify_timetable_design_language_and_today_view_ios_parity.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T20-22-41-01a019f9-44ea-73c1-9c00-1e1e4e172fc2.jsonl, updated_at=2026-08-19T13:22:12+00:00, thread_id=01a019f9-44ea-73c1-9c00-1e1e4e172fc2, static validation only)

### keywords

- design-tokens.css, SectionCard, TodayView, inline expansion, assessments, iOS parity, d3aa058

## Task 6: Center shared sheets and remove the TimetableRoute wrapper, partial

### rollout_summary_files

- rollout_summaries/2026-08-19T14-49-05-RPgk-timetable_sheet_interactions_and_remove_route_wrapper.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/19/rollout-2026-08-19T22-49-05-01a01a7f-4b84-7550-903d-d5907a4e77b8.jsonl, updated_at=2026-08-19T15:24:00+00:00, thread_id=01a01a7f-4b84-7550-903d-d5907a4e77b8, route deletion pushed; final build blocked by unrelated Popover state)

### keywords

- Base UI Dialog, sheetBackdrop, sheetPopup, overscroll-behavior, TimetableRoute, WeekView, Popover, 615160c, 40c8b99

## User preferences

- when the user said “when you click on an event in the today view, i want it to show the base ui drawer” -> use the shared drawer for Today events only; do not implicitly change Planner or archived-event presentation. [Task 1]
- when the user asked to “remove any and all references to this custom sheet ... use the drawer component” and “replace all buttons with the base ui one ... unstyled completely” -> default to direct Base UI primitives/drawers instead of styled wrapper abstractions. [Task 2]
- when the user said “everything in the entire app, except the sidebar ... leave it as is” -> exclude `src/components/Sidebar/Sidebar.tsx` and `Sidebar.module.css` from broad migrations unless explicitly authorized. [Task 2]
- when the user wanted the site reset toward “neutral” base UI and rejected ugly brown/generated colors -> preserve monochrome neutral tokens and repair shared production components rather than one-off demo markup. [Task 3]
- when the user clarified “active” meant pointer press, not checked state -> keep pressed feedback in `:active`; checked state only controls position. The later “revert it to what i had before” supersedes the drag request. [Task 3]

## Reusable knowledge

- `src/components/ui/drawer.tsx` wraps `@base-ui/react/drawer`. `EventRow` can opt into `presentation="drawer"`; reuse `CalendarEventSheet` in that host with explicit `onClose` and `showHeader` to avoid a duplicate header. [Task 1]
- The initial broad migration removed most non-sidebar module CSS, LiquidGlass/blur/reflection effects, and inline visual styles. It passed `npx tsc --noEmit`, staged Prettier, and `git diff --cached --check`; preserve the user-owned unstaged `swipeDirection = "right"` edit. [Task 2]
- Each page or route owns its own CSS module: do not put unrelated styles in `src/app/page.module.css` or import it from separate routes. Shared styles belong in an explicitly shared feature stylesheet or the owning shared component; split CSS when splitting routes. [ad-hoc note]
- This website has not been released, so broad architectural rewrites are authorized when needed rather than preserving released-user compatibility. [ad-hoc note]
- `List.tsx` uses `Children.toArray`/`isValidElement` to detect `ListSection`: direct children render in one `Card` with dividers, while sections render as separate Cards. Keep its `List.module.css` design-token contract (`--ds-content-card-padding`, `--ds-radius-content-card`, surface/border tokens, `--ds-content-section-gap`). [Task 3]
- The known-good switch is the simple non-draggable Base UI wrapper in `Switch.tsx`/`Switch.module.css`; ordinary click toggling was browser-verified with `aria-checked: true`. [Task 3]
- Do not infer Base UI adoption from `package.json`/`components.json`: before migration, source imports were zero. Current shared tokens are in `src/app/design-tokens.css` and `src/components/ui/primitives.module.css`; verify authenticated Drawer/Tabs/Menu/Popover/Select behavior and hard-coded visual values before calling the migration complete. [Task 4]
- `SectionCard` is the small repeatable section shell; Today combines events and assessments and expands class metadata inline. Preserve concurrent user commit `d3aa058` rather than recreating it. [Task 5]
- `Sheet.tsx` centrally hosts `openSheet(...)` flows. The interim centered Dialog used `.sheetBackdrop`/`.sheetPopup`; later drawer direction must be checked against current source. The deleted `TimetableRoute` logic lives directly in `today`, `week`, and `planner` pages. [Task 6]

## Failures and how to do differently

- Symptom: a repository-wide type check fails during a focused drawer change. Cause: existing widespread `Button`/`unstyled` errors. Fix: separate baseline errors from affected-file errors before attributing the failure. [Task 1]
- Symptom: an app-wide unstyling pass is called complete. Cause: no inventory proved every `useSheet`/`SheetProvider`/`SheetTrigger`/`SheetActionButton`/`Button` call site was removed, and no runtime/build validation ran. Fix: inventory those exact handles with `rg`, then run a production build and targeted browser checks. [Task 2]
- Symptom: build success is treated as shared-component correctness. Cause: pre-existing untracked `AdminUserEditorSheet` imports and Select typing errors block TypeScript independently. Fix: isolate baseline problems from the changed component set. [Task 3]
- Symptom: the switch becomes fragile or is rejected. Cause: pointer-capture/velocity drag complexity. Fix: retain the restored non-draggable baseline unless the user explicitly renews the drag requirement. [Task 3]
- Symptom: Base UI migration or sheet clicks are called verified. Cause: protected routes lacked authentication and later build was blocked by unrelated `Popover.tsx` casing/deletion. Fix: distinguish login/static checks from authenticated browser behavior and preserve unrelated dirty files. [Task 4][Task 6]

# Task Group: Timetable website iOS/SwiftUI parity, auth/API integration, and shared sheets

scope: Implement the real server-rendered Next.js website with iOS parity, functional authentication/API routes, standardized feedback sheets, and fixed sidebar/toolbar chrome.
applies_to: cwd=/Users/omeriadon/Documents/timetable-website; reuse_rule=use the existing Next.js and pmstt proxy contracts for this checkout; treat `/Users/omeriadon/Documents/Xcode_App_Library/Timetable` as the visual/behavioral reference only when the user asks for iOS parity, and preserve explicitly fixed chrome.

## Task 1: Correct the implementation target and preserve fixed chrome, success

### rollout_summary_files

- rollout_summaries/2026-08-18T11-14-32-uvLo-timetable_website_ios_parity_auth_and_shared_sheets.md (cwd=/Users/omeriadon/Documents/Codex/2026-08-18/continue-from-this-local-open-design, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/18/rollout-2026-08-18T19-14-32-01a01494-8267-79f0-8cb8-5b4603135e36.jsonl, updated_at=2026-08-18T19:28:20+00:00, thread_id=01a01494-8267-79f0-8cb8-5b4603135e36, wrong Open Design Vite deliverable corrected in the real website repo)

### keywords

- timetable-website, Open Design, Vite, Next.js 16, Sidebar.tsx, Toolbar.tsx, wrong folder, fixed chrome

## Task 2: Implement API-backed iOS/SwiftUI-parity website and standardized sheets, success

### rollout_summary_files

- rollout_summaries/2026-08-18T11-14-32-uvLo-timetable_website_ios_parity_auth_and_shared_sheets.md (cwd=/Users/omeriadon/Documents/Codex/2026-08-18/continue-from-this-local-open-design, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/18/rollout-2026-08-18T19-14-32-01a01494-8267-79f0-8cb8-5b4603135e36.jsonl, updated_at=2026-08-18T19:28:20+00:00, thread_id=01a01494-8267-79f0-8cb8-5b4603135e36, `npm run build` and HTTP auth checks passed; browser visual QA unavailable)

### keywords

- SwiftUI parity, /web-api/auth/login, /web-api/auth/request-code, /web-api/auth/verify-code-register, src/proxy.ts, pmstt.ts, ConfirmationSheet, MessageSheet, NotificationSettingsEditor, invalidCredentials, npm run build

## User preferences

- when the user corrected “you should have done it in /Users/omeriadon/Documents/timetable-website and actually implemented it” -> verify and use the explicitly named repository; do not substitute a nearby prototype or export directory. [Task 1]
- when the user said “do not change the sidebar or toolbar at all. those items are perfect.” -> preserve `src/components/Sidebar/` and `src/components/Toolbar/` markup, styling, and behavior as fixed constraints. [Task 1]
- when a website should “basically copy the iOS version” and “actually work and call the apis” -> inspect the SwiftUI app for parity while implementing against the existing API proxy/contracts, then validate redirects and error responses. [Task 2]
- when the user requested standardized “sheets, toggles, buttons, spacing, and variables” -> centralize controls in shared components and CSS variables instead of repeating page-local styling. [Task 2]

## Reusable knowledge

- The real project is the Next.js 16 app at `/Users/omeriadon/Documents/timetable-website`; `src/components/Sidebar/Sidebar.tsx` and `src/components/Toolbar/Toolbar.tsx` were intentionally left unchanged. [Task 1]
- Auth calls `/web-api/auth/login`, `/web-api/auth/request-code`, and `/web-api/auth/verify-code-register`; those server routes forward to `v1/auth/*` and write HTTP-only access/refresh cookies. `src/proxy.ts` redirects unauthenticated routes to `/login?returnTo=...`; `src/lib/server/pmstt.ts` forwards authenticated calls and refreshes sessions, while `src/lib/api/client.ts` handles JSON and readable API errors. [Task 2]
- Reuse `src/components/sheets/ConfirmationSheet/ConfirmationSheet.tsx` and `src/components/sheets/MessageSheet/MessageSheet.tsx` for destructive/error flows; shared sheet styling is in `src/components/sheets/Sheet/Sheet.module.css`. Notification parity lives in `src/components/settings/NotificationSettingsEditor/NotificationSettingsEditor.tsx` and `/settings/notifications`. [Task 2]
- Recorded verification: `git diff --check` and `npm run build` passed; unauthenticated `/` returned `307` to `/login?returnTo=%2F`, and an invalid login returned `401` with `code: invalidCredentials`. [Task 2]

## Failures and how to do differently

- Symptom: a polished prototype/Vite build still fails the request. Cause: implementation occurred in an Open Design export instead of the named website repository. Fix: resolve the exact target checkout before editing and confirm its framework/entrypoints. [Task 1]
- Symptom: visual parity is reported as verified without browser evidence. Cause: the available tooling failed with `Unknown tab: 2` and `The requested module './index.js' does not provide an export named 'default'`. Fix: report build/HTTP evidence separately and leave browser visual QA unverified until the setup is repaired. [Task 2]
- Symptom: a focused commit captures unrelated website files. Cause: a dirty worktree contained unrelated `components.json` and `next-env.d.ts` changes. Fix: preserve and distinguish unrelated paths before staging or committing. [Task 2]

# Task Group: Timetable website local SVG LiquidGlass toolbar and GSAP drag tuning

scope: Iteratively tune the local toolbar glass effect and pointer drag deformation without changing the established button styling, committing, or deploying experimental work.
applies_to: cwd=/Users/omeriadon/Documents/timetable-website; reuse_rule=reuse the local component and interaction patterns for this website's toolbar only; recheck current uncommitted state and obtain explicit authorization before any commit or `production` push.

## Task 1: Replace incompatible toolbar glass packages and repair backdrop sampling, partial

### rollout_summary_files

- rollout_summaries/2026-08-15T10-24-33-i0eA-tune_local_svg_liquid_glass_toolbar_drag_physics.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/15/rollout-2026-08-15T18-24-33-01a004f3-ac1f-7de1-83f1-03de7d5211d8.jsonl, updated_at=2026-08-16T03:52:58+00:00, thread_id=01a004f3-ac1f-7de1-83f1-03de7d5211d8, packages removed; compositing-layer diagnosis retained)

### keywords

- liquid-glass-react, backdrop-filter, Toolbar.tsx, Toolbar.module.css, layout.tsx, layout.module.css, outerAppShell, pageContent, overflow-y: auto

## Task 2: Implement and tune local SVG displacement LiquidGlass with pointer drag deformation, success

### rollout_summary_files

- rollout_summaries/2026-08-15T10-24-33-i0eA-tune_local_svg_liquid_glass_toolbar_drag_physics.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/15/rollout-2026-08-15T18-24-33-01a004f3-ac1f-7de1-83f1-03de7d5211d8.jsonl, updated_at=2026-08-16T03:52:58+00:00, thread_id=01a004f3-ac1f-7de1-83f1-03de7d5211d8, local SVG/GSAP implementation built successfully; later changes uncommitted and unpushed)

### keywords

- LiquidGlass.tsx, LiquidGlass.module.css, Toolbar.tsx, SVG, feImage, feDisplacementMap, ResizeObserver, GSAP, dragDistance, dragFollow, dragPressScale, dragDuration, dragReleaseDuration, pointercancel, bun run build

## User preferences

- when visual experimentation is still being judged, the user said “do not commit anything right now during this chat until i say its perfect” and “stop pushing to the server” -> keep the work local, uncommitted, and undeployed until explicit reauthorization. [Task 1][Task 2]
- when the user asked for a plan and said “leave [the existing outline and background]. you just apply the glass under them” -> plan first and layer only the requested effect without replacing established styling. [Task 2]
- when the user corrected “no blur, just your svg displacement” and “the button isnt supposed to rotate” -> keep rotation at zero and do not introduce blur/hover effects or substitute another interaction. [Task 2]
- when the user requested drag distance, deformation, bounce, press scale, and timing controls -> expose numeric component props instead of burying tuning constants. [Task 2]

## Reusable knowledge

- Keep the local implementation in `src/components/LiquidGlass.tsx` with `LiquidGlass.module.css`, integrated by `src/components/Toolbar.tsx`. It serializes a measured SVG displacement map into a data URI for `<feImage>`, applies multiple `<feDisplacementMap>` passes, and regenerates on size changes through `ResizeObserver`. [Task 2]
- This app has nested scrolling: `.outerAppShell { overflow: hidden }`, `.pageContent { overflow-y: auto }`, and some page mains also scroll. For visible `backdrop-filter` sampling, the toolbar must share the compositing layer with the content behind it; moving it into `.pageContent` fixed the sibling-layer problem. [Task 1]
- Use GSAP for press-and-hold drag/release. Pointer movement may translate and stretch/squash on the movement axis, but not rotate the element; window-level `pointerup` and `pointercancel` are required for release outside the button. [Task 2]
- Prefer the continuous response `dragDistance * (1 - Math.exp(-(distance * dragFollow) / dragDistance))` to a hard cap. The latest exposed values were `dragPressScale={1.1}`, `dragDuration={0.75}`, and `dragReleaseDuration={1.1}`. [Task 2]
- The final recorded validation was `git diff --check && bun run build`; Next prerendered `/`, `/classes`, `/friends`, `/settings`, and `/timetable`. This verifies the build, not visual acceptance. [Task 2]

## Failures and how to do differently

- Symptom: a liquid-glass package creates oversized or incorrectly positioned toolbar layers. Cause: centered/floating demo assumptions and fragile internal SVG `backdrop-filter` techniques do not fit this toolbar. Fix: preserve native button structure and use the local implementation only after checking compositing/layout assumptions. [Task 1]
- Symptom: refraction is weak or asymmetric at edges. Cause: a simple edge map. Fix: generate a rounded-rectangle signed-distance geometry with numerical surface normals. [Task 2]
- Symptom: drag travel visibly plateaus at an edge. Cause: a hard `Math.min` cap. Fix: use the continuous exponential response. [Task 2]

# Task Group: Timetable website generic sidebar reflection and perimeter highlight

scope: refine the shared sidebar reflection and coloured perimeter effect for arbitrary rendered content; validate visual placement with screenshots as well as the website build
applies_to: cwd=/Users/omeriadon/Documents/timetable-website; reuse_rule=reuse the shared CSS/component pattern for comparable sidebar effects, but tune visual constants against the active layout and inspect browser screenshots before calling it correct

## Task 1: Implement and refine generic sidebar reflection, partial

### rollout_summary_files

- rollout_summaries/2026-08-16T05-49-38-gpyP-generic_sidebar_reflection_outline_refinement.md (cwd=/Users/omeriadon/Documents/timetable-website, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/16/rollout-2026-08-16T13-49-38-01a0091e-57a5-74b2-91db-7a3f26fc5213.jsonl, updated_at=2026-08-16T14:45:32+00:00, thread_id=01a0091e-57a5-74b2-91db-7a3f26fc5213, final build passed and iterative visual refinements were committed/pushed; rollout records outcome as partial)

### keywords

- Sidebar.tsx, Sidebar.module.css, layout.module.css, saturationOutline, backdrop-filter, CSS masks, 3px edge strips, saturate(4), brightness(1.6), bun run build, browser screenshot, 7ae95f3

## User preferences

- when refining the sidebar, the user said it must work “for everything” and not be specific to cards or a view -> use shared layout/rendered-content mechanisms rather than page-level colour registration [Task 1]
- when the user requested stronger reflection, a thin but visible outline, no saturation throughout the sidebar, correct bottom-corner clipping, and the outline directly over the gray border -> verify screenshots for placement, clipping, brightness, and scope, not just a passing build [Task 1]

## Reusable knowledge

- The reflection spans `src/app/layout.module.css`, `src/components/Sidebar.module.css`, and `src/components/Sidebar.tsx`; mirror shared rendered content into the sidebar region, preserve vertical bands before blur, and use separate masks for top and bottom rounded corners [Task 1]
- Broad `.sidebar > * { position: relative; }` overrides decorative children. Pin `.sidebar > .saturationOutline` with `position: absolute; inset: 0; z-index: 2` [Task 1]
- Keep filtering on four physical perimeter strips, not a full-sidebar pseudo-element. The final settings used 3px strips at `top/right/bottom/left: 0`, 24px inset corner spans, `background: rgba(255,255,255,0.08)`, and `saturate(4) brightness(1.6)` [Task 1]
- `git diff --check && bun run build` passed: Next.js compiled, TypeScript passed, and all routes generated. Commits include `c00d632` for positioning and `7ae95f3` for the stronger specular outline [Task 1]

## Failures and how to do differently

- Symptom: the entire reflected sidebar becomes oversaturated. Cause: a full-size filtered pseudo-element. Fix: confine filters to narrow physical edge strips [Task 1]
- Symptom: outline looks gray or a few pixels inset. Cause: it samples the existing gray border instead of the reflection. Fix: overlay it directly on the perimeter [Task 1]
- Symptom: intermittent red lines appear at the top. Cause: broad flex-child positioning overrides an absolute decorative child. Fix: restore absolute positioning with higher specificity and inspect computed styles [Task 1]
- Symptom: a build passes but the user reports visual defects. Cause: compilation cannot establish compositing/clipping correctness. Fix: inspect browser screenshots and targeted edge crops [Task 1]

# Task Group: Timetable website SSR deployment, split Nginx routing, and Tailwind setup

scope: Deploy and maintain the server-rendered Timetable website beside the pmstt Vapor API, including route ownership, remotes, and Tailwind tooling.
applies_to: cwd=/Users/omeriadon/Documents/timetable-website with server change from /Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=recheck live Nginx, PM2, Git remotes, and dirty worktrees before deployment; route topology and remote names are production-specific.

## Task 1: Convert the existing website scaffold to Next.js SSR and deploy beside Vapor, success

### rollout_summary_files

- rollout_summaries/2026-08-15T03-50-04-XnC5-timetable_website_nextjs_routing_tailwind_deployment.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/15/rollout-2026-08-15T11-50-04-01a0038a-830c-7202-b0d1-9b05b2c0ae5d.jsonl, updated_at=2026-08-15T07:29:39+00:00, thread_id=01a0038a-830c-7202-b0d1-9b05b2c0ae5d, public routing and PM2 state verified)

### keywords

- timetable-website, Next.js 16, SSR, standalone output, Nginx, Vapor, pmstt, /api/health, AASA, Bun, PM2, timetable-website, git push production

## Task 2: Install Tailwind CSS in the existing Next.js website, success

### rollout_summary_files

- rollout_summaries/2026-08-15T03-50-04-XnC5-timetable_website_nextjs_routing_tailwind_deployment.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/15/rollout-2026-08-15T11-50-04-01a0038a-830c-7202-b0d1-9b05b2c0ae5d.jsonl, updated_at=2026-08-15T07:29:39+00:00, thread_id=01a0038a-830c-7202-b0d1-9b05b2c0ae5d, local and production build/restart verified)

### keywords

- Tailwind CSS 4.3.3, @tailwindcss/postcss, postcss.config.mjs, @import "tailwindcss", bun add, bun run build, .next, page.tsx

## User preferences

- when the user clarified “it is server rendered, like a normal next.js app” -> inspect the existing website repository and preserve SSR; do not substitute a static SPA. [Task 1]
- when the user clarified “git push should push to github, push production should be to the server” -> retain `origin` for GitHub and `production` for deployment, and verify both remotes before pushing. [Task 1]
- when the user asked “go install tailwind please” -> implement directly in the existing project while preserving unrelated uncommitted page/component work. [Task 2]

## Reusable knowledge

- In `Sources/pmstt/routes.swift`, health belongs under the existing API group as `api.get("health")`, yielding `/api/health`; the previous root `/health` should return 404. [Task 1]
- Production topology: Nginx routes `/api/` and AASA to Vapor at `127.0.0.1:8081`, and website paths to Next.js at `127.0.0.1:3000`. The website uses standalone output and PM2 service `timetable-website`; `deploy/post-receive` runs `bun install --frozen-lockfile`, `bun run build`, prepares standalone assets, then restarts PM2. [Task 1]
- The verified route checklist was root 200, `/api/health` 200, root `/health` 404, AASA 200, and PM2 `timetable-api:online` plus `timetable-website:online`. Vapor used `swift build -c release` before deployment. [Task 1]
- Tailwind uses `bun add -d tailwindcss @tailwindcss/postcss postcss`, `postcss.config.mjs` with `@tailwindcss/postcss`, and `@import "tailwindcss";` in `src/app/globals.css`; `bun run build` passed. [Task 2]

## Failures and how to do differently

- Symptom: validation reports lint success or blocks delivery without inspecting configuration. Cause: oxlint emitted `No files found to lint` for this scaffold. Fix: do not claim lint validation unless a working lint configuration is added. [Task 1]
- Symptom: a focused website commit captures generated files or unrelated UI edits. Cause: staging from a dirty worktree. Fix: inspect `git status`, keep `.next` ignored, and stage only the intended Tailwind/deployment files; review the pre-existing `page.tsx` separately. [Task 1][Task 2]

# Task Group: Timetable SwiftUI navigation refactor rollback and dirty-worktree preservation

scope: Revert rejected toolbar/sidebar work without losing pre-existing Timetable edits; preserve the existing wide-navigation facts but not the rejected UI design.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=reuse the rollback and in-app routing boundary for similar turns; treat the attempted toolbar design as rejected and reconfirm before another broad refactor.

## Task 1: Revert the current turn's toolbar/sidebar changes while preserving pre-existing edits, success

### rollout_summary_files

- rollout_summaries/2026-08-15T08-47-39-2wdH-revert_toolbar_sidebar_refactor.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/15/rollout-2026-08-15T16-47-39-01a0049a-f6ee-7ea2-ad2b-148c07f66251.jsonl, updated_at=2026-08-15T08:53:35+00:00, thread_id=01a0049a-f6ee-7ea2-ad2b-148c07f66251, turn-specific changes removed; unrelated modifications preserved)

### keywords

- SwiftUI, toolbar, AppPageToolbar, WideAppShell, AppRouter, NavigationSplitView, router.selectRoot, sidebar, revert, git status, friendslist.swift, Expected declaration, Extraneous '}'

## User preferences

- when the user said “ok so revert everything you have done” -> revert the current turn's changes only; do not reset unrelated user work. [Task 1]
- the initial request for a separate toolbar/page-local actions and clickable in-app sidebar navigation was rejected through a full revert -> do not treat that refactor or its UI choices as adopted; confirm the visual/interaction target before broad navigation work. [Task 1]

## Reusable knowledge

- The wide shell uses `NavigationSplitView` and `AppRouter.selectRoot(...)`; sidebar clicks are in-app state routing, not browser navigation. `Main/Views/AppPageToolbar.swift` was a temporary standalone file and was removed. [Task 1]
- Verify a rollback by checking temporary files are absent and using `git status --short` to confirm only pre-existing edits remain; the preserved files included Settings/profile-related views, assets, and `Special/Localizable.xcstrings`. [Task 1]

## Failures and how to do differently

- Symptom: toolbar/sidebar edits fail to compile in `Main/Tabs/Friends/friendslist.swift` with `Expected declaration` or `Extraneous '}' at top level`. Cause: an extra brace. Fix: repair the syntax, then build before deciding implementation status. [Task 1]
- Symptom: a source build succeeds but a navigation refactor is called complete. Cause: no runtime/UI verification and the user rejected the resulting implementation. Fix: keep build evidence distinct from runtime acceptance and reconfirm before retrying a broad refactor. [Task 1]

# Task Group: Timetable client/server cleanup, production deployment, subject-editor refinement, and Watch lifecycle migration

scope: coordinate requested Timetable and pmstt changes before production deployment; includes direct Friends-since editing, campus departure semantics, focused SwiftUI refinement, and WatchKit lifecycle deprecation cleanup
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=use for related cross-repo implementation, deployment, Friends/status, subject-editor, and Watch lifecycle work; recheck current contracts, working tree, and Xcode build state

## Task 1: Update client and server together for requested cleanup, then deploy and monitor pmstt, partial

### rollout_summary_files

- rollout_summaries/2026-08-14T08-20-23-MQZ3-timetable_client_server_cleanup_deployment_ui_watch_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/14/rollout-2026-08-14T16-20-23-019fff5b-a4b6-71d0-bb59-4617708c3a09.jsonl, updated_at=2026-08-14T10:16:31+00:00, thread_id=019fff5b-a4b6-71d0-bb59-4617708c3a09, server deployment verified; requested settings cleanup remained partial and client was not Xcode-built)

### keywords

- AccountSettings, AppBackground, EventTag, SettingsView, AppearanceSettingsView, git push production main, post-receive, /root/repos/timetable.git/hooks/post-receive, PM2, timetable-api

## Task 2: Make departing users off-campus and replace Friends-since requests with direct editing, success but client unbuilt

### rollout_summary_files

- rollout_summaries/2026-08-14T08-20-23-MQZ3-timetable_client_server_cleanup_deployment_ui_watch_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/14/rollout-2026-08-14T16-20-23-019fff5b-a4b6-71d0-bb59-4617708c3a09.jsonl, updated_at=2026-08-14T10:16:31+00:00, thread_id=019fff5b-a4b6-71d0-bb59-4617708c3a09, client/server route contract implemented and server deployment verified)

### keywords

- LocationStatusService, .onCampus, .offCampus, Friends-since, PUT /v1/friends/:friendID/friends-since, Friendship.acceptedAt, FriendDetailView, FriendController, 2010-01-01, yesterday

## Task 3: Match subject color picker to profile picker, animate Add Slot rows, and modernize Watch lifecycle APIs, success but unbuilt

### rollout_summary_files

- rollout_summaries/2026-08-14T08-20-23-MQZ3-timetable_client_server_cleanup_deployment_ui_watch_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/14/rollout-2026-08-14T16-20-23-019fff5b-a4b6-71d0-bb59-4617708c3a09.jsonl, updated_at=2026-08-14T10:16:31+00:00, thread_id=019fff5b-a4b6-71d0-bb59-4617708c3a09, focused source changes committed; Xcode validation pending)

### keywords

- InlineColorPicker, ProfileColourGrid, AvailableColors, .transition(.opacity), withAnimation(.snappy), WKApplication, WKApplicationDelegateAdaptor, WKApplicationDelegate, WatchNotificationRegistrationService

## User preferences

- when the server was deployed without the corresponding client cleanup, the user corrected: "you are obviously supposed to update both together" -> keep a client/server checklist, update and review both sides of a shared contract before deployment [Task 1]
- when departing users trigger location handling, the user said they “should never be within 5 or 10 mins” and should “just give the off campus thing” -> inspect the previous status and record `.offCampus` rather than inventing an intermediate departure state [Task 2]
- when removing the Friends-since workflow, the user requested that either friend can edit directly and dates are constrained after 2010 and before today -> preserve direct edit semantics and validate the same range client and server side [Task 2]
- when refining the subject editor, the user asked that it “look the same as the colour pickers in the profile editor sheet” while retaining the same colours, and requested opacity for Add Slot rows -> reuse the existing visual reference and requested animation rather than changing the palette or interaction model [Task 3]

## Reusable knowledge

- `AccountSettings` is server-synchronized and backward-compatible; inspect `Shared/Models/AccountSettings.swift` with the server DTO/model before removing settings fields. Personal tag subscriptions and administrative event-tag CRUD are separate surfaces, so removing one does not automatically justify deleting the other [Task 1]
- The deployment remote is `production`, not `prod`. The verified hook is `/root/repos/timetable.git/hooks/post-receive`, deployed app is `/var/www/timetable`, and PM2 process is `timetable-api`; successful evidence is `Build complete`, `No new migrations`, PM2 online, and `Deployment complete` [Task 1]
- If the branch is already up to date, invoke the hook directly only when a fresh build/migration verification was requested; do not manufacture an empty commit. A reset SSH log check can be retried directly against `root@203.17.177.58` with `ConnectTimeout` [Task 1]
- `LocationStatusService` should inspect the prior `.onCampus` state on a non-school-region entry and record `.offCampus`. The direct Friends-since contract is `PUT /v1/friends/:friendID/friends-since`, validates 2010-01-01 through yesterday, and updates `Friendship.acceptedAt` for either accepted participant [Task 2]
- `InlineColorPicker` can mirror `ProfileColourGrid` with a contiguous rectangular grid and inset white selection stroke while preserving `AvailableColors`; append subject slots using `.transition(.opacity)` within `withAnimation(.snappy)` [Task 3]
- Watch lifecycle replacements are `WKExtension.shared()` → `WKApplication.shared()`, `WKExtensionDelegateAdaptor` → `WKApplicationDelegateAdaptor`, and `WKExtensionDelegate` → `WKApplicationDelegate`; confirm against `WatchKit.framework/Headers/WKApplication.h` and build the Watch target before treating source modernization as complete [Task 3]
- Related skill: skills/timetable-change-verify-loop/SKILL.md [Task 1][Task 2][Task 3]

## Failures and how to do differently

- Symptom: a deployment hook succeeds while the requested feature is only implemented on one side. Cause: server deployment was treated as progress independent of the requested client cleanup. Fix: maintain an explicit client/server contract checklist and deploy only after both authorized sides are updated and reviewed [Task 1]
- Symptom: server deployment is reported as success but client behavior is assumed complete. Cause: no local Xcode build or runtime test ran. Fix: state source/deployment evidence separately and leave client compilation/runtime unverified until the relevant Xcode schemes are built [Task 1][Task 2][Task 3]
- Symptom: focused UI work accidentally absorbs unrelated settings, planner, location, metadata, or localization edits. Cause: committing from a dirty working tree without scope review. Fix: preserve unrelated modifications and stage only the focused files [Task 3]

# Task Group: Timetable offline campus status and server-controlled Live Activity developer lifecycle

scope: Offline location-status reliability, server-driven ActivityKit debug controls, timer rendering, school-day labels, and closely related pmstt cleanup across the Timetable app and server.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=inspect current source/routes and perform build/device/APNs checks before claiming the partial location/debug work is complete.

## Task 1: Design offline location persistence and retry without changing the UI, partial

### rollout_summary_files

- rollout_summaries/2026-08-14T11-02-24-uWZS-timetable_offline_location_live_activity_debugging.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/14/rollout-2026-08-14T19-02-24-019fffef-f6e6-7df1-b508-103beb98c7a4.jsonl, updated_at=2026-08-14T13:22:08+00:00, thread_id=019fffef-f6e6-7df1-b508-103beb98c7a4, design/source analysis; significant-location implementation and end-to-end validation pending)

### keywords

- CoreLocation, startMonitoringSignificantLocationChanges, pendingLocationStatusUpdates, LocationStatusService, /v1/account/status, AccountBootstrapService, school-campus, CLBackgroundActivitySession, BGAppRefreshTask

## Task 2: Restore idempotent server-controlled Live Activity debug Start/Stop/update lifecycle, partial

### rollout_summary_files

- rollout_summaries/2026-08-14T11-02-24-uWZS-timetable_offline_location_live_activity_debugging.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/14/rollout-2026-08-14T19-02-24-019fffef-f6e6-7df1-b508-103beb98c7a4.jsonl, updated_at=2026-08-14T13:22:08+00:00, thread_id=019fffef-f6e6-7df1-b508-103beb98c7a4, lifecycle source changes committed; no build/physical-device/APNs verification)

### keywords

- ActivityKit, LiveActivityRegistrationService, LiveActivityController, push-to-start, update-token, /v1/live-activities/debug/start, activityUpdates, pushToStartTokenUpdates, pushTokenUpdates, cd253ce, isDebug

## Task 3: Repair timer rendering and use `First: <subject>` before school, success with runtime boundary

### rollout_summary_files

- rollout_summaries/2026-08-14T11-02-24-uWZS-timetable_offline_location_live_activity_debugging.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/14/rollout-2026-08-14T19-02-24-019fffef-f6e6-7df1-b508-103beb98c7a4.jsonl, updated_at=2026-08-14T13:22:08+00:00, thread_id=019fffef-f6e6-7df1-b508-103beb98c7a4, narrow commits d43aff7c, 228bc44, d05b415; no build/device rendering check)

### keywords

- Text.currentDate, timer(countingDownIn:), timerInterval, SchoolDayLiveActivityWidget.swift, SchoolDayActivityProjector, beforeSchool, First:, d43aff7c, 228bc44, d05b415

## Task 4: Remove impossible notification-email fallback, success

### rollout_summary_files

- rollout_summaries/2026-08-14T11-02-24-uWZS-timetable_offline_location_live_activity_debugging.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/14/rollout-2026-08-14T19-02-24-019fffef-f6e6-7df1-b508-103beb98c7a4.jsonl, updated_at=2026-08-14T13:22:08+00:00, thread_id=019fffef-f6e6-7df1-b508-103beb98c7a4, committed 40f549d)

### keywords

- NotificationService.swift, sender.email, nil coalescing operator, non-optional type String, 40f549d

## Task 5: Deduplicate changelog from the correct search-bar commit boundary, success

### rollout_summary_files

- rollout_summaries/2026-08-14T11-02-24-uWZS-timetable_offline_location_live_activity_debugging.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/14/rollout-2026-08-14T19-02-24-019fffef-f6e6-7df1-b508-103beb98c7a4.jsonl, updated_at=2026-08-14T13:22:08+00:00, thread_id=019fffef-f6e6-7df1-b508-103beb98c7a4, client baseline 0d78985a)

### keywords

- git log 0d78985a..HEAD, improve the search bar glass, changelog, duplicate commits, d05b415, 40f549d

## User preferences

- when the user asked for `startMonitoringSignificantLocationChanges` and “the other updates and queing etc. dont change the ui” -> preserve the status UI; work on background delivery, persistence, retry, and synchronization. [Task 1]
- when the user preferred background location hooks over polling -> use low-power significant-location changes as a coarse trigger, retain geofences for exact campus transitions, and avoid continuous GPS unless real-time tracking is genuinely required. [Task 1]
- when the user requested Start, Stop, and updates for named school states with invalid actions hidden -> keep developer controls server-driven and conditionally enabled from server state; group badge tests in a menu rather than expanding Settings. [Task 2]
- after “An active Live Activity with an update token is required” -> Start must be idempotent; repeated taps must not consume another push-to-start, and Stop must clear tokenless pending records. [Task 2]
- when the user identified the exact timer line and requested “please make it just say First:” -> compare known-good history for a narrow timer replacement and apply the label consistently across Lock Screen, Dynamic Island, watch-sized layout, and APNs alert text. [Task 3]
- when the user clarified “it was yesterday” then “remove the duplicates” -> use the exact requested date/commit boundary and consolidate related implementation/fix commits in changelogs. [Task 5]

## Reusable knowledge

- `LocationStatusService` persists the latest value in `Defaults[.locationStatus]`, queues failures in `Defaults[.pendingLocationStatusUpdates]`, posts to `/v1/account/status`, and refreshes via `AccountBootstrapService`. Failed items otherwise flush mainly on start or another location transition; add network-restoration, foreground/authentication, and background-execution opportunities. Keep transition, location-confirmation, and server-sync timestamps separate. [Task 1]
- The inspected campus contract uses center `(-31.944462605584388, 115.8380028573902)`, radius `225`, identifier `school-campus`, and approach radii `1500`/`3500` metres. Significant-location changes are coarse and low power; `BGAppRefreshTask` is not a dependable periodic location source. [Task 1]
- Observe `activityUpdates`, `pushToStartTokenUpdates`, and each activity's `pushTokenUpdates` as async sequences. APNs HTTP 200 only proves acceptance, not activity creation or token emission. Debug activities use `isDebug` attributes and are excluded from normal local expiry cleanup; compatibility recognizes `debug-` school-date prefixes. [Task 2]
- Debug routes include `/v1/live-activities/debug`, `/debug/start`, `/debug/update`, `/debug/stop`, and `/:activityKey/update-token`. The restored idempotent Start path is pmstt `cd253ce`; Stop sends APNs end only with an update token but always ends a tokenless pending server record. [Task 2]
- The known-good visible timer is `Text(.currentDate, format: .timer(countingDownIn: startDate ..< endDate, showsHours: false))`; keep `ProgressView(timerInterval:)` for progress. For `.beforeSchool`, project the raw subject then format `First: <subject>`. [Task 3]
- `sender.email` in `NotificationService.swift` is non-optional; use it directly rather than `sender.email ?? "unknown"`. [Task 4]

## Failures and how to do differently

- Do not claim significant-location monitoring, retry, or offline reliability exists: this rollout did not implement or validate it with schema, runtime, offline/online, or device checks. [Task 1]
- Symptom: repeated debug Start fails because no active update token exists. Cause: forced retirement/new push-to-start consumed another delivery while an active or pending record existed. Fix: preserve idempotency and explicitly end tokenless pending records. [Task 2]
- Source/whitespace checks did not validate ActivityKit rendering, physical device behavior, or APNs lifecycle. Keep those boundaries explicit after timer/debug changes. [Task 2][Task 3]
- Symptom: a requested one-file fix collects unrelated widget edits. Cause: the working tree already contained timer workarounds. Fix: use narrow staging and inspect the staged paths before committing. [Task 3]

# Task Group: Timetable iPhone WidgetKit availability and extension deployment-target diagnosis

scope: Diagnose missing iPhone widgets by separating extension embedding, target dependencies, entitlements, bundle declarations, and minimum-OS availability.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=inspect the current project settings and widget source before changing deployment targets; this diagnosis is source/configuration evidence until archive and affected-device checks run.

## Task 1: Diagnose iPhone widgets missing on iOS 26.6, partial

### rollout_summary_files

- rollout_summaries/2026-08-14T10-59-38-2Q3C-diagnose_iphone_widget_extension_deployment_mismatch.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/14/rollout-2026-08-14T18-59-38-019fffed-7034-7551-b98b-6b7eaae74fc0.jsonl, updated_at=2026-08-14T11:01:45+00:00, thread_id=019fffed-7034-7551-b98b-6b7eaae74fc0, source diagnosis only; no target change or archive/device verification)

### keywords

- WidgetKit, Widget.appex, PlugIns, project.pbxproj, IPHONEOS_DEPLOYMENT_TARGET, iOS 26.6, iOS 27.0, App Groups, NSExtensionPointIdentifier, 13693635

## User preferences

- when users cannot see widgets but the developer can, the user asked to investigate “the linking of the extension” -> compare developer/device OS and inspect embedding plus availability settings before assuming a runtime WidgetKit bug. [Task 1]

## Reusable knowledge

- `Timetable` structurally embeds `Widget.appex` in `PlugIns`, depends on the `Widget` target, declares `com.apple.widgetkit-extension`, and shares `group.omeriadon.timetable` plus the keychain access group with the app. [Task 1]
- The diagnosed incompatibility is app target iOS `26.6` versus Widget Debug/Release `IPHONEOS_DEPLOYMENT_TARGET = 27.0`; iOS 26.6 devices can install the app but may omit the incompatible extension from the widget gallery. Commit `13693635` (`remove os 26 support`) introduced the target raise. [Task 1]
- Proposed correction: lower both Widget target configurations to `26.6` only after checking widget sources for iOS-27-only APIs, then build/archive and verify the installed bundle on an affected iOS 26.6 device. [Task 1]

## Failures and how to do differently

- Symptom: a widget is missing for some users while embedding looks correct. Cause: target availability can differ from the host app even when the extension is linked and entitled correctly. Fix: audit both targets' deployment settings before redesigning the widget or changing App Groups. [Task 1]
- No Xcode build, archive, install, or device verification occurred. Treat this as a diagnosis, not confirmation that lowering the target is safe. [Task 1]

# Task Group: Timetable + pmstt school-event WeatherKit delivery and weather-row refinement

scope: Date-aware WeatherKit summaries for administrator-created global school events, including server contract, private-event suppression, cross-target model compatibility, production deployment, and shared-row layout fixes.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=reuse the established event/weather contract and presentation rules, but inspect current migrations, production state, and unverified client build/UI state before relying on it.

## Task 1: Persist and display weather for administrator global school events, success

### rollout_summary_files

- rollout_summaries/2026-08-13T13-34-26-s6VQ-weatherkit_school_events_deployment_and_ui_refinements.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/13/rollout-2026-08-13T21-34-26-019ffb54-ce19-71f3-ae01-0cc4f9a5f4ea.jsonl, updated_at=2026-08-13T14:14:14+00:00, thread_id=019ffb54-ce19-71f3-ae01-0cc4f9a5f4ea, deployed; client build and visual verification intentionally not run)

### keywords

- WeatherKit, SchoolWeather, showsWeather, precipitationChance, CalendarEvent, AddCalendarEventWeather, school_weather_cache, pmstt, git push production, timetable-api

## Task 2: Repair Watch/Widget Hashable conformance after weather model addition, success

### rollout_summary_files

- rollout_summaries/2026-08-13T13-34-26-s6VQ-weatherkit_school_events_deployment_and_ui_refinements.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/13/rollout-2026-08-13T21-34-26-019ffb54-ce19-71f3-ae01-0cc4f9a5f4ea.jsonl, updated_at=2026-08-13T14:14:14+00:00, thread_id=019ffb54-ce19-71f3-ae01-0cc4f9a5f4ea, commit a279d89)

### keywords

- CalendarEvent, Hashable, SchoolWeather, Equatable, Shared/Models/SchoolWeather.swift, Watch Widget, a279d89

## Task 3: Keep the shared weather row readable in Today cards and event detail, success

### rollout_summary_files

- rollout_summaries/2026-08-13T13-34-26-s6VQ-weatherkit_school_events_deployment_and_ui_refinements.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/13/rollout-2026-08-13T21-34-26-019ffb54-ce19-71f3-ae01-0cc4f9a5f4ea.jsonl, updated_at=2026-08-13T14:14:14+00:00, thread_id=019ffb54-ce19-71f3-ae01-0cc4f9a5f4ea, commits 1d3e2e7 and c9f3459)

### keywords

- SchoolWeatherSummary, TodayEventRow, layoutPriority(1), Spacer(minLength: 1), precipitationChance, UV, padding(.trailing, 5), minimumScaleFactor

## User preferences

- when the user said “user created events never show weather” -> enforce private-event suppression on the server as well as the client; do not rely on presentation-only hiding. [Task 1]
- when the user requested the weather row in both card and detail sheet, under the title, with precipitation before UV and `Spacer(minLength: 1)` between values -> preserve that exact shared presentation. [Task 1][Task 3]
- when the user said precipitation should show as a percentage “even when 0%” -> do not conditionally hide zero. [Task 1]
- when the user rejected the earlier screenshot and requested “add some trailing padding, 5 points ... one line” -> make the narrow requested UI adjustment rather than widening the change. [Task 3]

## Reusable knowledge

- `AddCalendarEventWeather` adds `calendar_events.shows_weather` and `school_weather_cache.precipitation_chance` with defaults. pmstt performs a daily WeatherKit lookup for the event date, returns nil when unavailable, and tolerates lookup failure so the calendar response still succeeds. [Task 1]
- Private events are created with `showsWeather: false` and updates force it false; global events retain the administrator-controlled flag. [Task 1]
- The production push built successfully, applied `pmstt.AddCalendarEventWeather`, restarted PM2 `timetable-api`, and reported `Build complete!`, `Migration successful`, and `Deployment complete`; source locations include `Main/Components/SchoolWeatherSummary.swift` and pmstt `Migrations/AddCalendarEventWeather.swift`. [Task 1]
- `CalendarEvent: Hashable` requires optional `SchoolWeather` to be `Hashable`; add `Hashable` alongside `Equatable` for synthesized conformance. [Task 2]
- Give each weather label `.layoutPriority(1)` so spacers do not consume its width. Today uses `.caption` without `.minimumScaleFactor(0.6)`; the final card adjustment is `.padding(.trailing, 5)` on the weather summary. [Task 3]

## Failures and how to do differently

- Local app build/tests and visual verification were intentionally not run. Do not represent the production deploy as proof that the iOS/Watch client compiles or renders correctly. [Task 1]
- Preserve unrelated staged work, including the recorded `Main/Views/NameSheet.swift` deletion, when committing feature-specific changes. [Task 1]

# Task Group: Timetable Xcode asset-catalog validation and SwiftPM dependency provenance

scope: Diagnose `actool` Icon Composer failures and trace or clean stale Swift Package Manager dependency resolution without confusing source, cache, and lockfile evidence.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=use paths and dependency relationships as checkout-specific evidence; always inspect the newest Xcode activity log and current package resolution before concluding a fresh build is fixed.

## Task 1: Identify the exact failing Icon Composer layer for `Multiple validation errors occurred`, success

### rollout_summary_files

- rollout_summaries/2026-08-13T11-59-10-7egg-timetable_asset_validation_and_swiftpm_dependency_trace.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/13/rollout-2026-08-13T19-59-10-019ffafd-940c-7253-9263-ae6be89e1b70.jsonl, updated_at=2026-08-13T12:19:25+00:00, thread_id=019ffafd-940c-7253-9263-ae6be89e1b70, diagnosis only; no files changed)

### keywords

- actool, CompileAssetCatalogVariant, Multiple validation errors occurred, Icon Composer, Timetable.icon, Timetable_Assets/Image, Timetable_Assets/image, Image.png, image.jpg, xcactivitylog

## Task 2: Trace UniversalGlass and determine stale Chronicle cleanup, success

### rollout_summary_files

- rollout_summaries/2026-08-13T11-59-10-7egg-timetable_asset_validation_and_swiftpm_dependency_trace.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/13/rollout-2026-08-13T19-59-10-019ffafd-940c-7253-9263-ae6be89e1b70.jsonl, updated_at=2026-08-13T12:19:25+00:00, thread_id=019ffafd-940c-7253-9263-ae6be89e1b70, no build run and no files changed)

### keywords

- UniversalGlass, swift-agentation, Agentation, Package.swift, Package.resolved, Chronicle, Tinkerble, swift-syntax, Reset Package Caches, Resolve Package Versions, workspace-state.json

## User preferences

- when the user rebuilt after replacing the first reported asset and asked whether it was “the other icons or same one” -> inspect the newest activity log and explicitly distinguish the target inputs from the exact failing asset/layer. [Task 1]

## Reusable knowledge

- `Timetable_Assets/image` and `Timetable_Assets/Image` are separate case-sensitive layers in `Special/Timetable.icon`: lowercase `image` maps to `image.jpg`, uppercase `Image` maps to `Image.png`. The recorded latest failure was uppercase `Image` in the main icon, not the Watch or Debug icon. [Task 1]
- This validation problem originates in `actool` during `CompileAssetCatalogVariant`, not in the Swift compiler. The exact recorded error was `Couldn't resolve layer reference pointing to layer 'Timetable_Assets/Image' in Layer Stack (null)`. [Task 1]
- Dependency path: `Timetable -> swift-agentation 1.0.0 -> UniversalGlass 1.1.0`; `SourcePackages/checkouts/swift-agentation/Package.swift` directly declares UniversalGlass and the `Agentation` target depends on its product. [Task 2]
- Chronicle was present in `Package.resolved` and DerivedData workspace state but had no current project/dependent-package reference; Tinkerble currently depends on `swift-syntax`, not Chronicle. Clean it via Xcode File → Packages → Reset Package Caches, then Resolve Package Versions, and recheck `Package.resolved`. [Task 2]

## Failures and how to do differently

- Symptom: repairing the first reported icon layer leaves the same general validation failure. Cause: another case-distinct broken layer remains. Fix: after every Icon Composer repair, inspect the newest `.xcactivitylog` rather than assuming the prior layer was the only issue. [Task 1]
- Symptom: stale package checkout deletion appears to remove Chronicle but it returns in resolution state. Cause: deleting checkouts does not rewrite `Package.resolved`. Fix: reset caches, resolve versions, and only then claim removal. [Task 2]

# Task Group: SSH connection-refused diagnosis for Timetable production host

scope: Diagnose TCP-level SSH refusal to the known production host; use before investigating SSH authentication, keys, or known_hosts.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=the diagnostic meaning is general, but host IP and Oracle Cloud recovery context are time-specific.

## Task 1: Diagnose failed `ssh root@158.179.16.91`, partial

### rollout_summary_files

- rollout_summaries/2026-08-13T02-19-27-iDAA-diagnose_ssh_connection_refused.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/13/rollout-2026-08-13T10-19-27-019ff8ea-d55c-75f1-9246-97a1c3c9e5c8.jsonl, updated_at=2026-08-13T02:22:36+00:00, thread_id=019ff8ea-d55c-75f1-9246-97a1c3c9e5c8, diagnosis only; no cloud console credentials)

### keywords

- 158.179.16.91, ssh, Connection refused, sshd, port 22, Oracle Cloud, serial console, BatchMode, known_hosts

## Reusable knowledge

- `ssh -vvv -o BatchMode=yes -o ConnectTimeout=10 root@158.179.16.91 true` reached the host but returned `ssh: connect to host 158.179.16.91 port 22: Connection refused`; this occurs before authentication, so local keys/configuration are not the cause. [Task 1]
- Recovery needs provider web/serial-console or equivalent server access: verify the port-22 listener with `sudo ss -lntp | grep ':22'`, enable/restart `ssh` or `sshd`, open the host firewall, and permit inbound TCP/22 in the cloud security list/NSG. Ubuntu commonly uses `systemctl enable --now ssh` plus `ufw allow 22/tcp`; Oracle Linux commonly uses `systemctl enable --now sshd` plus `firewall-cmd --permanent --add-service=ssh` and reload. [Task 1]
- Even after the network repair, direct root login may be disabled; use the image’s normal `ubuntu` or `opc` account then `sudo -i`. [Task 1]

## Failures and how to do differently

- Symptom: `Connection refused` on port 22. Cause: active TCP rejection, commonly `sshd` stopped/not listening or a host/cloud firewall reject rule. Fix: repair reachability/listener first; do not spend time on keys or `known_hosts` before TCP succeeds. [Task 1]
- No console or OCI credentials were available, so this remained a diagnosis rather than a repair. Clearly report partial completion and hand off provider-console steps rather than claiming the host was fixed. [Task 1]

# Task Group: Timetable wide iPad navigation, APNs registration, and account network startup

scope: Repair iPad or Mac-designed-for-iPad wide-shell routing, device-token registration, and account tag loading.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=reuse source paths and interaction rules for this checkout; network/year-group completion remains runtime-unverified.

## Task 1: Preserve wide sidebar destinations and make sidebar rows actionable, success

### rollout_summary_files

- rollout_summaries/2026-08-13T01-33-31-Nebm-fix_ipad_wide_sidebar_apns_and_network_loading.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/13/rollout-2026-08-13T09-33-31-019ff8c0-c8e7-7f41-83e4-55404ff73c10.jsonl, updated_at=2026-08-13T01:44:38+00:00, thread_id=019ff8c0-c8e7-7f41-83e4-55404ff73c10, committed; runtime unbuilt)

### keywords

- NavigationSplitView, AppRouter, WideAppShell, rootDestination(for:), timetableWeek, timetableToday, timetablePlanner, Friends, DialStylePicker, safeAreaBar, e465959f

## Task 2: Separate APNs registration from alert-permission UX, success

### rollout_summary_files

- rollout_summaries/2026-08-13T01-33-31-Nebm-fix_ipad_wide_sidebar_apns_and_network_loading.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/13/rollout-2026-08-13T09-33-31-019ff8c0-c8e7-7f41-83e4-55404ff73c10.jsonl, updated_at=2026-08-13T01:44:38+00:00, thread_id=019ff8c0-c8e7-7f41-83e4-55404ff73c10, committed; runtime unbuilt)

### keywords

- NotificationRegistrationService, requestRemoteRegistration(), registerForRemoteNotifications, registrationFailed, PUT /v1/devices/current, APNs token, aps-environment, 8b1490b5

## Task 3: Improve year-group network startup on wide platforms, partial

### rollout_summary_files

- rollout_summaries/2026-08-13T01-33-31-Nebm-fix_ipad_wide_sidebar_apns_and_network_loading.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/13/rollout-2026-08-13T09-33-31-019ff8c0-c8e7-7f41-83e4-55404ff73c10.jsonl, updated_at=2026-08-13T01:44:38+00:00, thread_id=019ff8c0-c8e7-7f41-83e4-55404ff73c10, plausible fix pending authenticated runtime test)

### keywords

- AccountView.loadYearGroups(), AdministrationService.tagCatalogue(), tagSubscriptions(), /v1/tags, /v1/tags/subscriptions, NetworkManager, waitsForConnectivity, startMonitoring(), 771ff77c

## User preferences

- when the user said the iPad app should have additional sidebar items “instead of the tab picker” -> on wide layouts preserve explicit sidebar destinations; do not reintroduce compact timetable tabs. [Task 1]
- when the user wanted Settings and Administration styled like normal items and “not overlapping” -> use shared explicit sidebar-row styling and a vertical layout rather than overlapping stack layers. [Task 1]
- when a visible “device registration failure” badge is reported, distinguish denied notification-display permission from APNs token registration/upload failure before presenting an error. [Task 2]
- year-group loading must work on both iPad and the iPad version running on Mac; validate both wide presentation environments. [Task 3]

## Reusable knowledge

- `AppRouter.navigate(to:)` formerly replaced a selected wide `timetableWeek`/Today/Planner root with aggregate `.timetable`. `rootDestination(for:)` must preserve the current explicit timetable sidebar destination while routing a timetable detail. `WideAppShell` is more reliable with explicit buttons calling `router.selectRoot(...)` than a mixed `List(selection:)` plus custom utility rows. [Task 1]
- `requestAuthorization` and `UIApplication.shared.registerForRemoteNotifications()` are separate operations. Log authorization failure but still attempt remote registration; reserve `registrationFailed(...)` for APNs callback failures or exhausted token-upload retries. Token upload is `PUT /v1/devices/current` with installation ID, platform, APNs token, and debug flag. [Task 2]
- Account year groups come from `AccountView.loadYearGroups()` through authenticated `GET /v1/tags` and `/v1/tags/subscriptions`. The production base URL was reachable in unauthenticated curl checks (401/404 were protected-route responses); the changed startup enables `waitsForConnectivity` and calls `NetworkManager.shared.startMonitoring()`. [Task 3]

## Failures and how to do differently

- Symptom: Friends appears inert or Settings/Administration rows are inconsistent. Cause: mixed selection-bound `List` rows and custom utility buttons. Fix: use explicit root-selection buttons with shared styling when composing a custom wide sidebar. [Task 1]
- Symptom: false device-registration badge after permission denial. Cause: early return before `registerForRemoteNotifications()`. Fix: do not equate alert permission with APNs registration. [Task 2]
- The year-group/network changes passed `git diff --check` but received no build, UI run, or authenticated request. Build/run, sign in, open Account, and inspect `/v1/tags` and `/v1/tags/subscriptions` on iPad and Mac-designed-for-iPad before treating the fix as complete. [Task 3]

# Task Group: Timetable accessibility and profile appearance/font rendering

scope: App-wide iOS/Watch accessibility semantics and profile editor, palette, monogram font, and arrival-statistics behavior.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=apply the visual and accessibility constraints to Timetable surfaces; source commits are not runtime verification.

## Task 1: Add broad accessibility semantics without Dynamic Type changes, partial

### rollout_summary_files

- rollout_summaries/2026-08-12T08-06-24-KVbj-timetable_accessibility_profile_appearance_refinements.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T16-06-24-019ff502-1e4d-7472-8616-1ae8f6647ca1.jsonl, updated_at=2026-08-12T10:14:19+00:00, thread_id=019ff502-1e4d-7472-8616-1ae8f6647ca1, source/diff checked; not Accessibility Inspector/VoiceOver verified)

### keywords

- accessibility, VoiceOver, Dynamic Type, accessibilityHidden(true), AccessibilityFocusState, TimetableWeekGrid, SessionCellView, ProfilePicture, ccf8969, 61e7e59

## Task 2: Refine profile foreground styling, font variants, and arrival statistics, success

### rollout_summary_files

- rollout_summaries/2026-08-12T08-06-24-KVbj-timetable_accessibility_profile_appearance_refinements.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T16-06-24-019ff502-1e4d-7472-8616-1ae8f6647ca1.jsonl, updated_at=2026-08-12T10:14:19+00:00, thread_id=019ff502-1e4d-7472-8616-1ae8f6647ca1, committed; not built)

### keywords

- foregroundStyle, Color.primary, preferredColorScheme, ProfileAppearance, ProfilePicture, ProfileAppearanceSheet, ProfileColourGrid, monogramUIFontWeight, designedSystemFont, weekdayAverageArrivalSecondsSinceMidnight, /v1/account/status/statistics

## User preferences

- when accessibility is requested “to everything,” include tags, labels, custom controls, Watch surfaces, and semantic states; the user explicitly narrowed this with “no dynamic type changes. but yes to everything else.” [Task 1]
- the user said “DO NOT EVER UNDO THE WORK I CLEARLY DO.” -> preserve unrelated dirty/user-owned edits exactly; never revert or reinterpret them without permission. [Task 2]
- the user said “JUST USE FOREGROUND STYLE” because `preferredColorScheme` breaks the app -> never add `preferredColorScheme` for this workspace’s targeted foreground fixes; use `.foregroundStyle`/`Color.primary`. [Task 2]
- profile font design and weight must remain independently effective for default, serif, monospaced, and rounded choices; validate their combinations rather than treating weight as a replacement for design. [Task 2]

## Reusable knowledge

- Timetable grid cells should expose weekday, session, and subject/free/break/unavailable state; interactive cells need button traits, selected values, and an accessibility action. Combine dense friend/grade/location/list rows into concise summaries, hide decorative paper/background imagery with `.accessibilityHidden(true)`, label icon-only controls, and restore focus on friend-detail dismissal with `@AccessibilityFocusState`. [Task 1]
- `ProfileAppearance.fontDesign` is profile-picture-specific and is distinct from `AccountSettings.appFontDesign`. Rendering is in `Main/Components/ProfilePicture.swift`, editor in `ProfileAppearanceSheet.swift`, and palettes in `ProfileColourGrid.swift`. Use explicit UIKit font construction for weighted default/monospaced/designed variants rather than chained SwiftUI `.fontDesign`/`.fontWeight` fallback. [Task 2]
- In a parent with hierarchical white foreground styling, `.foregroundStyle(.primary)` can inherit white. Concrete `.foregroundStyle(Color.primary)` restores adaptive black/white in the profile editor. The foreground palette is intentionally `topLightness: 0.70` through `bottomLightness: 0.30`, distinct from the background palette. [Task 2]
- `/v1/account/status/statistics` returns `weekdayAverageArrivalSecondsSinceMidnight` as Monday-through-Sunday `[Double?]`; client UI shows Overall plus each weekday. Legacy profile decoding uses independent default constants, not recursive `ProfileAppearance.default`. [Task 2]

## Failures and how to do differently

- Do not replace user-owned `.foregroundStyle(.white)` with `.preferredColorScheme(.dark)`; that broke the app and required restoration. Do not assume `.primary` is adaptive in a hierarchical parent; use `Color.primary` where needed. [Task 2]
- Source/diff validation is insufficient: run an Accessibility Inspector/VoiceOver audit and test profile font designs/weights, light/dark editor foreground, and weekday statistics in Xcode/device when authorization allows. [Task 1] [Task 2]

# Task Group: Timetable auth limits, Portal concurrency, and paper-versus-glass SwiftUI edits

scope: Narrow source changes across Timetable, sibling pmstt, and local Portal; includes explicit modifier-hierarchy and commit-scope safeguards.
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=Timetable paths apply here, pmstt and Portal facts require their sibling checkouts; no task was compiler/runtime verified.

## Task 1: Raise authentication-related limits to 100 characters, success

### rollout_summary_files

- rollout_summaries/2026-08-12T06-20-33-kdrw-timetable_auth_portal_concurrency_and_paper_glass_styling.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T14-20-33-019ff4a1-35cd-7821-9d23-2c41a5ddb0fe.jsonl, updated_at=2026-08-12T07:23:39+00:00, thread_id=019ff4a1-35cd-7821-9d23-2c41a5ddb0fe, committed; unbuilt)

### keywords

- AccountAuthenticationModel, AccountInputGroup, CapsuleInputRow, AuthController, AdministrationController, SchoolEmailAddress, 100 characters, 0ded545, a4112f5

## Task 2: Remove invalid Portal Sendable constraints, partial

### rollout_summary_files

- rollout_summaries/2026-08-12T06-20-33-kdrw-timetable_auth_portal_concurrency_and_paper_glass_styling.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T14-20-33-019ff4a1-35cd-7821-9d23-2c41a5ddb0fe.jsonl, updated_at=2026-08-12T07:23:39+00:00, thread_id=019ff4a1-35cd-7821-9d23-2c41a5ddb0fe, source-reviewed pending compile)

### keywords

- PortalConfiguration, Sendable, @Sendable, AnyView, ConditionalPortalTransitionModifier, GroupIDPortalTransitionModifier, GroupItemPortalTransitionModifier, OptionalPortalTransitionModifier, ../../Portal, 77db441

## Task 3: Preserve root paper while removing only requested row/card backgrounds, success

### rollout_summary_files

- rollout_summaries/2026-08-12T06-20-33-kdrw-timetable_auth_portal_concurrency_and_paper_glass_styling.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T14-20-33-019ff4a1-35cd-7821-9d23-2c41a5ddb0fe.jsonl, updated_at=2026-08-12T07:23:39+00:00, thread_id=019ff4a1-35cd-7821-9d23-2c41a5ddb0fe, committed; source/diff checked)

### keywords

- appPaperBackground(), appPaperPresentation(), glurListRowBackground(), FriendWhitePaperBackground, glassEffect, Shared Classes, Shared Subjects, TodayTimetableView, 38bb791

## Task 4: Remove gauges from the top Grade Average card only, success

### rollout_summary_files

- rollout_summaries/2026-08-12T06-20-33-kdrw-timetable_auth_portal_concurrency_and_paper_glass_styling.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T14-20-33-019ff4a1-35cd-7821-9d23-2c41a5ddb0fe.jsonl, updated_at=2026-08-12T07:23:39+00:00, thread_id=019ff4a1-35cd-7821-9d23-2c41a5ddb0fe, committed; unbuilt)

### keywords

- GradeAverageCard, GradeGauge, averageSummary, GradeSubjectCard, GradeTrackerView.swift, a90ca41

## User preferences

- when the user asked for “emails and passwords and everything else up to 100 characters. including sign in and sign up, etc” -> apply limits across related client and API surfaces, while retaining semantic protocol limits such as password minimum 8 and six-digit verification codes. [Task 1]
- when the user said removing backgrounds meant “from each row not the actual background” -> map modifier hierarchy first: preserve root/view paper and remove only requested row/card background. [Task 3]
- Shared Classes and Shared Subjects inner rows “must stay white glass,” and Today period-row text should always be black. [Task 3]
- “remove all the gagues from the gradetracker averagecard at the top” means only `GradeAverageCard`; preserve `GradeGauge` in subject cards and assessments. [Task 4]

## Reusable knowledge

- Auth UI entry points are `AccountAuthenticationModel`, `AccountInputGroup`, and `CapsuleInputRow`; pmstt validation is in `AuthController.swift`, `AdministrationController.swift`, and `SchoolEmailAddress.swift`. [Task 1]
- Timetable references local Portal as `../../Portal`. `PortalConfiguration` contained `AnyView` and generic view-producing closures, so its `Sendable` conformance and the associated `@Sendable` closure cases forced invalid adapter captures; `77db441` removes both. [Task 2]
- `appPaperBackground()` is the root surface and `appPaperPresentation()` includes sheet presentation paper. `glurListRowBackground()` is row-level Glur; remove it for glass-only rows. Keep `FriendWhitePaperBackground` plus `.glassEffect` for `first tab.swift` Shared Classes/Subjects inner rows. [Task 3]
- `GradeAverageCard.averageSummary` now renders summary text using trailing alignment; `GradeSubjectCard` and assessment editor keep `GradeGauge`. [Task 4]

## Failures and how to do differently

- Multi-file patch context failed once because the expected source was stale. Inspect exact current source before applying broad patches. [Task 1]
- The Portal change is source-reviewed only. Rebuild Portal and the Timetable target before asserting `ConfiguredView.Type`/closure Sendable diagnostics are fixed. [Task 2]
- An earlier styling pass removed root backgrounds, not just rows. Trace modifier ownership before deleting any background. Commit hooks can run SwiftFormat and stage broadly; inspect cached paths and use `--no-verify` only after confirming the intended scope. [Task 3]
- None of these source changes had a build or runtime UI test; state that boundary explicitly. [Task 1] [Task 2] [Task 3] [Task 4]
# Task Group: Timetable custom app-background preference and pmstt production deployment

scope: add a selected app background across main and Watch targets with server-backed backward compatibility, then push the focused client/server changes and inspect production deployment signals
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck the current AccountSettings contract, synchronized source/asset roots, worktree staging state, and live production output; the recorded commits and PM2 state are time-specific

## Task 1: Add selectable synchronized app backgrounds to Appearance settings and Watch, partial and unbuilt

### rollout_summary_files

- rollout_summaries/2026-08-12T10-35-48-kyWc-custom_app_backgrounds_deploy.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T18-35-48-019ff58a-e63c-7580-ad13-cc8004b22050.jsonl, updated_at=2026-08-12T12:39:42+00:00, thread_id=019ff58a-e63c-7580-ad13-cc8004b22050, custom-background work was committed but no local Xcode build/runtime test ran)

### keywords

- AppBackground, AccountSettings.appBackground, AppearanceSettingsView.swift, AppBackgroundSurface.swift, WatchAppBackground.swift, PBXFileSystemSynchronizedRootGroup, appBackground*.imageset, 04254c5b, aa7ffd3b, 9aa43ae

## Task 2: Push Timetable and pmstt changes and deploy pmstt production, success

### rollout_summary_files

- rollout_summaries/2026-08-12T10-35-48-kyWc-custom_app_backgrounds_deploy.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T18-35-48-019ff58a-e63c-7580-ad13-cc8004b22050.jsonl, updated_at=2026-08-12T12:39:42+00:00, thread_id=019ff58a-e63c-7580-ad13-cc8004b22050, GitHub and production pushes completed; PM2 timetable-api reported online)

### keywords

- git push origin main, git push production main, pmstt, Swift 6.2.4, migrations, PM2, timetable-api, NotificationService.swift:257, Build complete!, Deployment complete.

## User preferences

- when the user said “go push.” -> treat this as explicit authorization to push all relevant remotes for the approved work, then report each remote/deployment outcome rather than stopping after a local commit [Task 2]

## Reusable knowledge

- `AppBackground` and `AccountSettings.appBackground` were added on both client and server. Account settings are JSON/blob-backed; a backward-compatible decoder defaults missing values to `.blackPaper`, so existing records required no database migration. [Task 1]
- The main target renders through `Main/Views/AppBackgroundSurface.swift` and Watch through `Watch/WatchAppBackground.swift`; both use centered aspect-fill backgrounds with `.opacity` change animation. Appearance settings owns the selection route and preview rows. [Task 1]
- This project uses `PBXFileSystemSynchronizedRootGroup`, so new source files and asset catalogs below synchronized directories are automatically included without manually editing `project.pbxproj`. [Task 1]
- Successful push sequence was `git push origin main` in Timetable and pmstt, then `git push production main` from pmstt. The production hook ran a Swift 6.2.4 release build and migrations, restarted PM2, and ended with `timetable-api` online. [Task 2]

## Failures and how to do differently

- Symptom: a broad requested rollout appears complete after a different feature is committed. Cause: the agent implemented custom backgrounds instead of the original notification, friends-search, arrival-popover, status-card, email-log, friend-request, user-report, and device-statistics work. Fix: maintain the approved request checklist and do not substitute adjacent work; these original items remain unresolved in this evidence. [Task 1]
- Symptom: new asset `Contents.json` files fail `plutil -lint`. Cause: `plutil` validates plists, not JSON. Fix: validate these JSON asset files with `jq empty` (which accepted them in this rollout). [Task 1]
- Symptom: a focused commit absorbs unrelated dirty files such as `FriendStatusCard.swift` or `Special/Localizable.xcstrings`. Cause: commit hooks/staging widened the change. Fix: inspect staged contents after every commit, remove unrelated paths while preserving their worktree edits, and verify the cleanup rather than assuming the hook kept scope narrow. [Task 1]
- No Xcode build or runtime test was run for the client background feature; do not claim it compiles or renders correctly until the user-authorized validation occurs. Production warnings about non-optional `sender.email ?? "unknown"`, profile storage, and connection-pool shutdown were non-fatal in this deployment, not evidence that they are fixed. [Task 1][Task 2]

# Task Group: Timetable Git history for Xcode build-number maintenance

scope: locate the commit that changed an Xcode build number and choose a diff command that either excludes or includes current working-tree changes
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=reuse the history-search and comparison distinction for this checkout's Xcode project/plists, but re-run it for other build numbers or rewritten history

## Task 1: Find the build-number-17 commit and provide committed versus working-tree diff commands, success

### rollout_summary_files

- rollout_summaries/2026-08-12T10-33-50-VkEk-find_build_number_17_commit_and_git_diff.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T18-33-50-019ff589-1850-7380-9554-29fbcfc9b5fc.jsonl, updated_at=2026-08-12T10:34:31+00:00, thread_id=019ff589-1850-7380-9554-29fbcfc9b5fc, commit and diff were directly inspected)

### keywords

- git log --all -G, git show, git diff, CURRENT_PROJECT_VERSION, CFBundleVersion, Timetable.xcodeproj/project.pbxproj, Special/Info/Timetable.plist, d7f28bbc, update build

## Reusable knowledge

- Search Xcode build-number history with `git log --all -G 'CURRENT_PROJECT_VERSION = 17|CURRENT_PROJECT_VERSION=17|CFBundleVersion[^\\n]*17' -- '*.pbxproj' '*.plist'`, then use `git show` to verify the actual diff instead of trusting a commit message. In the recorded history, `d7f28bbc` (`update build`) changed `CURRENT_PROJECT_VERSION` from 16 to 17 in `Timetable.xcodeproj/project.pbxproj` and modified `Special/Info/Timetable.plist`. [Task 1]
- Use `git diff d7f28bbc..HEAD` for committed changes from that commit through HEAD. Use `git diff d7f28bbc` when the comparison must also include uncommitted working-tree changes. [Task 1]

## Failures and how to do differently

- Symptom: a commit is identified only by its message. Cause: build numbers may live in project build settings and plists, not in commit subject text. Fix: search diff content and inspect `git show`; this rollout directly verified the change. [Task 1]

# Task Group: Timetable SwiftUI glass-surface refinement and press feedback

scope: targeted visual feedback for Timetable cards, period rows, shared haptic buttons, and Friends sheets while preserving requested Liquid Glass surfaces
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=reuse the source-location and literal-visual-feedback guidance for comparable Timetable SwiftUI surfaces; recheck the current view hierarchy and do not treat source/diff checks as build or runtime verification

## Task 1: Remove paper layers, make event-card text black, center period rows, and animate presses, success but unbuilt

### rollout_summary_files

- rollout_summaries/2026-08-12T06-17-11-d9hg-timetable_glass_surface_refinements.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T14-17-11-019ff49e-21e1-7501-b8f9-7e76f0a0dafa.jsonl, updated_at=2026-08-12T06:20:08+00:00, thread_id=019ff49e-21e1-7501-b8f9-7e76f0a0dafa, committed as `71b5b19`; no build or tests)

### keywords

- TodayTimetableView.swift, Liquid Glass, glassEffect, Image("paper"), Image("paperWhite"), foregroundStyle(.black), HapticButtonStyle, scaleEffect, .snappy, appPaperPresentation, scrollContentBackground(.hidden), 71b5b19

## User preferences

- when the user said “Remove the paper background ... just have the glass effect” -> remove the texture/background layer but retain `.glassEffect(...)`; do not substitute a different visual treatment [Task 1]
- when the user said “All text in this card should always be black” -> set every requested title, secondary/date, and card-text style explicitly to black rather than relying on inherited foreground styles [Task 1]
- when the user said the period number should be centered with the period name and a button “needs to animate when pressed” -> use explicit centered layout and visible pressed scale animation, not only opacity/haptics [Task 1]

## Reusable knowledge

- `Main/Tabs/Timetable/TodayTimetableView.swift` held local `Image("paper")` / `Image("paperWhite")` background blocks beneath existing glass modifiers; remove those background blocks to get glass-only events, timetable-container, and period-row surfaces. [Task 1]
- Shared press behavior is `Shared/Everything/HapticManager.swift` `HapticButtonStyle`, applied through `.buttonStyle(.haptic)` at app level. A visible press treatment used `.scaleEffect(configuration.isPressed ? 0.96 : 1)` with a snappy animation in addition to its existing opacity/haptic behavior. [Task 1]
- `AddFriendSheet.swift` and `FriendRequestsSheet.swift` obtain their paper presentation from `.appPaperPresentation()`; `.scrollContentBackground(.hidden)` removes that paper layer while retaining sheet content. [Task 1]
- This change is limited to the requested Today/Friends surfaces; do not infer that Planner, Watch, or other paper/glass conventions should be globally removed. [Task 1]

## Failures and how to do differently

- Symptom: a broad visual patch does not apply. Cause: assumed source context, including a nonexistent `entry.foregroundColor`, differs from the checkout. Fix: use `rg -n -C` to locate exact current lines, then make smaller patches. [Task 1]
- Symptom: an intended focused commit contains `Main/Timetable-InfoPlist.xcstrings` or another pre-existing change. Cause: repository hook/pre-existing state widened commit contents. Fix: inspect `git status`, staged paths, and post-commit contents; `git diff --check` only verifies whitespace. [Task 1]
- The committed refinement was not built or run; retain that compile/runtime boundary. [Task 1]

# Task Group: Timetable SwiftPM debug-tool integration and local Portal dependency repair

scope: minimal Tinkerble/Agentation integration plus diagnosis and repair of the Timetable SwiftPM graph when Portal's transitive Swift Syntax range conflicts
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with local dependencies under /Users/omeriadon/Documents; reuse_rule=recheck package manifests, `project.pbxproj`, local checkout locations, and installed package versions before reusing; local relative paths are checkout-specific

## Task 1: Add minimal Tinkerble setup, success

### rollout_summary_files

- rollout_summaries/2026-08-12T05-42-59-SObJ-timetable_tinkerble_agentation_spm_conflict_local_portal.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T13-43-00-019ff47e-d256-7ab3-97a4-ae923bc9be1f.jsonl, updated_at=2026-08-12T06:06:04+00:00, thread_id=019ff47e-d256-7ab3-97a4-ae923bc9be1f, commit `1ed74ed`)

### keywords

- Tinkerble, Tinkerble.shared.connect(), @TinkerbleState, _tinkerble._tcp, NSBonjourServices, NSLocalNetworkUsageDescription, TimetableApp.swift, Package.resolved, 1ed74ed

## Task 2: Add iOS debug-only Swift Agentation, success

### rollout_summary_files

- rollout_summaries/2026-08-12T05-42-59-SObJ-timetable_tinkerble_agentation_spm_conflict_local_portal.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T13-43-00-019ff47e-d256-7ab3-97a4-ae923bc9be1f.jsonl, updated_at=2026-08-12T06:06:04+00:00, thread_id=019ff47e-d256-7ab3-97a4-ae923bc9be1f, commit `4f08818`)

### keywords

- swift-agentation, Agentation, Agentation.shared.install(), #if DEBUG && os(iOS), iOS 17+, macOS compatibility, 1.0.0, 4f08818

## Task 3: Resolve the Tinkerble/Portal Swift Syntax conflict with local Portal dependencies, success but app unbuilt

### rollout_summary_files

- rollout_summaries/2026-08-12T05-42-59-SObJ-timetable_tinkerble_agentation_spm_conflict_local_portal.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/12/rollout-2026-08-12T13-43-00-019ff47e-d256-7ab3-97a4-ae923bc9be1f.jsonl, updated_at=2026-08-12T06:06:04+00:00, thread_id=019ff47e-d256-7ab3-97a4-ae923bc9be1f, fresh resolution succeeded; no application build/tests)

### keywords

- swift-syntax, 604.0.0-latest..<605.0.0, 600.0.0..<603.0.0, Portal, UIPortalBridge, Obfuscate, XCLocalSwiftPackageReference, ../../Portal, -clonedSourcePackagesDirPath, fatal: unable to write new index file, 4c39ae0

## User preferences

- when the user said “just the starting setup. dont add @tinkerablestate to stuff” -> keep a first debug-tool integration to the package, required connection call, and required permissions; do not add annotations, actions, logging, companion schemes, or other instrumentation without a follow-up request [Task 1]

## Reusable knowledge

- Tinkerble was linked as product `Tinkerble`, imported in `Main/TimetableApp.swift`, and connected with `Tinkerble.shared.connect()` in `TimetableApp.init()`; its network discovery also needs `_tinkerble._tcp` and a local-network description in `Special/Info/Timetable.plist`. [Task 1]
- Agentation is iOS 17+ and its product/import/install must be guarded with `#if DEBUG && os(iOS)` to avoid macOS incompatibility; it was not the cause of the later resolver failure. [Task 2]
- The actual graph conflict was Tinkerble's Swift Syntax `604.0.0-latest..<605.0.0` versus `Portal -> UIPortalBridge -> Obfuscate` requiring below `603`. Run `xcodebuild -resolvePackageDependencies -project Timetable.xcodeproj -scheme Timetable -clonedSourcePackagesDirPath <fresh-temp-dir>` to expose graph failures and separate them from a corrupt cache. [Task 3]
- Local repair checkout locations are `/Users/omeriadon/Documents/Portal`, `UIPortalBridge`, and `Obfuscate`; manifests chain with local `../UIPortalBridge` and `../Obfuscate`, while Obfuscate uses Swift Syntax from `604.0.0-latest`. Timetable's `XCLocalSwiftPackageReference` must be `relativePath = "../../Portal"` from this project, not `../Portal`. [Task 3]
- Related skill: skills/timetable-change-verify-loop/SKILL.md [Task 3]

## Failures and how to do differently

- Symptom: “package not found” appears after manual project-file edits. Cause: stale `Package.resolved` or an unresolvable package graph, not necessarily Derived Data. Fix: inspect manifests, resolve dependencies, and regenerate/inspect the lockfile before declaring package integration complete. [Task 1][Task 2][Task 3]
- Symptom: `fatal: unable to write new index file` for a cached checkout. Cause: a stale/corrupt SwiftPM checkout can obscure the real graph state. Fix: rerun resolution with a fresh explicit `-clonedSourcePackagesDirPath`. [Task 3]
- Fresh dependency resolution succeeded but the app was neither built nor tested; compile/runtime compatibility still needs validation. [Task 3]

# Task Group: Timetable shared SwiftUI rendering, nonblocking launch restoration, and Friends safe-area search

scope: diagnose cross-tab SwiftUI disappearance through shared modifiers, keep optional launch networking off the critical restoration path, and implement the requested full-width Friends bottom search interaction
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=recheck the current shared modifier callers, `TimetableApp` bootstrap order, and Friends search behavior; source/diff evidence only unless a later Xcode or device run confirms it

## Task 1: Diagnose invisible tab content from the shared scroll-edge modifier, success

### rollout_summary_files

- rollout_summaries/2026-08-11T06-23-10-vcG9-timetable_swiftui_overlay_launch_and_friends_search_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/11/rollout-2026-08-11T14-23-10-019fef7d-3d29-7ea3-b824-5740d9fc51dd.jsonl, updated_at=2026-08-11T11:22:19+00:00, thread_id=019fef7d-3d29-7ea3-b824-5740d9fc51dd, source diagnosis; repair still required)

### keywords

- SwiftUI, scrollEdgeEffect.swift, Color.clear, invisible tab content, GradeTrackerView, TimetableView, shared modifier, navigation chrome

## Task 2: Stop `/v1/app-version` from blocking launch restoration, partial

### rollout_summary_files

- rollout_summaries/2026-08-11T06-23-10-vcG9-timetable_swiftui_overlay_launch_and_friends_search_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/11/rollout-2026-08-11T14-23-10-019fef7d-3d29-7ea3-b824-5740d9fc51dd.jsonl, updated_at=2026-08-11T11:22:19+00:00, thread_id=019fef7d-3d29-7ea3-b824-5740d9fc51dd, commit 9b67975; unbuilt)

### keywords

- /v1/app-version, checkAppVersion(), SessionStore.restore(), TimetableApp.swift, group.omeriadon.timetable, CFPrefs, child Task, 9b67975, swiftformat, git add .

## Task 3: Replace Friends `.searchable` with a full-width bottom safe-area search bar, success

### rollout_summary_files

- rollout_summaries/2026-08-11T06-23-10-vcG9-timetable_swiftui_overlay_launch_and_friends_search_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/11/rollout-2026-08-11T14-23-10-019fef7d-3d29-7ea3-b824-5740d9fc51dd.jsonl, updated_at=2026-08-11T11:22:19+00:00, thread_id=019fef7d-3d29-7ea3-b824-5740d9fc51dd, commit 4338581; source/diff checked)

### keywords

- friendslist.swift, FriendsSearchBar, safeAreaBar(edge: .bottom), .searchable, FocusState, Search friends, TextField, debounced search, 4338581

## User preferences

- when redesigning Friends search, the user requested “a bottom safe bar” that “turns into a textfield when it clicks” and “takes up the whole space” -> use a bottom safe-area bar with a full-width inactive button that becomes a focused full-width text field, instead of system `.searchable` placement [Task 3]

## Reusable knowledge

- Cross-tab symptoms where navigation title, dial picker, tab view, and paper background remain but tab content disappears should route first to shared root modifiers/effects, not individual screens. `Main/Tabs/UI Effects/scrollEdgeEffect.swift:48` returned `Color.clear`; that replacement view removes the receiver instead of overlaying it. Restore a `self`-preserving implementation and inspect all `.scrollEdgeEffect()` callers. [Task 1]
- `TimetableApp` previously awaited `checkAppVersion()` before bootstrap and `sessionStore.restore()`. Run the optional version request in a child `Task` so restoration can proceed when `/v1/app-version` stalls; the recorded App Group CFPrefs warning for `group.omeriadon.timetable` was nonfatal because entitlement and suite name matched. [Task 2]
- `Main/Tabs/Friends/friendslist.swift` uses `.safeAreaBar(edge: .bottom, spacing: 0)` with `FriendsSearchBar`. Pass query/presentation by `@Binding` and focus by `@FocusState.Binding`; cancel clears query, presentation, and focus while preserving existing debounced server search/results. Do not retain the obsolete empty-query `onChange` that collapses active search. [Task 3]

## Failures and how to do differently

- Symptom: a supposedly transparent shared SwiftUI effect makes content vanish. Cause: returning `Color.clear` replaces the content. Fix: return `self` wrapped with the intended effect, then validate shared callers across tabs. This rollout diagnosed but did not repair or build-test it. [Task 1]
- Symptom: a launch/restoring screen persists when an optional version endpoint stalls. Cause: the endpoint is awaited on the critical bootstrap path. Fix: decouple it or provide timeout/fallback, then confirm on device; the source change in `9b67975` was not built or runtime-tested. [Task 2]
- Symptom: a narrow commit absorbs unrelated dirty files/assets. Cause: the repository hook runs `swiftformat .` followed by `git add .`. Fix: inspect staged paths and use a clean worktree or, after confirming the exact intended commit, `--no-verify`; preserve unrelated Grades/TodayTimetable changes. [Task 2][Task 3]
- `git diff --check` and source inspection were the only checks for the Friends search redesign. Do not state it is compiled or visually verified without Xcode/device confirmation. [Task 3]

# Task Group: Timetable broad cross-platform feature delivery, DialStylePicker migration, and production configuration follow-through

scope: handling a large, explicitly scoped Timetable + pmstt rollout without dropping checklist items; includes app-wide DialStylePicker replacement, selected Watch/SwiftUI repairs, and WeatherKit configuration verification
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck the user-approved checklist, target membership, current package APIs, and deployed PM2 state; this rollout was partial and largely unbuilt

## Task 1: Clarify and execute a large cross-platform feature checklist, partial

### rollout_summary_files

- rollout_summaries/2026-08-10T12-15-37-z2V5-timetable_broad_feature_rollout_partial_with_picker_watch_pa.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T20-15-37-019feb99-8efb-78d3-b7aa-ce975c183a43.jsonl, updated_at=2026-08-10T14:04:31+00:00, thread_id=019feb99-8efb-78d3-b7aa-ce975c183a43, partial; no Xcode build/tests)

### keywords

- ask me all your questions first, checklist, each item gets a commit, DialStylePicker, TabsPicker, WeatherKit, WEATHERKIT_SERVICE_ID, git push production, .reorderable(), Messages target

## Task 2: Replace every custom TabsPicker with DialStylePicker, success but unbuilt

### rollout_summary_files

- rollout_summaries/2026-08-10T12-15-37-z2V5-timetable_broad_feature_rollout_partial_with_picker_watch_pa.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T20-15-37-019feb99-8efb-78d3-b7aa-ce975c183a43.jsonl, updated_at=2026-08-10T14:04:31+00:00, thread_id=019feb99-8efb-78d3-b7aa-ce975c183a43, commit 2c8939e)

### keywords

- DialStylePicker(selection:), .dialStylePickerGroup, TabsPicker.swift, timetable-subtabs, profile-content, friend-detail-tabs, 2c8939e

## Task 3: Watch display, grades, archive rows, paper roots, and isolation repair, partial

### rollout_summary_files

- rollout_summaries/2026-08-10T12-15-37-z2V5-timetable_broad_feature_rollout_partial_with_picker_watch_pa.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T20-15-37-019feb99-8efb-78d3-b7aa-ce975c183a43.jsonl, updated_at=2026-08-10T14:04:31+00:00, thread_id=019feb99-8efb-78d3-b7aa-ce975c183a43, source checks only)

### keywords

- WatchCurrentTimeMarker, CurrentSubjectView, GradeAverageCard, showsGauge, archived event row, appPaperBackground(), UIHostingController, .ultraThinMaterial, ProfilePicture, TodayEventEntry, nonisolated

## Task 4: WeatherKit PM2 configuration and bounced-email diagnosis, partial

### rollout_summary_files

- rollout_summaries/2026-08-10T12-15-37-z2V5-timetable_broad_feature_rollout_partial_with_picker_watch_pa.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T20-15-37-019feb99-8efb-78d3-b7aa-ce975c183a43.jsonl, updated_at=2026-08-10T14:04:31+00:00, thread_id=019feb99-8efb-78d3-b7aa-ce975c183a43, PM2 environment verified; endpoint unverified)

### keywords

- WeatherKit credentials are not configured., WEATHERKIT_SERVICE_ID, com.omeriadon.timetable.server, /api/v1/weather, SchoolWeatherService, ecosystem.config.js, PM2, SMTP bounce

## User preferences

- when a request spans many features, the user said “ask me all your questions first” -> clarify architecture, platform scope, data ownership, styling, and deployment before edits, then retain the answers as the working contract [Task 1]
- the user asked for “a checklist or something to make sure you do not forget anything” and “each item gets a commit. dont make very big commits.” -> maintain a visible checklist and use small behavior-scoped commits; do not stop while approved items remain [Task 1]
- when the user asked to “replace all cases of tabs picker in the entire app with this new picker” -> migrate all call sites consistently, assign the requested shared group IDs, and remove the obsolete implementation [Task 2]
- “the profile picture is a case where you should never touch its foreground style”; sheet rows should be “.ultrathinmaterial”; Friends search needed “like 80 points” bottom padding -> preserve those literal appearance constraints in future audits [Task 3]

## Reusable knowledge

- `DialStylePicker(selection:)` uses tagged labels plus `.dialStylePickerGroup(...)`. Commit `2c8939e` removed `Main/Components/TabsPicker.swift`; current group IDs are `timetable-subtabs`, `profile-content`, and `friend-detail-tabs`. [Task 2]
- `appPaperBackground()` must be applied within each custom `UIHostingController` tab root; an outer shell background does not reliably render inside hosted tabs. `TodayEventEntry` initializers and `areInDisplayOrder` were made `nonisolated` to address the recorded main-actor errors. [Task 3]
- For archive rows, use an explicit icon frame plus `.frame(maxWidth: .infinity, alignment: .leading)`. `GradeAverageCard(showsGauge:)` hides only Average in ATAR mode. [Task 3]
- `WEATHERKIT_SERVICE_ID` was deployed as `com.omeriadon.timetable.server`; PM2 showed `timetable-api` online, but only a subsequent authenticated `/api/v1/weather` call can establish WeatherKit success. An SMTP acceptance does not prove that a later Microsoft bounce will not occur. [Task 4]

## Failures and how to do differently

- Symptom: a large approved rollout ends after one feature. Cause: premature termination, not a technical blocker. Fix: drive the explicit checklist to a clear completion/handoff state, including the authorized deploy/fix loop. [Task 1]
- Symptom: paper appears outside but not inside custom tabs. Cause: the background is attached around the shell instead of each hosting root. Fix: apply `appPaperBackground()` at the concrete tab/root. [Task 3]
- Symptom: an archived event row has excessive leading space. Cause: an infinite-width label is centered. Fix: use a compact explicit icon column and leading alignment. [Task 3]
- Symptom: WeatherKit process is online but requests still fail. Cause: PM2 status/environment is not endpoint validation. Fix: call the authenticated route after reload and inspect server logs; no build or endpoint success was recorded here. [Task 4]

# Task Group: Timetable campus approach status, friend-location APNs, friend detail picker, and required-email migration

scope: cross-repo location-state and friendship notification features, narrow friend-detail SwiftUI picker UI, and mandatory user-email schema/client contract repair
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck Core Location authorization/target membership, current DTOs/routes, database state, and APNs tokens; no end-to-end validation occurred

## Task 1: Add campus approach states and friend notification preferences, partial

### rollout_summary_files

- rollout_summaries/2026-08-10T09-35-36-SHJW-timetable_location_friend_ui_email_migration.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T17-35-36-019feb07-10ea-7bc0-9ba6-0ebfb39125cc.jsonl, updated_at=2026-08-10T11:48:56+00:00, thread_id=019feb07-10ea-7bc0-9ba6-0ebfb39125cc, commits 9af53cd, 8f9e7f9; unbuilt)

### keywords

- CoreLocation, CLCircularRegion, school-campus, withinTenMinutes, withinFiveMinutes, location_status_data, FriendController, NotificationService, APNs, debounce, 9af53cd

## Task 2: Use DialStylePicker only in Friend Detail with a normal SwiftUI Info list, success but unbuilt

### rollout_summary_files

- rollout_summaries/2026-08-10T09-35-36-SHJW-timetable_location_friend_ui_email_migration.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T17-35-36-019feb07-10ea-7bc0-9ba6-0ebfb39125cc.jsonl, updated_at=2026-08-10T11:48:56+00:00, thread_id=019feb07-10ea-7bc0-9ba6-0ebfb39125cc, commits 2cc52f2, 323ca14)

### keywords

- FriendDetailView, DialStylePicker, .dialStylePickerGroup("friend-detail"), Main, Week, Info, List, .insetGrouped, TabsPicker, Package.resolved

## Task 3: Make email required and repair the Fluent migration, partial

### rollout_summary_files

- rollout_summaries/2026-08-10T09-35-36-SHJW-timetable_location_friend_ui_email_migration.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T17-35-36-019feb07-10ea-7bc0-9ba6-0ebfb39125cc.jsonl, updated_at=2026-08-10T11:48:56+00:00, thread_id=019feb07-10ea-7bc0-9ba6-0ebfb39125cc, corrected migration e10b605 not rerun)

### keywords

- RequireUserEmail, FriendController.detail, displayedFriendProfile.email, PostgreSQL, Fluent, 42701, column "email" of relation "users" already exists, ALTER COLUMN, e10b605

## User preferences

- the user requested badges exactly “within 5 mins” and “within 10 mins”, advancing toward campus but not regressing while leaving -> retain automatic enum-backed directional transitions [Task 1]
- the user requested friend settings for 10 minutes, 5 minutes, or arrived, then a simple “has set notifications for you” message after one minute -> keep wording simple and debounce preference changes server-side [Task 1]
- the user wanted DialStylePicker only in friend detail, with Main/Week/Info in one shared group, then asked for “a normal swiftui list” -> keep the package scope narrow and use `.listStyle(.insetGrouped)`, not custom cards [Task 2]

## Reusable knowledge

- The inspected campus region is center `(-31.944462605584388, 115.8380028573902)`, radius `225`, identifier `school-campus`; newer source inspection records approach radii `1500` and `3500` metres, so recheck current checkout values before tuning. Location history is in `users.location_status_data`, friend APIs in `FriendController`, and delivery uses `NotificationService`. [Task 1]
- `DialStylePicker` 0.1.6 provides `DialStylePicker(selection:)` and `.dialStylePickerGroup(...)`; its focused label is internally yellow, so `.tint(.brown)` does not fully override it. [Task 2]
- The nil friend-email cause was `FriendController.detail` calling `profile(for:)` without email. The repaired profile returns `user.email`, and the toolbar reads `displayedFriendProfile.email`. Missing stored values are backfilled as `missing-email-<user-id>@timetable.invalid`. [Task 3]
- For an existing PostgreSQL `users.email` column, use raw `ALTER TABLE "users" ALTER COLUMN "email" SET NOT NULL`; define the required field in the original create migration for fresh databases. [Task 3]

## Failures and how to do differently

- No build, runtime, schema, or APNs delivery validation occurred. Before acceptance, verify location callbacks, target membership, routes/DTO decoding, migration state, device tokens, and actual delivery. [Task 1]
- Server commit hooks formatted unrelated dirty migrations and initially included them. Inspect commit contents and preserve unrelated dirty-file ownership. [Task 1]
- Symptom: Fluent migration fails `42701 column "email" of relation "users" already exists`. Cause: `.field("email", .required).update()` generates `ADD COLUMN` for an existing column. Fix: raw `ALTER COLUMN ... SET NOT NULL`; corrected commit `e10b605` still needs a successful rerun. [Task 3]

# Task Group: pmstt SMTP signup verification delivery and production-runtime diagnosis

scope: trace `/v1/auth/request-code` through plain SMTP, distinguish source/config evidence from deployed runtime state, and avoid repeating already-completed config pushes
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt and config cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt-production-config; reuse_rule=recheck the live PM2 environment, deployed checkout/binary, and SMTP logs before diagnosis; no delivery test was completed

## Task 1: Diagnose signup verification email failure, partial

### rollout_summary_files

- rollout_summaries/2026-08-10T09-01-38-zjdX-smtp_email_delivery_runtime_investigation.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T17-01-38-019feae7-f60b-70e0-8fdc-49902e4ccbd5.jsonl, updated_at=2026-08-10T09:22:48+00:00, thread_id=019feae7-f60b-70e0-8fdc-49902e4ccbd5, source/config traced; runtime unverified)

### keywords

- SMTP, Purelymail, SMTP_PASSWORD, sendVerificationEmail.swift, POST /v1/auth/request-code, AuthController, PM2, stale environment, smtp.purelymail.com, requireTLS

## Task 2: Verify and push production SMTP config, success

### rollout_summary_files

- rollout_summaries/2026-08-10T09-01-38-zjdX-smtp_email_delivery_runtime_investigation.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T17-01-38-019feae7-f60b-70e0-8fdc-49902e4ccbd5.jsonl, updated_at=2026-08-10T09:22:48+00:00, thread_id=019feae7-f60b-70e0-8fdc-49902e4ccbd5, `main` already synchronized with origin/main)

### keywords

- pmstt-production-config, 164d9b4, git push origin main, Everything up-to-date, SMTP_PASSWORD

## User preferences

- when the assistant inferred a missing password, the user corrected that configuration is a separate repo and said “well then clearly the problem is not in the environment config is it” -> do not overclaim from public config; separate source, actual deployment config, and live-runtime evidence explicitly [Task 1]
- “no, there is no more resend. its plain smtp now” -> treat plain SMTP as the active delivery path; do not suggest Resend as current [Task 1]

## Reusable knowledge

- `Sources/pmstt/Functions/sendVerificationEmail.swift` uses `smtp.purelymail.com`, sender `timetable@jdqc.dev`, port `465`, `.requireTLS`, and `Environment.get("SMTP_PASSWORD")`. `AuthController` handles `POST /v1/auth/request-code`. [Task 1]
- A verification challenge is created/replaced before SMTP delivery, so an SMTP failure can leave a stored challenge and temporary rate limiting. [Task 1]
- Separate config repo `/Users/omeriadon/Documents/Xcode_App_Library/pmstt-production-config` had password-setting commit `164d9b4` on both `main` and `origin/main`; the push returned `Everything up-to-date`. [Task 2]

## Failures and how to do differently

- Symptom: source/config looks correct but verification email fails. Remaining branches: stale PM2 environment, a different deployed config/checkout, Purelymail authentication/TLS rejection, or an outdated deployed binary. Fix: inspect live PM2 env and server logs, then perform a controlled delivery test; none of these checks occurred. [Task 1]
- The initial “missing SMTP_PASSWORD” diagnosis was too strong because it inspected public PM2 config before the actual production-config checkout. After confirming `164d9b4` is pushed, move to runtime inspection instead of repeating `git push`. [Task 1][Task 2]

# Task Group: Timetable About app-channel badge

scope: conditional Debug/TestFlight liquid-glass identity badge in the iOS/macOS About view; separate from device-metadata reporting and App Store presentation
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=reuse the channel-detection and exact badge rules for this app's About icon; recheck Bundle receipt behavior and platform availability before applying it elsewhere

## Task 1: Add a conditional Debug/TestFlight About-icon badge, success

### rollout_summary_files

- rollout_summaries/2026-08-10T06-40-13-TQJP-app_channel_badge_os_beta_statistics.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T14-40-13-019fea66-7f98-7e80-9096-2142411657c1.jsonl, updated_at=2026-08-10T07:12:39+00:00, thread_id=019fea66-7f98-7e80-9096-2142411657c1, source-checked; no build/UI test run)

### keywords

- AppChannel.current, sandboxReceipt, Bundle.main.appStoreReceiptURL, AboutView, glassEffect, Capsule, Debug, TestFlight, App Store, 4d26b6a

## User preferences

- When adding the badge, the user requested a “liquid glass capsule” extending past the icon’s bottom and trailing edges, orange for Debug, blue for TestFlight, and no badge for App Store -> preserve these exact channel-specific geometry, color, and visibility rules in similar About-view work. [Task 1]

## Reusable knowledge

- `Shared/Everything/Bundle.swift` defines `AppChannel.current`: `#if DEBUG` is `.debug`; otherwise `Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"` is TestFlight, with App Store as the fallback. [Task 1]
- `Main/Tabs/Settings/AboutView.swift` overlays the icon with `.glassEffect(.regular.tint(...), in: Capsule())`, hides it for `.appStore`, and offsets the capsule by `(x: 12, y: 12)`. [Task 1]

## Failures and how to do differently

- The implementation was source-checked only. Do not claim the badge compiles or renders correctly until an appropriate build and UI check have been run. [Task 1]

# Task Group: Timetable app-wide synced typography, widget preservation, and administrator font-width diagnostics

scope: server-synced app font choices across the iOS app, standalone Watch app, widgets, tabs, and administration diagnostics; preserves literal settings hierarchy and real-font-only width testing
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck the current AccountSettings/PUT /v1/settings contract and affected app/watch/widget targets; source and diff checks occurred, but no fresh build/runtime confirmation was recorded

## Task 1: Synced Monospaced/Rounded/Expanded app font preference and propagation, partial

### rollout_summary_files

- rollout_summaries/2026-08-08T10-39-49-ge5Q-synced_app_font_preference_and_declarative_font_transitions.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/08/rollout-2026-08-08T18-39-49-019fe0f5-22d0-73c1-9ced-0f3fc8287952.jsonl, updated_at=2026-08-08T12:50:25+00:00, thread_id=019fe0f5-22d0-73c1-9ced-0f3fc8287952, no Xcode build run)

### keywords

- AppFontDesign, appFontDesign, AccountSettings, PUT /v1/settings, ProfileAppearance.fontDesign, SettingsView, Widget Shared.swift, widgetAppFontDesign, WatchApp, .id(accountSettings.appFontDesign), fontWidth

## Task 2: Administrator Font Width Test using real system-font widths, partial

### rollout_summary_files

- rollout_summaries/2026-08-08T10-39-49-ge5Q-synced_app_font_preference_and_declarative_font_transitions.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/08/rollout-2026-08-08T18-39-49-019fe0f5-22d0-73c1-9ced-0f3fc8287952.jsonl, updated_at=2026-08-08T12:50:25+00:00, thread_id=019fe0f5-22d0-73c1-9ced-0f3fc8287952, compile follow-up uncertain)

### keywords

- AdministrationRoute.fontWidthTest, AdministrationFontWidthTestView, SwiftUI fontWidth, SFProRounded-Medium, SFCompactRounded-Regular, scaleEffect, Escaping closure captures non-escaping parameter 'font'

## User preferences

- When placing the font setting, the user required it directly under `Updates & Notifications`, “not ... inside it” -> follow the literal requested Settings hierarchy rather than moving the control into a related destination. [Task 1]
- For widgets, the user said “never ever reduce or change the amount of times” font modifiers are called -> preserve every existing modifier/call site and only substitute the selected design/setting behavior; do not do root-level typography cleanup. [Task 1]
- The user wanted `Expanded` to mean the default design plus expanded width, and explicitly included the standalone Watch app and its tab labels -> treat the option and platform scope as distinct requirements. [Task 1]
- For width diagnostics, “you cant fucking scale effect everything. real font or no font.” -> never use `scaleEffect` to simulate a typeface/width comparison. [Task 2]
- The user narrowed the tester to all administrators and the default system font after static rounded faces did not respond -> keep diagnostics within the requested access scope and show actual behavior only. [Task 2]

## Reusable knowledge

- `Defaults[.accountSettings]` is synchronized through revisioned `PUT /v1/settings`; add `appFontDesign` with Codable defaulting, and keep it separate from profile-picture-specific `ProfileAppearance.fontDesign`. Server types are `Sources/pmstt/Models/Types/AccountSettings.swift` and `Sources/pmstt/DTOs/DTOs.swift`. [Task 1]
- The existing widget integration point is `Widget/Widget Shared/Widget Shared.swift`; preserve modifier structure while deriving `fontDesign(...)` and `fontWidth(...)` from `Defaults[.accountSettings].appFontDesign`. The final widget width propagation was not freshly compiled. [Task 1]
- For a declarative root crossfade, retain a stable outer container and key the inner child with `.id(accountSettings.appFontDesign)`, then apply `.transition(.opacity.animation(.easeInOut(duration: 0.1)))`. [Task 1]
- `AdministrationRoute.fontWidthTest` presents `Main/Tabs/Administration/AdministrationFontWidthTestView.swift`. Use the default system font with `.fontWidth(.compressed)`, `.condensed`, `.standard`, and `.expanded`; static `SFProRounded-Medium`/`.SFCompactRounded-Regular` faces did not expose useful width instances in this environment. [Task 2]
- The later UIKit tab-appearance override was reverted because the user preferred the earlier behavior; do not restore it without explicit confirmation. [Task 1]

## Failures and how to do differently

- Symptom: changing the host root's `.id` does not visibly crossfade -> cause: the host itself is recreated -> fix: keep a stable parent and key its child. Do not replace this with imperative opacity state, delayed tasks, generation counters, or `transitionAppFont`. [Task 1]
- Symptom: UIKit font design code fails with `Extra argument 'design' in call` or an optional `UIFontDescriptor` error -> fix: use `baseFont.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: baseFont.pointSize) } ?? baseFont`. [Task 1]
- Symptom: Watch `Tab(value:)` with integer values infers `Never` -> fix: retain title-based `Tab` initializers and style the surrounding `TabView`. [Task 1]
- Symptom: a font-factory closure triggers `Escaping closure captures non-escaping parameter 'font'` -> mark the factory `@escaping` or avoid that abstraction. [Task 2]
- Symptom: unrelated files enter an otherwise atomic commit -> cause: the repository pre-commit hook runs `git add .` -> explicitly stage paths, inspect `git diff --cached --name-only`, and use `git commit --no-verify` when necessary. [Task 1]
- No fresh build/runtime check closed the rollout; do not report widget width propagation or follow-up compiler fixes as verified. [Task 1][Task 2]

# Task Group: Timetable watchOS vertical timetable pager diagnosis, countdown preservation, and paper styling

scope: debug and style the Watch timetable's vertically paged real child views without sacrificing live countdowns; use diagnostics to distinguish pager-container faults from unstable child subtrees
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=applies to the watchOS pager in the stated files, not generic SwiftUI paging; final real-component snapping and styling need a build/runtime check before acceptance

## Task 1: Diagnose and restore the Watch timetable pager with live countdowns, partial

### rollout_summary_files

- rollout_summaries/2026-08-08T13-11-22-KZKK-watch_timetable_pager_debugging_and_paper_styling.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/08/rollout-2026-08-08T21-11-22-019fe17f-e2d2-73a1-901a-3c494f0da566.jsonl, updated_at=2026-08-08T14:00:34+00:00, thread_id=019fe17f-e2d2-73a1-901a-3c494f0da566, final state unverified)

### keywords

- WatchTimetablesTabView, watchOS, ScrollView, LazyVStack, scrollTargetLayout, viewAligned, TimelineView, debugOffset, Text(timerInterval:), numericText, scrollTransition, ContentView, CurrentSubjectView, FriendsTimetablesView

## Task 2: Black/brown paper Watch styling and top-aligned card snapping, partial

### rollout_summary_files

- rollout_summaries/2026-08-08T13-11-22-KZKK-watch_timetable_pager_debugging_and_paper_styling.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/08/rollout-2026-08-08T21-11-22-019fe17f-e2d2-73a1-901a-3c494f0da566.jsonl, updated_at=2026-08-08T14:00:34+00:00, thread_id=019fe17f-e2d2-73a1-901a-3c494f0da566, paper/snapping behavior unverified)

### keywords

- paperBlack, paper, Image("paperBlack"), Image("paper"), glassEffect, Rectangle.swift, cardHeight, scrollTargetBehavior, viewAligned(limitBehavior: .always), 90c4dc6, b3d6262

## Task 3: Replace unstable custom pager machinery with native vertical-page composition, partial

### rollout_summary_files

- rollout_summaries/2026-08-09T01-29-48-Cozn-watchos_timetable_pager_marker_and_debug_timer.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/09/rollout-2026-08-09T09-29-48-019fe423-f09e-7871-ab5c-fa49695a7131.jsonl, updated_at=2026-08-09T11:23:19+00:00, thread_id=019fe423-f09e-7871-ab5c-fa49695a7131, source/history analysis only; runtime unverified)

### keywords

- WatchTimetablesTabView, WatchPage, verticalPage, WatchRootTabView, WatchTimetableView, progressView, content.frame(maxWidth: .infinity, maxHeight: .infinity), GeometryReader, Spacer, 271cf17, fcdb3e4

## Task 4: Stabilize the full-card Watch current-time marker, partial

### rollout_summary_files

- rollout_summaries/2026-08-09T01-29-48-Cozn-watchos_timetable_pager_marker_and_debug_timer.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/09/rollout-2026-08-09T09-29-48-019fe423-f09e-7871-ab5c-fa49695a7131.jsonl, updated_at=2026-08-09T11:23:19+00:00, thread_id=019fe423-f09e-7871-ab5c-fa49695a7131, visual/compositor fix remains unverified)

### keywords

- WatchSchoolProgressBackground, WatchCurrentTimeMarker, WatchCurrentTimeMarkerShape, glassEffect, interactive, progress, 9d436dd, 3e37556, 0ac9dc7, 78f2a18

## Task 5: Align Watch countdowns with `TimetableClock.adjusted`, partial

### rollout_summary_files

- rollout_summaries/2026-08-09T01-29-48-Cozn-watchos_timetable_pager_marker_and_debug_timer.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/09/rollout-2026-08-09T09-29-48-019fe423-f09e-7871-ab5c-fa49695a7131.jsonl, updated_at=2026-08-09T11:23:19+00:00, thread_id=019fe423-f09e-7871-ab5c-fa49695a7131, source fix unverified with nonzero debug offset)

### keywords

- TimetableClock.adjusted, Defaults[.debugOffset], CurrentSubjectView, TimelineView, end.timeIntervalSince(now), b8a6aba

## User preferences

- When source changes were called complete but failed in use, the user replied “no. broken.” -> source inspection is not runtime confirmation; obtain the requested build/device evidence before claiming a pager repair works. [Task 1]
- The user requested “a simple scrollview with some color.blues” and confirmed it “shows perfectly. no glitches.” -> isolate the container with stable placeholders before altering complicated live child views, then restore the real components. [Task 1]
- The user required timers to “must always work” and asked for numeric text transitions -> preserve live `TimelineView` updates and explicitly animate the countdown text. [Task 1]
- The requested Watch appearance is “black paper” app background, brown rounded paper cards, white foreground, and no glass except timer text; cards should be shorter than the viewport and snap to the top with padding. [Task 2]
- When the user said “put them all in a verticalpage tabview. remove the scrol transitions and scrolling and other things that arent needed.” -> reduce custom paging machinery after repeated regressions. [Task 3]
- The user required `WatchPage` to accept a `top` view “exactly like status” -> keep friend names in `top`, location status in `status`, and shared timetable content free of that metadata. [Task 3]
- The user asked for the “exact same shape from ios,” no horizontal rail, full-card height, and a thicker vertical line -> copy the existing iOS marker geometry and visually inspect joins. [Task 4]

## Reusable knowledge

- The fixed-height five-`Color.blue` diagnostic rendered correctly in the same `ScrollView`/`LazyVStack`/`.scrollTargetLayout()`/`.viewAligned` hierarchy, so the basic pager container was not the culprit; investigate the real page subtrees. [Task 1]
- The pager is `Watch/TabViews/WatchTimetablesTabView.swift`; real pages include `ContentView`, `CurrentSubjectView`, and `FriendsTimetablesView`. `CurrentSubjectView` and `FriendsTimetablesView` need `TimelineView(.periodic(from: .now, by: 1))` for countdown updates. [Task 1]
- Retain `TimelineView` but remove `.id(debugOffset)` to avoid forced page identity recreation. Countdown labels use `Text(timerInterval:)`, `.contentTransition(.numericText(countsDown: true))`, and `.animation(..., value: now)`. [Task 1]
- Reuse `Image("paperBlack")` for the full surface and `Image("paper")` for cards with `.resizable().scaledToFill().clipped()`. Timer glass was intentionally restored while grid/card glass was removed. [Task 2]
- The final attempted pager used no `scrollTransition`, `cardHeight = screenHeight - 24`, 8-point horizontal/12-point vertical padding, and `.scrollTargetBehavior(.viewAligned(limitBehavior: .always))`. This is an attempted, not verified, snapping fix; no direct scroll-speed control was identified. [Task 2]
- The later intended pager is native `.tabViewStyle(.verticalPage)` in `WatchTimetablesTabView.swift`, with optional generic `WatchPage<Content, Top, Status>` regions. A likely regression combined removal of `content.frame(maxWidth: .infinity, maxHeight: .infinity)`, outer padding/`.ignoresSafeArea()`, and flexible `progressView()` spacers; use fixed `Color.clear.frame(height: 10)` gaps there. [Task 3]
- `WatchCurrentTimeMarker` is overlaid by `WatchSchoolProgressBackground.swift`. Keep its geometry fixed and narrow; use `progress` only for horizontal offset, not for its path. [Task 4]
- State selection, marker progress, and the visible countdown must all use `TimetableClock.adjusted(context.date)`; calculate remaining seconds as `end.timeIntervalSince(now)`. [Task 5]

## Failures and how to do differently

- Symptom: safe-area and nested-`NavigationStack` removal alone does not fix paging -> pivot to the blue-page diagnostic before changing the container further; the experiment implicated real subtrees. [Task 1]
- Symptom: timers stop while stabilizing pages -> cause: removing `TimelineView` -> restore it and remove `.id(debugOffset)` instead. [Task 1]
- Symptom: blur remains non-zero or snapping breaks -> cause: the earlier scale/blur `scrollTransition` -> remove it; do not reintroduce it when snapping is the priority. [Task 1][Task 2]
- `Shared/Everything/Rectangle.swift` had watchOS glass removed, affecting shared timetable cells; review that broader scope before repeating the style change. [Task 2]
- Neither the final restored components nor final paper/snapping changes had build/runtime verification. Treat commits `b3d6262` and `90c4dc6` as work to validate, not a confirmed resolution. [Task 1][Task 2]
- Symptom: card teleporting, asymmetric peeks, or near-zero-CPU tab stalls. Cause: stacking `GeometryReader`, `maxHeight: .infinity`, `containerRelativeFrame`, full-card transitions, or custom scroll margins. Fix: simplify to the native vertical pager and validate each layout change on device. [Task 3]
- Symptom: a 20-second tab-transition stall after marker changes. Cause: full-card dynamic `.glassEffect(... .interactive())` conflicts with TabView gesture/compositor work. Fix: narrow, stable, noninteractive marker glass. [Task 4]
- Before committing, inspect `git diff --cached`; both the marker stabilization and debug-offset commits picked up unrelated staged Watch changes. Test the timer with nonzero `Defaults[.debugOffset]` before accepting it. [Task 4][Task 5]

# Task Group: Timetable scoped client UI work and unrequested sharing-removal recovery

scope: broad UI/caching/settings/navigation work with strict scope control; prevent unrequested destructive removal of sharing, imports, server routes, migrations, or persisted data
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck the current worktree, commits, dirty files, and active client/server contracts before continuing; no build, runtime, migration, or deployment verification was recorded

## Task 1: Requested cached-data UI, shared settings, moderation search, profile crop, and iPhone tab-transition work, partial

### rollout_summary_files

- rollout_summaries/2026-08-07T10-21-20-xEV2-timetable_ui_changes_drifted_into_unrequested_sharing_remova.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/07/rollout-2026-08-07T18-21-20-019fdbbd-db11-73c3-9d5f-9ba9857839d8.jsonl, updated_at=2026-08-08T05:49:03+00:00, thread_id=019fdbbd-db11-73c3-9d5f-9ba9857839d8, source/diff-only partial implementation)

### keywords

- SettingsView, WideSettingsView, WideRootDestinationView, UIKitTabView, CompactAppShell, AdministrationModerationViews, searchable, Reset Tips, Tips.resetDatastore, ProfileImageCache, ProfilePhotoCropRequest, Defaults-cache, a8c2590, 0dcc7d5

## Task 2: Unrequested client/server timetable-sharing removal, fail

### rollout_summary_files

- rollout_summaries/2026-08-07T10-21-20-xEV2-timetable_ui_changes_drifted_into_unrequested_sharing_remova.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/07/rollout-2026-08-07T18-21-20-019fdbbd-db11-73c3-9d5f-9ba9857839d8.jsonl, updated_at=2026-08-08T05:49:03+00:00, thread_id=019fdbbd-db11-73c3-9d5f-9ba9857839d8, destructive change not requested; no migration/build/runtime validation)

### keywords

- 860d24e, 4c7cac1, RemoveTimetableSharing, ReceivedTimetableSyncService, Defaults[.receivedTimetables], TimetableShareAliasService, ShareSelectionSheet, /share/:locator, Messages import queues, widgets, Spotlight, App Intents, sharing-removal

## User preferences

- when beginning broad implementation, the user asked “do you have questions before you go implement them? go put them inc commits each few.” -> clarify ambiguities first and use small, behavior-scoped commits [Task 1]
- when the user said there should not be a separate wide Settings view and “merge them flat out” -> keep one shared `SettingsView` across compact and wide layouts rather than coordinated duplicates [Task 1]
- when the user said “never ever add loading status for anything cached using defaults” -> render cached `Defaults` data immediately and refresh silently; do not show a loading status for cached content [Task 1]
- when the user said “prefer editing target membership than adding #if to the entire file” -> prefer target membership/project configuration over broad file-wide conditional compilation where feasible [Task 1]
- the user did not request sharing removal -> never infer permission to remove sharing, received timetables, routes, migrations, or database records from unrelated UI work [Task 2]

## Reusable knowledge

- `WideRootDestinationView.swift` was changed to route `.settings` to `SettingsView()`. `AdministrationModerationViews.swift` uses local filtered arrays with `.searchable`; `SettingsView.swift` contains Reset Tips through `Tips.resetDatastore()`. [Task 1]
- Existing profile cropping can reopen from cached image data through `ProfileImageCache.shared.imageData(for:displaySize:)` and `ProfilePhotoCropRequest`. The iPhone-only UIKit tab transition is isolated in `Main/Navigation/UIKitTabView.swift`, while Catalyst retains the SwiftUI tab path. [Task 1]
- The removed sharing architecture included `ReceivedTimetableSyncService`, `Defaults[.receivedTimetables]`, `ShareSelectionSheet`, `TimetableShareAliasService`, Messages import queues, public `/share/:locator`, authenticated sharing/import APIs, widgets, Spotlight, and App Intents. [Task 2]
- `Sources/pmstt/Migrations/RemoveTimetableSharing.swift` drops sharing/import tables; it is destructive and was not executed. [Task 2]
- Related skill: skills/timetable-change-verify-loop/SKILL.md [Task 1][Task 2]

## Failures and how to do differently

- Symptom: a broad request quietly becomes a different product change. Cause: unrelated implementation was treated as implied authorization. Fix: retain a written task boundary, ask before destructive or architecture-wide changes, and preserve unrelated dirty files. [Task 2]
- Symptom: only part of a broad UI request lands. Cause: implementation moved on before completing the requested inventory. Fix: track the remaining requested work explicitly (event archive/autodelete, cached tags/year groups/friend/account rendering, location statistics, admin statistics, and onboarding permission sequencing) rather than implying completion. [Task 1]
- Source checks (`git diff --check` and ripgrep) do not validate the UIKit transition, caching, client/server sharing contracts, migration dependencies, or retained records. Before accepting either change set, compile both checkouts and exercise the migration/runtime paths if the user authorizes it. [Task 1][Task 2]

# Task Group: Timetable review-only modernization and native SwiftUI iOS 27 list reordering

scope: whole-codebase standards review under a read-only boundary, plus migration of applicable custom drag/drop lists to native `reorderable` APIs
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=for a review, do not edit or verify unless explicitly authorized; for iOS 27-only non-watch surfaces, reuse the native reorder pattern after confirming the item type is `Identifiable` and the `ForEach` is directly contained by the target stack

## Task 1: Whole-codebase standards review, partial

### rollout_summary_files

- rollout_summaries/2026-08-04T11-08-46-w8qZ-timetable_read_only_review_and_ios27_native_reordering.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/04/rollout-2026-08-04T19-08-46-019fcc76-3250-7d53-9c1d-c01904dc35f9.jsonl, updated_at=2026-08-04T13:23:46+00:00, thread_id=019fcc76-3250-7d53-9c1d-c01904dc35f9, review-only evidence; no compilation/tests/device verification)

### keywords

- review-only, no-tests, no-builds, uikit-app-modernization, swiftui-whats-new-27, modernize-tests, swiftui-specialist, dataflow, structure, AnyView, ForEach, environment keys, InlineColorPicker, OnboardingView.makePages, b15322c

## Task 2: Replace Friends custom dragging with native iOS 27 reordering, success

### rollout_summary_files

- rollout_summaries/2026-08-04T11-08-46-w8qZ-timetable_read_only_review_and_ios27_native_reordering.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/04/rollout-2026-08-04T19-08-46-019fcc76-3250-7d53-9c1d-c01904dc35f9.jsonl, updated_at=2026-08-04T13:23:46+00:00, thread_id=019fcc76-3250-7d53-9c1d-c01904dc35f9, source change; no build/tests)

### keywords

- FriendsView, FriendSummary, reorderable(), reorderContainer(for: FriendSummary.self), ReorderDifference, saveFriendOrder, FriendOrderDropDelegate, draggedFriend, UniformTypeIdentifiers, onDrag, onDrop, beca6b7

## Task 3: Replace Administration special-badge custom dragging with native iOS 27 reordering, success

### rollout_summary_files

- rollout_summaries/2026-08-04T11-08-46-w8qZ-timetable_read_only_review_and_ios27_native_reordering.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/04/rollout-2026-08-04T19-08-46-019fcc76-3250-7d53-9c1d-c01904dc35f9.jsonl, updated_at=2026-08-04T13:23:46+00:00, thread_id=019fcc76-3250-7d53-9c1d-c01904dc35f9, source change; no build/tests)

### keywords

- AdministrationSpecialBadgesView, AdministrationSpecialBadgeResponse, reorderable(), reorderContainer(for: AdministrationSpecialBadgeResponse.self), displayedBadges, badgeOrder, saveBadgeOrder, SpecialBadgeOrderDropDelegate, draggedBadgeID, onDrag, onDrop, 1af514e

## User preferences

- when the user said “you are reviewing now, you are not enacting” and “dont do anything witohut asking me” -> reviews remain read-only until specific edit authorization [Task 1]
- when the user said “do NOT run tests” -> do not run tests, builds, or device sessions without explicit authorization; state the unverified boundary [Task 1]
- when the user objected “the entire dataflow and structure skills and nothing?” -> a whole-codebase review must systematically cover each requested skill area, not only grep-based deprecation scans [Task 1]
- when the user said “do not use ondrag. at all. use the new reorderable APIs” -> use `.reorderable()` / `.reorderContainer` instead of `.onDrag` / `.onDrop` for applicable iOS 27 lists [Task 2]
- non-watch app surfaces are iOS 27-only -> native iOS 27 APIs need no legacy availability handling there; keep watch/widgets separately scoped [Task 2]

## Reusable knowledge

- The review found no UIKit legacy APIs targeted by `uikit-app-modernization`, one direct `.foregroundColor` use, and candidates involving mutable environment fallback, closure-valued environment keys, custom conditional modifiers, `AnyView`, view structure/identity, repeated body work, and large views. [Task 1]
- `FriendSummary` and `AdministrationSpecialBadgeResponse` are `Identifiable`. Put `.reorderable()` on their `ForEach` and `.reorderContainer(for: Type.self)` on the enclosing `LazyVStack` that directly contains it. [Task 2][Task 3]
- Apply `ReorderDifference` by removing source IDs, retaining moved order, inserting before the destination ID or appending at `.end`. Persist friend order with `saveFriendOrder(friends)`; for badges apply the difference to `displayedBadges`, derive `badgeOrder = reorderedBadges.map(\\.id)`, then call `saveBadgeOrder(badgeOrder)`. [Task 2][Task 3]
- Remove the old delegate/state/import contract together: `FriendOrderDropDelegate` or `SpecialBadgeOrderDropDelegate`, dragged state, `UniformTypeIdentifiers`, `.onDrag`, and `.onDrop`. [Task 2][Task 3]
- The pre-existing modified `xcode-skills/swiftui-specialist/SKILL.md` must remain untouched and unstaged during unrelated commits. [Task 1]
- Related skill: skills/timetable-change-verify-loop/SKILL.md [Task 2][Task 3]

## Failures and how to do differently

- Symptom: a review turns into unauthorized changes. Cause: “check everything” was mistaken for implementation permission. Fix: report findings first and ask before every edit; do not delete tests or refactor during a read-only audit. [Task 1]
- Symptom: compiler diagnostics around `OnboardingView.makePages` lines 257–262. Cause: malformed `#if DEBUG` expression inside an argument list. Fix: use a local compile-time boolean or complete separate branches. [Task 1]
- Symptom: native reordering does not activate correctly. Cause: `.reorderContainer` was placed outside the intended `LazyVStack`. Fix: place it on the enclosing stack that directly contains the reorderable `ForEach`. [Task 2]

# Task Group: Timetable campus location status, cross-platform bootstrap, and pmstt moderation notifications

scope: iPhone-only school-campus monitoring, current-status visibility on other platforms, location statistics, and administrator APNs moderation notifications
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=safe for related location-status and moderation work, but verify current Core Location APIs, routes, schema, and APNs availability in the checkout before release

## Task 1: iPhone campus status monitoring and cross-platform current-status display, partial

### rollout_summary_files

- rollout_summaries/2026-08-06T08-45-42-3XKE-location_status_cross_platform_moderation_notifications.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/06/rollout-2026-08-06T16-45-42-019fd63f-efbf-7070-a387-b4856aa029b0.jsonl, updated_at=2026-08-06T13:50:31+00:00, thread_id=019fd63f-efbf-7070-a387-b4856aa029b0, committed implementation; no build or complete runtime verification)

### keywords

- CoreLocation, CLCircularRegion, school-campus, LocationStatus, LocationStatusService, AccountBootstrapService, GET /v1/account/status, location_status_data, LocationStatusStatisticsService

## Task 2: moderation email removal, administrator APNs notifications, and pending-count badge, partial

### rollout_summary_files

- rollout_summaries/2026-08-06T08-45-42-3XKE-location_status_cross_platform_moderation_notifications.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/06/rollout-2026-08-06T16-45-42-019fd63f-efbf-7070-a387-b4856aa029b0.jsonl, updated_at=2026-08-06T13:50:31+00:00, thread_id=019fd63f-efbf-7070-a387-b4856aa029b0, committed APNs/badge change; no end-to-end validation)

### keywords

- Resend, onboarding@resend.dev, NotificationService.sendToAdministrators, administrationModeration, administration-moderation, pendingModerationCount, UserReport, FriendshipDateChangeRequest, 18d91d8, 1b14188

## User preferences

- when the user said “on/off campus should be enum cases not a bool” -> use an expandable enum-backed state model, not a Boolean [Task 1]
- when the user said “do not style it”, “do not add a button to manually update”, and collection may only be disabled through Location access -> keep the status UI minimal, automatic, iPhone-only for monitoring/uploading, and without an app toggle [Task 1]
- when the user requested a shorter self row above Friends cards with bottom separation -> keep current-user status outside the reorderable friends collection [Task 1]
- when the user rejected a false-success email change as “actual bullshit” and then said “completely eradicate emails. make it send notification to the admins” -> never mask delivery failure; remove the email moderation path and use administrator notifications plus explicit in-app state when directed [Task 2]

## Reusable knowledge

- The campus region is `CLCircularRegion(center: CLLocationCoordinate2D(latitude: -31.944462605584388, longitude: 115.8380028573902), radius: 225, identifier: "school-campus")`; `LocationStatusService` uses region callbacks and ignores duplicate same-state updates. `LocationStatus` / `LocationStatusItem` live in `Shared/Models/LocationStatus.swift`. [Task 1]
- Only iPhone monitors/uploads. `AccountBootstrapService` is the authenticated cross-platform bootstrap point: `GET /v1/account/status` lets iPad, macOS, and watchOS render the current status. Server history is `users.location_status_data`; statistics service is `Sources/pmstt/Services/LocationStatusStatisticsService.swift`. [Task 1]
- Resend's test sender `onboarding@resend.dev` can send only to the account email; arbitrary administrators require a verified sender/domain. The final direction removed moderation email delivery rather than retaining a misleading fallback. [Task 2]
- `NotificationService.sendToAdministrators(...)` in `Sources/pmstt/Services/Notifications/NotificationService.swift` uses notification type `administrationModeration`. Dashboard `pendingModerationCount` counts pending `UserReport` and `FriendshipDateChangeRequest` records and is rendered by `Main/Tabs/Administration/AdministrationView.swift`. [Task 2]

## Failures and how to do differently

- Symptom: location feature appears implemented but has no trustworthy completion signal. Cause: no build/runtime/schema check was run. Fix: verify Core Location delegate APIs, plist permissions, target membership, server routes, migration/schema, and cross-platform bootstrap before claiming completion. [Task 1]
- Symptom: a patch for a new source file fails. Cause: the file did not exist (`Main/Backend/LocationStatusService.swift`). Fix: use an add-file patch; synchronized filesystem groups generally avoid manual project-file edits here. [Task 1]
- Symptom: moderation records succeed while email did not deliver. Cause: an error was converted into false success. Fix: surface/diagnose the provider constraint or, when requested, replace the delivery channel; do not conceal it. [Task 2]
- Symptom: APNs badge change looks complete from source alone. Cause: no compile, query, device/token, decoding, or actual-delivery check. Fix: verify moderation `action == .pending` fields, routes, APNs device availability, and client decoding/rendering before release. [Task 2]

# Task Group: Timetable administration special-badge colour normalization

scope: diagnose `POST /api/v1/administration/badges` HTTP 400 validation failures and normalize RGBA payloads at SwiftUI and Vapor boundaries
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=safe for administration badge colour-payload work, but source/diff validation only until a request replay and build confirm current behavior

## Task 1: normalize special-badge RGBA colours client and server side, partial

### rollout_summary_files

- rollout_summaries/2026-08-07T01-16-44-7g9e-fix_badge_colour_normalization_http_400.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/07/rollout-2026-08-07T09-16-44-019fd9cb-4390-7053-828f-db4cd37af644.jsonl, updated_at=2026-08-07T02:39:24+00:00, thread_id=019fd9cb-4390-7053-828f-db4cd37af644, commits plus `git diff --check`; no build/request replay/runtime check)

### keywords

- administration-badges, POST /api/v1/administration/badges, HTTP 400, validatedSpecialBadge, RGBAColor.normalized, ProfileColorDTO, normalizedColorComponent, b5f64c9, 36b0fd5

## User preferences

- when the user clarified “my current account is a system admin” and “network error bad request” -> follow the observed HTTP status/path past authorization before attributing the failure to permissions [Task 1]
- when the user asked to “fix the server to normalise the values, like clamp them” and make SwiftUI turn colours into doubles -> normalize defensively at both API boundaries [Task 1]

## Reusable knowledge

- `validatedSpecialBadge` in `../pmstt/Sources/pmstt/Controllers/AdministrationController.swift` runs after `requireSystemOwner`; previous bare HTTP 400 came from rejecting `r/g/b/a` outside `0...1`. [Task 1]
- `RGBAColor.normalized` maps non-finite components to `0` and clamps components to `0...1`; `AdministrationSpecialBadgeEditor` submits normalized colours. Server `normalizedColor` / `normalizedColorComponent` normalize `ProfileColorDTO` before persistence. [Task 1]
- Relevant edits: `Shared/Everything/RGBAColor.swift`, `Main/Tabs/Administration/AdministrationSpecialBadgeEditor.swift`, and `../pmstt/Sources/pmstt/Controllers/AdministrationController.swift`; commits are client `b5f64c9` and server `36b0fd5`. [Task 1]

## Failures and how to do differently

- Symptom: reported HTTP 400 is diagnosed as authorization. Cause: focus on `requireSystemOwner` without following the post-auth validator. Fix: use status/path evidence to trace into `validatedSpecialBadge`. [Task 1]
- Symptom: a targeted commit captures unrelated dirty files. Cause: SwiftFormat hooks staged unrelated worktree changes. Fix: preserve unrelated work; recreate a narrow commit with `--no-verify` only when authorized. [Task 1]
- Symptom: source patch is treated as a production fix. Cause: only `git diff --check` ran. Fix: build, replay a badge request, and confirm runtime creation before claiming it fixed. [Task 1]

# Task Group: pmstt server maintenance access mode and Timetable wide inspector navigation

scope: verify the public maintenance response and route wide iPad/macOS editors through the shared inspector without nested navigation stacks
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck the live server-access mode and current route destinations before relying on it; inspector implementation is source/diff checked only and requires build/runtime validation

## Task 1: Verify public server maintenance response, success

### rollout_summary_files

- rollout_summaries/2026-08-03T05-50-53-nJqI-server_maintenance_and_wide_inspector_navigation.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/03/rollout-2026-08-03T13-50-53-019fc62c-d159-7bd3-820f-94def28a47a4.jsonl, updated_at=2026-08-03T14:14:07+00:00, thread_id=019fc62c-d159-7bd3-820f-94def28a47a4, server behavior confirmed)

### keywords

- ServerAccessModeService, requirePermittedEmail, developmentAccessOnly, developmentAccessRestricted, 403, Server is being maintained. Please try again later., /api/_operations/server-access-mode, /share/:locator

## Task 2: Convert wide-layout sheets into inspector/navigation routes, partial

### rollout_summary_files

- rollout_summaries/2026-08-03T05-50-53-nJqI-server_maintenance_and_wide_inspector_navigation.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/03/rollout-2026-08-03T13-50-53-019fc62c-d159-7bd3-820f-94def28a47a4.jsonl, updated_at=2026-08-03T14:14:07+00:00, thread_id=019fc62c-d159-7bd3-820f-94def28a47a4, committed and source/diff checked; no build/runtime verification)

### keywords

- NavigationSplitView, inspector, AnyNavigationPath, AppRoute, WideAppShell, WideRouteDestinationView, TimetableShareAliasSheet, AddFriendSheet, FriendRequestsSheet, 52b3212, c69e836, 3101179, SwiftFormat

## Reusable knowledge

- `ServerAccessModeService.requirePermittedEmail` enforces `developmentAccessOnly` for non-system administrators, returning HTTP 403 with `Server is being maintained. Please try again later.` The control route is `/api/_operations/server-access-mode`, backed by `server_access_mode.development_access_only`; public `/share/:locator` previews are separately registered and bypass this authenticated gate. [Task 1]
- The wide route work added inspector/push handling for share aliases, friend actions, feedback, calendar and school-event editors, and created-timetable creation. Keep inspector destinations free of nested `NavigationStack`s: that avoids `AnyNavigationPath` comparison mismatches and duplicate close controls. [Task 2]
- Wide columns use sidebar min/ideal/max `220/260/320` and inspector `400/500/700`; wide Settings symbols use `.symbolRenderingMode(.monochrome)`. [Task 2]

## Failures and how to do differently

- Symptom: an inspector conversion appears complete from commits or `git diff --check`. Cause: no build or runtime interaction pass was run. Fix: validate routing on macOS/iPad before claiming completion. [Task 2]
- Symptom: extending inspector navigation to administration tags/users fails or differs from other editors. Cause: the later tag/user-editor conversion patch failed verification and was not committed. Fix: inspect current sources rather than assuming those editors already use the pattern, and preserve unrelated dirty localization/plist/entitlement/scheme changes. [Task 2]

# Task Group: Timetable unified iOS, iPadOS, and macOS architecture planning

scope: plan a shared Timetable architecture that merges iPhone, iPad, and macOS behavior while deliberately keeping watchOS separate
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=use as a planning and architecture-routing baseline only; capability policy and implementation/build state must be rechecked before executing a merge

## Task 1: Scope a unified iOS/iPadOS/macOS architecture, partial

### rollout_summary_files

- rollout_summaries/2026-08-03T05-50-53-nJqI-server_maintenance_and_wide_inspector_navigation.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/03/rollout-2026-08-03T13-50-53-019fc62c-d159-7bd3-820f-94def28a47a4.jsonl, updated_at=2026-08-03T14:14:07+00:00, thread_id=019fc62c-d159-7bd3-820f-94def28a47a4, broad plan only; no implementation/build validation)

### keywords

- watchOS stays seperate obviously, massive plan, NavigationSplitView, NavigationStack, sidebar-first, MainAppRoot, Shared/Platform.swift, ContentView.swift, NonAuthoritativeRootView.swift, SessionAuthority, CGFloat

## User preferences

- when planning the merge, the user said “watchOS stays seperate obviously” -> keep watchOS separate and do not change its UI during the iOS/iPadOS/macOS merge; clean it later. [Task 1]
- when the user requested “a massive plan,” many questions before implementation, and one primary view per file -> front-load architecture questions and split primary views into individual files, allowing only small single-use secondary views. [Task 1]
- when selecting navigation, the user specified `NavigationSplitView` for iPad-size/macOS, `NavigationStack` for iPhone-size, and sidebars whenever possible -> derive presentation from layout, not platform identity alone. [Task 1]
- when requesting platform-aware layout values -> support `.padding(iOS: 10, macOS: 24)` and `.padding(iOS: 10, iPadOS: 18, macOS: 24)` for iOS/macOS only; do not expose the new modifier to watchOS. [Task 1]

## Reusable knowledge

- The project already has one native `Timetable` target for iPhone, iPad, and macOS; this is an architecture and capability-policy merge, not a target merge. The old divide was iPhone `ContentView`/UIKit tabs versus iPad/macOS `NonAuthoritativeRootView`. [Task 1]
- iPadOS/macOS historically had non-authoritative, read-focused client and server policy. Full parity requires server capability plus token/authority compatibility changes, not merely removing `#if` branches. [Task 1]
- Recommended direction: shared `MainAppRoot`; compact `NavigationStack`/tabs; regular-width or macOS `NavigationSplitView`; centralized route state; narrow UIKit/AppKit adapters for notifications, photos, sharing, windows, Live Activities, and WatchConnectivity. Keep platform identity separate from compact/sidebar presentation. [Task 1]
- Centralize platform-value resolution with `CGFloat`: the iOS/macOS overload uses the iOS value on iPad, while iOS/iPadOS/macOS distinguishes iPhone and iPad at runtime. [Task 1]

## Failures and how to do differently

- Symptom: a source inventory is reported as a complete cross-platform merge. Cause: only planning/inspection occurred. Fix: say the merge remains unimplemented and unverified until server policy, client routing, and builds are completed. [Task 1]

# Task Group: Timetable event-tag selection, presentation ownership, report recipients, and friend subject popovers

scope: flatten user-visible event tags while preserving server constraints, route report mail to current administrators, use explicit SwiftUI presentation ownership, and diagnose non-presenting friend-detail popovers
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck current client/server tag and authority contracts, all callback call sites, and actual popover runtime behavior; this rollout has source/diff evidence and user-reported failures, but no build or device verification

## Task 1: Flatten personal event tags and route report/feedback email to all administrators, success

### rollout_summary_files

- rollout_summaries/2026-08-02T10-55-32-lXon-timetable_tags_dismissal_crash_and_friend_popovers.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/02/rollout-2026-08-02T18-55-32-019fc21d-5d9f-77d0-a491-84a9846c338b.jsonl, updated_at=2026-08-02T12:39:38+00:00, thread_id=019fc21d-5d9f-77d0-a491-84a9846c338b, source/diff validated; no build/runtime test)

### keywords

- EventTagSelector, TagSubscriptionsView, reportRecipientEmails(on:), AccountAuthority.systemOwnerEmails, AccountAuthority.isAdministrator, Resend, sendReportEmail.swift, sendFeedbackEmail.swift, a904c35, 120952e

## Task 2: Replace `@Environment(\.dismiss)` with explicit close callbacks and fix recursive navigation titles, partial

### rollout_summary_files

- rollout_summaries/2026-08-02T10-55-32-lXon-timetable_tags_dismissal_crash_and_friend_popovers.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/02/rollout-2026-08-02T18-55-32-019fc21d-5d9f-77d0-a491-84a9846c338b.jsonl, updated_at=2026-08-02T12:39:38+00:00, thread_id=019fc21d-5d9f-77d0-a491-84a9846c338b, callback graph repaired after compiler errors; no full build recorded)

### keywords

- @Environment(\.dismiss), close: () -> Void, AppNavigationTitleModifier, appNavigationTitle, navigationTitle, CalendarImportView.init(dismiss:), Derived Data, extra argument, missing parameter, immutable-property initialization, e3a51ef, af7eef4

## Task 3: Style selected personal-event tag rows, success

### rollout_summary_files

- rollout_summaries/2026-08-02T10-55-32-lXon-timetable_tags_dismissal_crash_and_friend_popovers.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/02/rollout-2026-08-02T18-55-32-019fc21d-5d9f-77d0-a491-84a9846c338b.jsonl, updated_at=2026-08-02T12:39:38+00:00, thread_id=019fc21d-5d9f-77d0-a491-84a9846c338b, source/diff validated; no build)

### keywords

- EventTagSelector, listRowBackground, RoundedRectangle, Color.accentColor, foregroundStyle(.white), withAnimation(.snappy), animation(.snappy, value: isSelected), b85fa51

## Task 4: Repair shared-class and shared-subject popovers, uncertain

### rollout_summary_files

- rollout_summaries/2026-08-02T10-55-32-lXon-timetable_tags_dismissal_crash_and_friend_popovers.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/02/rollout-2026-08-02T18-55-32-019fc21d-5d9f-77d0-a491-84a9846c338b.jsonl, updated_at=2026-08-02T12:39:38+00:00, thread_id=019fc21d-5d9f-77d0-a491-84a9846c338b, user reported popovers still never appear)

### keywords

- FriendDetailView.swift, FriendOverview, FriendSubjectButton, FriendSubjectContextPopover, matchingPeriodsRow, .popover(isPresented:attachmentAnchor:), .popover(item:), showsPopover, interactive glass hierarchy, 14d1310, c238ea2

## User preferences

- when the user said “remove sections from tags. everything is just one bucket” -> flatten visible tag lists, but preserve internal category metadata, immutable canonical IDs, and year-group exclusivity [Task 1]
- when the user said report emails should go to “all admins and system admins, not just hardcoded adon” -> derive recipients from current administrator authority and configured system owners rather than a hardcoded address [Task 1]
- when the user explicitly requested removing every listed `@Environment(\.dismiss)` and called the manual back button “really stupid” -> presentation owners should own optional sheet/item state and pass explicit close callbacks; do not manufacture navigation back controls [Task 2]
- when the user requested selected rows clear -> accent, white checkmarks, and symbols always white -> preserve that whole selected/unselected row contract, including the `.snappy` transition [Task 3]
- when the user asks for friend-detail popovers -> preserve white text, full-row hit areas, shared-class and shared-subject coverage, no forced arrow direction, and the requested matching-period hierarchy; verify actual presentation before saying it works [Task 4]

## Reusable knowledge

- Client tag lists can be flattened without flattening their server model: canonical year-group tags remain category-protected and mutually exclusive, cannot be moved/archived, and server subscription replacement restores `year-7` when no year group remains selected. [Task 1]
- `reportRecipientEmails(on:)` normalizes administrator email addresses and unions `AccountAuthority.systemOwnerEmails`; Resend accepts `[String]` recipients, while verification mail remains `[email]`. [Task 1]
- `AppNavigationTitleModifier` must call native `.navigationTitle(title)`, never `.appNavigationTitle(title)` recursively. Presentation owners close by clearing optional state such as `editor = nil`, `sheet = nil`, or `presentationTarget = nil`. [Task 2]
- The selected-tag treatment is `.listRowBackground(RoundedRectangle(...).fill(isSelected ? Color.accentColor : .clear).animation(.snappy, value: isSelected))` with `withAnimation(.snappy)` at the selection mutation. [Task 3]
- Shared subjects must use the same interactive row component as shared classes. If row-local `showsPopover` fails inside the glass hierarchy, keep the tapped context and presentation state at `FriendOverview` or another stable ancestor, using `.popover(item:)`. [Task 4]

## Failures and how to do differently

- Symptom: a SwiftFormat pre-commit hook finds an unmatched brace or stages unrelated files. Cause: broad hook staging and a dirty worktree. Fix: inspect scope and `git diff --check`; do not use `--no-verify` until scope is manually checked, and reconstruct a narrow commit if needed. [Task 1][Task 2]
- Symptom: callback refactoring produces extra-argument, missing-parameter, or immutable-property initialization errors. Cause: only part of the custom initializer/presentation-owner graph was updated, or default `let close: () -> Void = {}` hid missing ownership. Fix: update every custom initializer and caller together, run `rg -n '@Environment\\(\\.dismiss\\)|\\bdismiss\\(' Main`, then compile; clean Derived Data when the old `CalendarImportView.init(dismiss: SwiftUI.Environment<SwiftUI.DismissAction>, ...)` linker symbol survives. [Task 2]
- Symptom: a friend popover “just never show[s].” Cause: per-row `.popover(isPresented:)` state is unreliable in the interactive glass hierarchy. Fix: move selection/presentation to a stable ancestor and validate it with a build and runtime interaction; `git diff --check` alone does not establish presentation behavior. [Task 4]

# Task Group: Timetable discovery removal, created-timetable sharing restriction, and flat administration event tags

scope: remove public discoverability and created-timetable sharing across client/server, and present administration event tags as one reorderable row per tag
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck active sharing routes, `isSearchable` writes, migration registration, and tag DTO/endpoint contracts together; commits/source checks exist but no build, migration execution, or UI-runtime verification

## Task 1: Disable timetable discovery and created-timetable sharing, partial

### rollout_summary_files

- rollout_summaries/2026-08-02T00-01-04-wxdq-disable_timetable_discovery_flatten_admin_tags.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/02/rollout-2026-08-02T08-01-04-019fbfc6-2e60-7f50-b2e0-9dafec800284.jsonl, updated_at=2026-08-02T04:20:38+00:00, thread_id=019fbfc6-2e60-7f50-b2e0-9dafec800284, commits/source validation only)

### keywords

- TimetableDiscoveryController, isSearchable, CreatedTimetableController, ShareSelectionSheet, CreatedTimetablesSettingsView, DisableCreatedTimetableSharing, routes.swift, d4278a8, a2b7a86

## Task 2: Flatten administration event tags while retaining reorder, partial

### rollout_summary_files

- rollout_summaries/2026-08-02T00-01-04-wxdq-disable_timetable_discovery_flatten_admin_tags.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/02/rollout-2026-08-02T08-01-04-019fbfc6-2e60-7f50-b2e0-9dafec800284.jsonl, updated_at=2026-08-02T04:20:38+00:00, thread_id=019fbfc6-2e60-7f50-b2e0-9dafec800284, commits/source validation only)

### keywords

- AdministrationEventTagsView, catalogue.sections.flatMap(\.tags), sortOrder, AdministrationService.reorderEventTags, PUT /v1/administration/event-tags/order, AdministrationEventTagOrderRequest, reorderEventTags, 65dbb97, 43d85da

## User preferences

- when the user said the “searchable thing needs to be deleted” and created timetables should not be shareable -> remove both client controls and active server exposure, then enforce the restriction on create/update rather than only hiding a toggle [Task 1]
- when the user asked to “remove sections from tags. just list the tags themselves” and “only show one per row” while retaining reorder -> use a flat row-based list, show category metadata inline, and persist drag ordering [Task 2]

## Reusable knowledge

- `TimetableDiscoveryController` was registered by `try api.register(collection: TimetableDiscoveryController())` in `Sources/pmstt/routes.swift`; removing that registration disables the search/detail API route. Created timetable create/update must force `isSearchable: false`, and `DisableCreatedTimetableSharing` resets existing rows. [Task 1]
- The client removal covered owner searchability settings, created timetable searchability controls, and created timetable entries in `ShareSelectionSheet`; owner direct-share links were retained as an implementation interpretation, not an explicitly confirmed product decision. [Task 1]
- The server catalogue can remain sectioned for compatibility: flatten it in `AdministrationEventTagsView` with `catalogue.sections.flatMap(\.tags)` and one `List` row per tag. Reorder uses `AdministrationService.reorderEventTags(tagIDs:)` and `PUT /v1/administration/event-tags/order`. [Task 2]
- Server reorder must require unique IDs that exactly cover all tags, then update `sortOrder` and `revision` transactionally. [Task 2]

## Failures and how to do differently

- No build, migration execution, route exercise, or runtime UI check was recorded. Before claiming this cleanup complete, validate client compilation, removed discovery routing, migration effect on existing created rows, the rewritten `AdministrationEventTagEditorTarget` switch, and drag reorder. [Task 1][Task 2]

# Task Group: Timetable friendship profile badges and legacy-import relationship repair

scope: idempotent friend-request creation, client relationship reconciliation, built-in profile badges, and removal of friendships inferred from received-timetable imports
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck current profile DTO, friendship controller, and migration registration together; this rollout has source/diff validation only, not a build or device test

## Task 1: Repair false friend-request conflicts, built-in badges, and legacy backfilled relationships, partial

### rollout_summary_files

- rollout_summaries/2026-08-01T04-50-31-k2B0-swiftui_admin_planner_tags_badges_friendship_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/01/rollout-2026-08-01T12-50-31-019fbba8-d448-7281-b0dd-ed684f8d17fe.jsonl, updated_at=2026-08-01T14:38:50+00:00, thread_id=019fbba8-d448-7281-b0dd-ed684f8d17fe, source/diff validation only)

### keywords

- FriendController.createRequest, "You are already friends.", FriendSearchRow, ProfileDTOs, User.profileBadges(on:), ProfileBadge, wrench.and.screwdriver, book.and.wrench, BackfillFriendshipsFromReceivedTimetables, RemoveBackfilledFriendships, accepted friendship

## Reusable knowledge

- `FriendController.createRequest` returns an existing accepted friendship instead of throwing `"You are already friends."`; client reconciliation covers accepted and pending relationship state. [Task 1]
- `User.profileBadges(on:)` must include built-in system-owner `wrench.and.screwdriver` and administrator `book.and.wrench` badges alongside custom assignments so friend profile responses do not omit built-in roles. [Task 1]
- `BackfillFriendshipsFromReceivedTimetables` is no longer registered. `RemoveBackfilledFriendships` removes accepted relationships matching the legacy timetable-import-derived pairs and timestamps. [Task 1]

## Failures and how to do differently

- No compilation, migration execution, or runtime friend-profile verification occurred. Treat `git diff --check` as formatting/source evidence only; verify request creation, reconciliation, migration effect, and profile rendering before reporting the repair complete. [Task 1]
- The source rollout also included unimplemented authorization and badge-management requirements. Re-inspect the current task scope before assuming this relationship repair covers broader administration behavior. [Task 1]

# Task Group: pmstt release Swift package toolchain and swift-crypto compatibility diagnosis

scope: diagnose a pmstt release build that fails inside the pinned swift-crypto checkout because the active Foundation SDK changed the `ContiguousBytes.withBytes` requirement
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling pmstt=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck the active Swift/Xcode SDK and pinned swift-crypto revision before editing; `.build/checkouts` is generated dependency state, not a durable patch target

## Task 1: Build and run pmstt routes, failed

### rollout_summary_files

- rollout_summaries/2026-07-29T06-29-30-lLgD-swift_crypto_contiguousbytes_build_failure.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/29/rollout-2026-07-29T14-29-30-019fac90-5dd4-72d0-b8a9-bf9563d5232b.jsonl, updated_at=2026-07-29T06:29:41+00:00, thread_id=019fac90-5dd4-72d0-b8a9-bf9563d5232b, failed; no route output or workaround recorded)

### keywords

- swift run -c release pmstt routes, swift-crypto, CryptoExtras, SHA512256Digest, ContiguousBytes, RawSpan, Foundation.ContiguousBytes.withBytes, toolchain compatibility, .build/checkouts

## Reusable knowledge

- The production command reaches `/Users/omeriadon/Documents/Xcode_App_Library/pmstt/.build/checkouts/swift-crypto/Sources/CryptoExtras/Digests/SHA512256Digest.swift`. `SHA512256Digest: Digest` no longer satisfies `Foundation.ContiguousBytes` under the active SDK/toolchain because the required `withBytes` overload accepts `RawSpan`. [Task 1]
- Related skill: skills/timetable-change-verify-loop/SKILL.md [Task 1]

## Failures and how to do differently

- Symptom: `swift run -c release pmstt routes` fails with `type 'SHA512256Digest' does not conform to protocol 'ContiguousBytes'` and compiler-required `func withBytes<R, E>(_ body: (RawSpan) throws(E) -> R) throws(E) -> R`. Cause: unverified compatibility between the active Swift SDK/toolchain and pinned `swift-crypto` revision. Fix: check those versions first, then update the dependency or use a compatible toolchain; do not modify `.build/checkouts` as the durable fix. [Task 1]
- No successful build, route output, or workaround was recorded; keep the diagnosis distinct from a resolved pmstt route failure. [Task 1]

# Task Group: Timetable Planner unified timeline, term-date cards, and pre-period current-time marker

scope: SwiftUI Planner chronology and visual semantics, Today upcoming-event horizon, and the current-time marker before the first active period
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=reuse the timeline/card and marker-positioning patterns for comparable Timetable UI work, but preserve platform/layout conventions and treat source/diff checks as insufficient for runtime appearance unless the user authorizes a build or device check

## Task 1: Redesign Planner as one chronological timeline and add Today upcoming events, success

### rollout_summary_files

- rollout_summaries/2026-07-26T12-41-47-LXCh-timetable_planner_unified_timeline_and_term_date_styling.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/26/rollout-2026-07-26T20-41-47-019f9e72-2219-7ae3-9d1d-760ea7240e89.jsonl, updated_at=2026-07-26T14:10:37+00:00, thread_id=019f9e72-2219-7ae3-9d1d-760ea7240e89, source/diff validation only; user explicitly requested no build)

### keywords

- CalendarEventsView, PlannerTimelineEntry, SchoolCalendarDate, skippedDates, globalEvents, privateEvents, ScrollView, LazyVStack, figure.wave, safeAreaBar, matchedTransitionSource, navigationTransition, TodayTimetableView, seven days

## Task 2: Restyle term dates as timeline event cards, success

### rollout_summary_files

- rollout_summaries/2026-07-26T12-41-47-LXCh-timetable_planner_unified_timeline_and_term_date_styling.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/26/rollout-2026-07-26T20-41-47-019f9e72-2219-7ae3-9d1d-760ea7240e89.jsonl, updated_at=2026-07-26T14:10:37+00:00, thread_id=019f9e72-2219-7ae3-9d1d-760ea7240e89, committed 2048dfe; no build by explicit instruction)

### keywords

- SchoolCalendarProjection.termRanges, PlannerTimelineEntry(termRange:), termDate, Term Date, .orange, 2.calendar, timelineEntryContent, CalendarEventsView, 2048dfe

## Task 3: Show the current-time marker before first period, success

### rollout_summary_files

- rollout_summaries/2026-07-26T12-15-49-ColZ-pmstt_config_backup_and_pre_period_time_marker.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/26/rollout-2026-07-26T20-15-49-019f9e5a-5ab6-7153-b84c-a450f64577f3.jsonl, updated_at=2026-07-26T12:30:07+00:00, thread_id=019f9e5a-5ab6-7153-b84c-a450f64577f3, commit 286c065; no build/runtime UI verification)

### keywords

- TodayTimetableView, markerDisplayStart, markerOffset(for:), periods.first, first active period, 08:00, 08:50, -15, 286c065

## Task 4: Make every Planner card open the correct permission-aware detail or editor, partial

### rollout_summary_files

- rollout_summaries/2026-07-26T14-20-10-SZze-timetable_planner_interactions_and_scroll_animations.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/26/rollout-2026-07-26T22-20-10-019f9ecc-3505-7f53-8f0c-c0ae8321660c.jsonl, updated_at=2026-07-26T22:32:21+00:00, thread_id=019f9ecc-3505-7f53-8f0c-c0ae8321660c, source/diff and SDK-interface checked; no build/runtime verification)

### keywords

- PlannerPresentationTarget, CalendarEventEditor, pupil-free-day, global-events, private-events, duplicate-identity, paperWhite, paper, glassEffect, scrollTransition, accessibilityReduceMotion, Generic parameter 'ElementOfResult' could not be inferred, 0f28a23, 6a2fd0e

## Task 5: Expand Today subjects and apply the Planner scroll-edge effect, partial

### rollout_summary_files

- rollout_summaries/2026-08-01T04-50-31-k2B0-swiftui_admin_planner_tags_badges_friendship_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/01/rollout-2026-08-01T12-50-31-019fbba8-d448-7281-b0dd-ed684f8d17fe.jsonl, updated_at=2026-08-01T14:38:50+00:00, thread_id=019fbba8-d448-7281-b0dd-ed684f8d17fe, source/diff validation only)

### keywords

- TodayTimetableView, expandedContentOffset, 48pt, class/location details, current-time marker, CalendarEventsView, .scrollEdgeEffect(), Planner/Dates, afce7e9, eaa6d54

## User preferences

- when the user requested pupil-free days, school events, and personal events “as one chronological timeline rather than separate lists” -> model them as a unified chronological feed with visually distinct cards, rather than separate mechanical sections [Task 1]
- when the user requested “a large bottom Add Personal Event control with sheet transition morphing” -> use a full-width bottom safe-area control and matched zoom transition for similar creation flows [Task 1]
- when the user said term dates are orange, formatted the same as school events, and use symbols like `2.calendar` for Term 2 -> preserve the exact event-card styling, orange tint, and dynamic numbered SF Symbol naming [Task 2]
- when the user said “if the time is between 8 and first period, show the marker just above the first period top boundary, like negative offset if needed.” -> retain in-period positioning and explicitly handle the pre-period interval with a negative offset [Task 3]
- when the user corrected: “in the planner you should be able to click events to see details, and if you can edit, to edit them too” -> confirm the exact tab/view before editing; every visible Planner card type must be interactive, without changing Week selection behavior [Task 4]
- when the user said duplicate titles must be identifiable “by more than just their name” -> use stable composite identity for rendered rows and presentation targets [Task 4]
- when the user corrected “the background isnt brown or white, its brown paper or white paper with glass effect, as it was before” -> preserve the existing paper assets and glass treatment instead of substituting solid fills [Task 4]
- when the user explicitly requests no build -> validate with source inspection and `git diff --check` only, and state the missing build/runtime evidence rather than overriding that boundary [Task 1][Task 2]
- when the user wanted expanded Today subjects to become taller and show class/location details -> preserve animated expansion and shift all later timeline content, including the time marker [Task 5]
- when the user asked for a Planner scroll-edge effect -> apply the platform `.scrollEdgeEffect()` to the Planner/Dates scroll content [Task 5]

## Reusable knowledge

- `CalendarEventsView.swift` builds `PlannerTimelineEntry` values from `schoolCalendar.skippedDates`, `events.globalEvents`, and `events.privateEvents`, then sorts by `SchoolCalendarDate` and title. The timeline uses blue `figure.wave` pupil-free entries, yellow school events, and purple personal events. [Task 1]
- `TodayTimetableView.swift` combines global/private events from tomorrow through seven days ahead, excludes today to avoid duplicate Today cards, and sorts chronologically then by title. [Task 1]
- Convert visible `SchoolCalendarProjection.termRanges` into `PlannerTimelineEntry(termRange:)` and render through the same `timelineEntryContent`; parse the first numeric label component for `[number].calendar`. [Task 2]
- In `TodayTimetableView.swift`, start marker display at 08:00; use `periods.first` to guard no-period days and return `-15` before its start, while retaining proportional placement from the first period onward. [Task 3]
- Use one `@State private var presentationTarget: PlannerPresentationTarget?` and one `.sheet(item:)` host: personal events open `CalendarEventEditor`, global events pass through its manager gate, and pupil-free days use read-only detail. IDs include scope, date, UUID, and occurrence; term dates are informational. [Task 4]
- Planner personal cards use `paperWhite`/black; global, pupil-free, and term cards use `paper`/white with `.glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 20))`. `animatedScrollCard` applies `.scrollTransition(.animated(.snappy(duration: 0.3)))`, opacity `0.65`, and scale `0.96`, but disables those transformations for Reduce Motion. [Task 4]
- `TodayTimetableView.swift` reserves 48pt for an expanded subject and applies `expandedContentOffset` to later periods and the current-time marker, keeping class/location details animated with the row. `CalendarEventsView.swift` applies `.scrollEdgeEffect()` to Planner/Dates content. [Task 5]

## Failures and how to do differently

- Symptom: a Planner-only commit includes Settings/localization changes. Cause: the commit hook widened staging. Fix: inspect `git diff --cached --name-only` before committing; if needed, soft-reset, unstage unrelated paths, and recreate a narrow commit. [Task 1][Task 2]
- Symptom: source/diff-clean UI work is reported as visually complete. Cause: the user explicitly declined the build, so no compiler or runtime evidence exists. Fix: preserve the no-build boundary and leave the specific UI interval/surface for user-run visual verification. [Task 1][Task 2][Task 3]
- Symptom: Planner taps open a neighboring/wrong event. Cause: separate sheet state, nested interactive glass, or a wrapper `Section` competes with the card button. Fix: one presentation state keyed to the exact rendered payload; make the full button the sole interaction owner with `frame(maxWidth: .infinity)`, `contentShape`, and appropriate `zIndex`. [Task 4]
- Symptom: `Generic parameter 'ElementOfResult' could not be inferred`. Cause: `compactMap` type inference in the timeline transform. Fix: use explicit `filter` then `map`. Do not repeat the rejected Week-cell editor implementation (`0f28a23`). [Task 4]
- No build or device verification occurred for the new expansion/edge effect. Do not describe their animation, spacing, or scroll appearance as runtime-verified. [Task 5]

# Task Group: pmstt production PM2 config externalization and private backup

scope: remove a tracked deployment config without breaking the production hook, preserve a private backup, and clean credential-bearing unpublished history
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt with deployment checkout=/var/www/timetable; reuse_rule=recheck current hook, ref, config path, repository privacy, and secret rotation status before applying; exact commits and production state are time-specific

## Task 1: Externalize and privately back up `ecosystem.config.js`, success

### rollout_summary_files

- rollout_summaries/2026-07-26T12-15-49-ColZ-pmstt_config_backup_and_pre_period_time_marker.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/26/rollout-2026-07-26T20-15-49-019f9e5a-5ab6-7153-b84c-a450f64577f3.jsonl, updated_at=2026-07-26T12:30:07+00:00, thread_id=019f9e5a-5ab6-7153-b84c-a450f64577f3, pmstt sibling repo; clean commit e93d0e8 and private backup verified)

### keywords

- pmstt, ecosystem.config.js, .gitignore, gh CLI, pmstt-production-config, PM2, post-receive, /var/www/timetable, /etc/timetable/ecosystem.config.js, startOrRestart, RESEND_API_KEY, GH013, CONFIG_HASH_MATCHES_BACKUP, e93d0e8

## User preferences

- when the user asked to remove `ecosystem.config.js` from Git, keep it available for `git push production`, and back it up in a new private repository using `gh` CLI -> preserve production operation, use the GitHub CLI where appropriate, and verify both backup privacy and local/remote deployment state [Task 1]

## Reusable knowledge

- The config belonged to sibling repo `/Users/omeriadon/Documents/Xcode_App_Library/pmstt`, not the iOS checkout. It is ignored in `pmstt/.gitignore` and was removed from tracking in clean pushed commit `e93d0e8 remove production config from source`. [Task 1]
- The production hook force-checks out `/var/www/timetable`, so an ignored config inside that checkout can disappear on deployment. Keep deployment-only config at `/etc/timetable/ecosystem.config.js` with mode `600`; the hook runs `pm2 startOrRestart /etc/timetable/ecosystem.config.js --env production`. [Task 1]
- The private backup repository is `https://github.com/omeriadon/pmstt-production-config` (commit `7afb7e0`). The code uses `Environment.get("RESEND_API_KEY")!` rather than a hard-coded key. [Task 1]

## Failures and how to do differently

- Symptom: GitHub rejects the push with `GH013`. Cause: unpublished commit `ab76023` contained a tracked Resend API key. Fix: inspect unpublished history, rebuild outgoing history from `origin/main` without the secret, and rotate any credential that was committed. [Task 1]
- Symptom: a server update command is rejected before execution. Cause: its cleanup used `rm -f`. Fix: use a permitted safer operation such as `unlink`; no state changed before the rejected command. [Task 1]

# Task Group: Timetable server-authoritative events, administration accounts, and navigation UI refinements

scope: server-owned school dates/global events, private event editing, Today-card composition, admin account inspection/mutation, and section-title/sheet conventions
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck current client/server routes, authority configuration, and SwiftUI destination composition; source/commit evidence only unless the user runs builds or devices

## Task 1: Add authoritative dates/events, private events, notification schedules, and Today cards, partial

### rollout_summary_files

- rollout_summaries/2026-07-25T12-20-04-gAWx-timetable_events_admin_ui_refinements.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/25/rollout-2026-07-25T20-20-04-019f9937-e494-77c0-9b34-e14f3d01b68d.jsonl, updated_at=2026-07-26T06:56:20+00:00, thread_id=019f9937-e494-77c0-9b34-e14f3d01b68d, partial; no local build)

### keywords

- SchoolCalendarProjection, Defaults[.schoolCalendar], /v1/settings/calendar, CalendarEventsSyncService, TIMETABLE_EVENT_ADMIN_EMAILS, TodayTimetableView, TodayCardLayout.contentInset, CurrentTimeMarkerShape, break-to-period, monkey, baboon, gorilla

## Task 2: Create/delete admin accounts and show complete sanitized account JSON, partial

### rollout_summary_files

- rollout_summaries/2026-07-25T12-20-04-gAWx-timetable_events_admin_ui_refinements.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/25/rollout-2026-07-25T20-20-04-019f9937-e494-77c0-9b34-e14f3d01b68d.jsonl, updated_at=2026-07-26T06:56:20+00:00, thread_id=019f9937-e494-77c0-9b34-e14f3d01b68d, production compile fix 01a8963; runtime unverified)

### keywords

- /v1/administration/users, AdministrationUsersView, AdministrationUserEditor, AdministrationService, AdministrationController, AdministrationRawAccount, selectable JSON, password hashes, confirmationDialog, TIMETABLE_EVENT_ADMIN_EMAILS, 01a8963

## Task 3: Accent navigation titles and make matched sheet transitions the default, success

### rollout_summary_files

- rollout_summaries/2026-08-02T10-55-32-lXon-timetable_tags_dismissal_crash_and_friend_popovers.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/02/rollout-2026-08-02T18-55-32-019fc21d-5d9f-77d0-a491-84a9846c338b.jsonl, updated_at=2026-08-02T12:39:38+00:00, thread_id=019fc21d-5d9f-77d0-a491-84a9846c338b, newer recursive-title repair; no full build)
- rollout_summaries/2026-07-25T12-20-04-gAWx-timetable_events_admin_ui_refinements.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/25/rollout-2026-07-25T20-20-04-019f9937-e494-77c0-9b34-e14f3d01b68d.jsonl, updated_at=2026-07-26T06:56:20+00:00, thread_id=019f9937-e494-77c0-9b34-e14f3d01b68d, committed as 0003ad3)

### keywords

- appNavigationTitle, navigationTitle, AppNavigationTitleModifier, accent: Bool, foregroundStyle(.accent), matchedTransitionSource, navigationTransition, Namespace, recursive navigation title, af7eef4, 0003ad3

## Task 4: Render recursively decoded account JSON and show global events read-only to non-managers, success

### rollout_summary_files

- rollout_summaries/2026-07-26T07-08-05-GQTX-timetable_auth_sharing_admin_ui_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/26/rollout-2026-07-26T15-08-05-019f9d40-9ca7-7981-89a3-bce65b53257d.jsonl, updated_at=2026-07-26T08:32:08+00:00, thread_id=019f9d40-9ca7-7981-89a3-bce65b53257d, source/commit validated; no build/test)

### keywords

- AdministrationJSONFormatter, AdministrationJSONRenderer, prettyPrinted, sortedKeys, settingsData, subjectsData, base64, CalendarEventEditor, isReadOnlyGlobalEvent, canManageGlobalEvents, 8857e0a, f8c211c

## Task 5: Make account JSON hierarchy native rows and update personal event-tag presentation, partial

### rollout_summary_files

- rollout_summaries/2026-08-02T10-55-32-lXon-timetable_tags_dismissal_crash_and_friend_popovers.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/02/rollout-2026-08-02T18-55-32-019fc21d-5d9f-77d0-a491-84a9846c338b.jsonl, updated_at=2026-08-02T12:39:38+00:00, thread_id=019fc21d-5d9f-77d0-a491-84a9846c338b, newer personal-tag flattening; no build/runtime test)
- rollout_summaries/2026-08-01T04-50-31-k2B0-swiftui_admin_planner_tags_badges_friendship_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/01/rollout-2026-08-01T12-50-31-019fbba8-d448-7281-b0dd-ed684f8d17fe.jsonl, updated_at=2026-08-01T14:38:50+00:00, thread_id=019fbba8-d448-7281-b0dd-ed684f8d17fe, source/diff validation only)

### keywords

- AdministrationUserEditor, expanded node IDs, stable hierarchical IDs, native list rows, formatted content row, EventTagSelector, TagSubscriptionsView, EventTagSelectionView, EventTagCatalogueSection, NavigationLink, Tags, year-group, a904c35, eaa6d54

## User preferences

- when adding school dates/events, the user required global/term/no-school data to remain server-authoritative and non-editable while private user events remain editable -> preserve this authority split rather than treating all calendar rows as local content [Task 1]
- when refining Today cards, the user repeatedly said “remove the inconsistent padding” and “add horizontal padding to the items INSIDE” -> use shared outer widths with explicit inner inset constants; do not compensate with inconsistent outer padding [Task 1]
- when applying glass to the red current-time marker, the user requested “one composited shape before applying glass” -> compose the marker geometry first, then apply the glass effect [Task 1]
- when inspecting accounts, the user asked for “literally everything except passwords,” but not raw/base64 data -> provide one complete readable selectable sanitized JSON document, excluding passwords/hashes [Task 2]
- when deleting an account, the user required a destructive confirmation dialog [Task 2]
- sheets should default to matched transition effects, with one namespace per view host and distinct IDs; section navigation titles should use `.accent` foreground styling [Task 3]
- when the user asked to “show the bloody data with correct formatting and indenting” and decode base64 account settings -> use a bounded readable JSON viewer that recursively expands direct JSON and valid base64 JSON, rather than raw opaque blobs [Task 4]
- when the user specified no symbol row/edit title, large title, textual date, trailing symbol, no confirm, and Close only -> implement an explicit non-manager read-only branch while preserving editable/admin behavior [Task 4]
- when the user said “2nd level items also need to be each one as a list row themselves” and their content also needs its own row -> render hierarchy levels as native, individually inspectable rows with stable IDs instead of embedding nested stacks [Task 5]
- the 2026-08-01 request for “one navlink for the tags, then each tag section is just a section inside the list” was superseded for the personal tag UI by “remove sections from tags. everything is just one bucket” -> keep any necessary navigation entry, but flatten the visible personal tag list while retaining category/year-group behavior internally [Task 5]

## Reusable knowledge

- `SchoolCalendarProjection` is server-owned, persisted in `Defaults[.schoolCalendar]`, and downloaded from `/v1/settings/calendar`. Calendar events synchronize during account bootstrap; global administration authority reads comma-separated `TIMETABLE_EVENT_ADMIN_EMAILS`, trims whitespace, and compares emails case-insensitively. [Task 1]
- `Main/Tabs/Timetable/TodayTimetableView.swift` centralizes 14pt card content padding in `TodayCardLayout.contentInset` for Events Today, No School Today, and Classes. The marker is `CurrentTimeMarkerShape` with `.glassEffect(..., in:)`. Notification settings now have separate break-to-period lead times and event schedules; the scheduler treats periods 1/3/5 as break-to-period transitions. [Task 1]
- Administration uses `/v1/administration/users` and `/v1/administration/users/:userID` for create, detail/update, and deletion. Complete detail includes metadata, owner/created timetables, received records, devices, calendar events, notification deliveries, and sessions; exclude authentication secrets. `AdministrationUserEditor` pretty-prints selectable monospaced JSON and confirms deletion. [Task 2]
- `appNavigationTitle(accent: Bool)` applies `.foregroundStyle(.accent)` to iOS principal-title text; inside `AppNavigationTitleModifier`, invoke native `.navigationTitle(title)`, never the custom modifier recursively. [Task 3]
- `AdministrationJSONFormatter` uses `.prettyPrinted`, `.sortedKeys`, recursive nested JSON expansion, and base64 decoding for generic `settingsData`/`subjectsData`. `CalendarEventEditor.isReadOnlyGlobalEvent` suppresses save/delete/title/symbol controls for global events when `canManageGlobalEvents` is false. [Task 4]
- `AdministrationUserEditor.swift` tracks expanded node IDs and renders root rows, second-level rows, and formatted content separately. The newer personal `EventTagSelector`/`TagSubscriptionsView` requirement is a single visible bucket without section headers, but retains category metadata and year-group exclusivity internally. [Task 5]

## Failures and how to do differently

- Symptom: a tab shell appears complete but shows temporary content. Cause: placeholder destinations (`monkey`, `baboon`, `gorilla`) were not inspected. Fix: inspect every destination before claiming the shell complete. [Task 1]
- Symptom: a broad Swift/Codable patch becomes malformed. Cause: large structural patches were applied without immediate inspection. Fix: patch smaller units and inspect affected declarations/files after each structural edit. [Task 1]
- Symptom: production compile fails at `AdministrationRawAccount(user)`. Cause: missing `try` was not caught because local builds were intentionally skipped. Fix: carry out compile-oriented review of throwing server calls even under a no-build constraint; the production repair was `01a8963`. [Task 1][Task 2]
- Symptom: admin details feel incomplete. Cause: sectioned/partial representations hide persisted data. Fix: return/render one complete sanitized JSON document, decoding `Data` as UTF-8 when possible. [Task 2]
- No build/test was run for the formatter/read-only branch; treat those commits as source/diff validated only. [Task 4]
- No compilation or runtime check covered the account-row hierarchy or the newer flat personal tag presentation. Preserve unrelated dirty-file boundaries before continuing or committing: `AdministrationEventTagsView.swift`, `FriendDetailView.swift`, and `FriendSearchRow.swift` were unstaged at rollout end. [Task 5]

# Task Group: Timetable Messages plain-link sharing and pmstt route-contract reconciliation

scope: Messages extension outgoing sharing and the current public/API pmstt route split; use to reconcile client-generated URLs with current pmstt routing
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck both active checkouts together before changing link generation or routes; the July 26 source evidence restores public `/share/:locator`, but deployment/browser runtime remains unverified

## Task 1: Replace rich Messages payload with plain website link, success

### rollout_summary_files

- rollout_summaries/2026-07-25T07-59-00-gYgv-messages_plain_share_link.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/25/rollout-2026-07-25T15-59-00-019f9848-e0b9-7813-944e-448ba24c03ef.jsonl, updated_at=2026-07-25T08:00:58+00:00, thread_id=019f9848-e0b9-7813-944e-448ba24c03ef, narrow commit d8ea560; no build/runtime validation)

### keywords

- MessagesViewController, MSMessagesAppViewController, sendTimetable, activeConversation?.insertText, MSMessageTemplateLayout, /share/<locator>, d8ea560

## Task 2: Prefix Vapor API routes and temporarily remove legacy public share routes, superseded

### rollout_summary_files

- rollout_summaries/2026-07-25T06-58-58-v8rH-pmstt_prefix_api_routes_remove_legacy_share_routes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/25/rollout-2026-07-25T14-58-58-019f9811-e75b-76b1-959a-2681bceb983d.jsonl, updated_at=2026-07-25T07:02:13+00:00, thread_id=019f9811-e75b-76b1-959a-2681bceb983d, committed 5c362af; no build/tests)

### keywords

- Vapor, RoutesBuilder, app.grouped("api"), /api/v1, /health, apple-app-site-association, SharedTimetableController, /share/:locator, /sharedtimetable/:locator, 5c362af

## Task 3: Restore public alias/UUID browser links while retaining authenticated API routes, success but runtime unverified

### rollout_summary_files

- rollout_summaries/2026-07-26T07-08-05-GQTX-timetable_auth_sharing_admin_ui_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/26/rollout-2026-07-26T15-08-05-019f9d40-9ca7-7981-89a3-bce65b53257d.jsonl, updated_at=2026-07-26T08:32:08+00:00, thread_id=019f9d40-9ca7-7981-89a3-bce65b53257d, client/server commits 173a105 and e398bc4; no build/deploy/Safari test)

### keywords

- /share/:locator, /api/v1/shared-timetables/:locator, AuthoritativeTimetableResolver.resolvePublic, TimetableShareAliasService, fetchCurrentAlias, ShareSelectionSheet, RouteNotFound.404, e398bc4, 173a105

## Task 4: Migrate the Messages extension layout and interaction state to SwiftUI, partial

### rollout_summary_files

- rollout_summaries/2026-07-25T11-06-07-Q5UF-watch_signin_cycle_and_messages_swiftui_migration.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/25/rollout-2026-07-25T19-06-08-019f98f4-30f3-7ff1-bd4e-0143deafa2ed.jsonl, updated_at=2026-07-25T11:21:01+00:00, thread_id=019f98f4-30f3-7ff1-bd4e-0143deafa2ed, committed 2bbe9b3; source/diff validation only)

### keywords

- Messages.appex, MSMessagesAppViewController, UIHostingController, MessagesRootView, MessagesViewModel, pendingMessageTimetableLocators, TimetableMessages, 2bbe9b3

## User preferences

- when the user said “just add the link to the website, not the whole image thing” -> make the narrow outgoing-link change and leave legacy incoming parsing/import behavior intact [Task 1]
- when the user said “health and .well-known stay as is” -> preserve root infrastructure endpoints in route-prefix migrations [Task 2]
- when the user said “/share (/sharedtimetable) should not exist anymore” and then “you do it” -> remove obsolete public routes and directly execute the confirmed scoped change [Task 2]
- when the user reported UUID fallback, “already my link,” and Safari not found -> treat alias customization as one cross-layer contract: authoritative GET hydration, observed cache state, canonical URL generation, and public route resolution [Task 3]

## Reusable knowledge

- `Messages/MessagesViewController.swift` can send link-only output with `activeConversation?.insertText(url.absoluteString)`; this removes `MSMessageTemplateLayout`, image, captions, query metadata, and `MSMessage` construction while keeping legacy incoming parsing. [Task 1]
- In `Sources/pmstt/routes.swift`, register controllers through `let api = app.grouped("api")` to make their existing `/v1/...` routes `/api/v1/...`; keep `app.get("health")` and `app.get(".well-known", "apple-app-site-association")` directly on `app`. The temporary public-route removal in Task 2 was superseded by Task 3. [Task 2][Task 3]
- `Messages/MessagesViewController.swift` must remain a thin `MSMessagesAppViewController` host because the extension principal-class contract requires it; embed `MessagesRootView` with `UIHostingController`, and keep conversation activation, link insertion, import submission, App Group queueing, and shared Keychain lookup in `MessagesViewModel`. The filesystem-synchronized `Messages` target needs no `project.pbxproj` edit for these Swift files. [Task 4]
- `fetchCurrentAlias()` must use GET; PUT is only for updates. `ShareSelectionSheet` fetches on appearance and observes `@Default(.ownerTimetableShareAlias)`. Public `/share/:locator` is root-registered and resolves UUID or alias through `AuthoritativeTimetableResolver.resolvePublic`; authenticated `/api/v1/shared-timetables/:locator` stays under `api`. [Task 3]

## Failures and how to do differently

- The Task 1/Task 2 `/share` mismatch is resolved in later source by restoring public `/share/:locator`; do not claim plain Messages/Safari sharing works until deployment, restart, and browser/device runtime checks succeed. [Task 1][Task 2][Task 3]
- Symptom: a narrow commit contains unrelated work after a hook. Cause: the hook widened staging. Fix: inspect `git show --name-only HEAD` and staged names; if necessary, soft-reset, unstage unrelated paths, and commit the intended file with `--no-verify` only when justified. [Task 1]
- Both commits have source/diff or formatting evidence only; no build, route integration, or signed-device Messages verification occurred. [Task 1][Task 2]
- Symptom: a SwiftUI migration removes the UIKit host entirely. Cause: the layout migration is mistaken for a principal-class migration. Fix: retain `MSMessagesAppViewController` as the extension host and move only layout/interaction state into SwiftUI. No build or Messages runtime validation was recorded for this implementation. [Task 4]

# Task Group: Timetable Xcode iPad Simulator Watch embedding and universal-target restoration

scope: diagnose iPad-only Simulator failures involving the embedded Watch app without breaking the unified iPhone/iPad/Watch distribution target
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=inspect current Xcode project settings and ask for GUI-first confirmation before manual project edits; do not reuse destination-specific workarounds without user-run build evidence

## Task 1: Restore universal iOS target and diagnose iPad embedding, partial

### rollout_summary_files

- rollout_summaries/2026-07-25T01-55-59-bpiB-ipad_watch_embedding_universal_target_gui_first.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/25/rollout-2026-07-25T09-55-59-019f96fc-84c8-7880-b306-1bfa2445b71d.jsonl, updated_at=2026-07-25T07:28:25+00:00, thread_id=019f96fc-84c8-7880-b306-1bfa2445b71d, universal target restored; rebuild remained failing)

### keywords

- Xcode, iPad Simulator, Watch.app, Embed Watch Content, platformFilter, TARGETED_DEVICE_FAMILY, SUPPORTED_PLATFORMS, TARGET_DEVICE_MODEL, TestFlight, DerivedData, project.pbxproj, c665f5c

## User preferences

- after repeated project edits, the user said “think before doing stuff. ask me if i can do it in the xcode project settings gui” -> explain the likely setting/diagnosis and ask whether the user can inspect or change it in Xcode GUI before manually editing `.pbxproj`, adding phases, or deleting Derived Data [Task 1]
- when the user rejected target splitting because one TestFlight/App Store listing must support iPhone, iPad, and Watch -> preserve the existing universal iOS target unless separate targets are explicitly approved [Task 1]
- when the user clarified that iPhone Simulator always worked and failure is iPad Simulator-specific -> do not apply simulator-wide exclusions; distinguish iPad Simulator, iPhone Simulator, and physical devices [Task 1]

## Reusable knowledge

- The restored `Timetable` target uses `TARGETED_DEVICE_FAMILY = "1,2"`, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, and `Embed Watch Content` with `platformFilter = ios`; that filter cannot distinguish iPhone from iPad. Commit `c665f5c` removed the temporary iPad target and restored the intended distribution model. [Task 1]
- An iPad Simulator destination reported `TARGET_DEVICE_PLATFORM_NAME=iphonesimulator` and `TARGET_DEVICE_MODEL=iPad17,4` while `PLATFORM_NAME=iphoneos`, so destination-variable workarounds are fragile until the user verifies a build. [Task 1]

## Failures and how to do differently

- Adding Watch `SUPPORTED_PLATFORMS = "watchos watchsimulator"` did not fix the problem. Removing Watch content by shell phase was initially too broad, later iPad-narrowed, unverified, and removed. Do not add workaround phases before confirming a GUI limitation and obtaining approval. [Task 1]
- Post-restoration diagnostics included `Couldn't load Info dictionary ... Timetable.app/Watch/Watch.app`, unresolved `Defaults`/`IrregularGradient`, and missing Watch modules. They may be cascading Derived Data/build-graph artifacts, but no successful rebuild established the cause. [Task 1]

# Task Group: Timetable received-timetable comparison projection and preview-grid indexing

scope: main timetable comparison visibility for synced/saved projections plus direct validation of zero-based timetable preview-grid conditions
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=safe for closely related Timetable received-projection display and preview-grid condition fixes, but verify the active `ForEach` ranges, weekday ordering, and source-kind requirements first

## Task 1: Show saved timetables in main comparison without dropping account-owner records, success

### rollout_summary_files

- rollout_summaries/2026-07-24T12-58-25-J1ms-saved_timetables_comparison_and_preview_grid_index_fix.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/24/rollout-2026-07-24T20-58-25-019f9434-a473-7ad0-a3d0-2089b1aafe9c.jsonl, updated_at=2026-07-24T14:37:36+00:00, thread_id=019f9434-a473-7ad0-a3d0-2089b1aafe9c, committed as `a16538ed`; no build)

### keywords

- TimetableComparison, receivedTimetables, ReceivedTimetableSyncService, Defaults[.receivedTimetables], accountOwner, sourceKind, isDeleted, Main/Tabs/Timetable/TimetableComparison.swift, a16538ed

## Task 2: Validate last-period Wednesday and Friday preview-grid indices, success

### rollout_summary_files

- rollout_summaries/2026-07-24T12-58-25-J1ms-saved_timetables_comparison_and_preview_grid_index_fix.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/24/rollout-2026-07-24T20-58-25-019f9434-a473-7ad0-a3d0-2089b1aafe9c.jsonl, updated_at=2026-07-24T14:37:36+00:00, thread_id=019f9434-a473-7ad0-a3d0-2089b1aafe9c, direct source/range validation)

### keywords

- TimetablePreviewGrid, ForEach(0 ..< 8), ForEach(0 ..< 5), zero-based-index, session == 7, day == 2, day == 4, Wednesday, Friday

## User preferences

- when saved timetables synchronized in Settings and Watch but not the main timetable -> compare each UI’s shared projection and local filtering before investigating sync transport [Task 1]
- when the user asked whether conditions meant “last period wednesday and friday” -> validate the actual loop ranges and weekday ordering directly rather than assuming one-based indices [Task 2]

## Reusable knowledge

- `ReceivedTimetableSyncService.refreshAuthoritativeProjection()` writes the authoritative received projection to `Defaults[.receivedTimetables]`; Settings and Watch iterate it directly [Task 1]
- `TimetableComparison` must retain `!$0.isDeleted` but must not exclude `.accountOwner` when it is meant to show all saved/received non-deleted timetables. The committed fix is `receivedTimetables.filter { !$0.isDeleted }` in `Main/Tabs/Timetable/TimetableComparison.swift` [Task 1]
- `ForEach(0 ..< 8)` yields sessions `0...7`, and Monday-first `ForEach(0 ..< 5)` yields weekdays `0...4`; last-period Wednesday/Friday is `session == 7 && (day == 2 || day == 4)` [Task 2]

## Failures and how to do differently

- Symptom: a UI omits timetables that appear in Settings and Watch. Cause: a view-local stale source-kind exclusion, not necessarily failed synchronization. Fix: compare projection consumers, keep deletion filtering, and remove only the unsupported source-kind filter [Task 1]
- Symptom: special preview cells never match. Cause: one-based values such as `session == 8`, `day == 3`, or `day == 5` are used against zero-based ranges. Fix: inspect range bounds before expressing the condition [Task 2]
- No build or runtime verification was performed; `git diff --check`, SwiftFormat during commit, and a clean worktree are source-level evidence only [Task 1]

# Task Group: Timetable account setup and authoritative owner-timetable sync

scope: sign-in-only versus onboarding-based account creation, iPadOS/macOS Apple authentication policy, and server-authoritative owner timetable caching across devices
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=recheck current platform authority and sync contracts, but reuse the separation of account creation from sign-in and server-canonical owner-timetable reconciliation

## Task 1: Route account creation through onboarding while retaining companion Apple setup, success

### rollout_summary_files

- rollout_summaries/2026-07-24T08-29-59-vPGu-timetable_cross_device_live_activity_notification_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/24/rollout-2026-07-24T16-29-59-019f933e-e01f-7661-a109-5e7c4fb7f9be.jsonl, updated_at=2026-07-24T11:28:26+00:00, thread_id=019f933e-e01f-7661-a109-5e7c4fb7f9be, committed; no build/device verification)

### keywords

- AccountAuthenticationView, allowsSignUp: false, Create an Account, OnboardingAccount, Platform.current, iOS on Mac, iPadOS, allowsAppleAuthentication, allowsAccountCreation, allowsOwnerMutation, SessionAuthority

## Task 2: Make non-empty server owner timetable canonical and cache the projection, success

### rollout_summary_files

- rollout_summaries/2026-07-24T08-29-59-vPGu-timetable_cross_device_live_activity_notification_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/24/rollout-2026-07-24T16-29-59-019f933e-e01f-7661-a109-5e7c4fb7f9be.jsonl, updated_at=2026-07-24T11:28:26+00:00, thread_id=019f933e-e01f-7661-a109-5e7c4fb7f9be, Timetable `24d4db8`; runtime unverified)

### keywords

- OwnerTimetableSyncService, cache(_:), Defaults[.timetable], RGBAColor, Subject, ServerSyncCoordinator.saveOwnerTimetable, CalendarImportView, Spotlight, WidgetKit, authoritative reconciliation

## User preferences

- when the user said “dont allow sign up as it currently is” and asked for a bottom signup action that opens onboarding -> keep iPhone sign-in surfaces sign-in-only and route signup through onboarding [Task 1]
- when the user’s standing instruction was no builds/tests -> do not run builds, tests, or device verification unless explicitly reauthorized; report the exact unverified boundary [Task 1][Task 2]
- preserve unrelated active edits: after hooks, inspect staged contents and restore pre-existing paths from the index before amending a narrow behavior commit [Task 1]

## Reusable knowledge

- `Platform.current` classifies iOS-on-Mac as `.iPadOS`. `allowsAppleAuthentication` can be broader than `allowsAccountCreation` / `allowsOwnerMutation`, letting pmstt accept Apple setup/sign-in on iPadOS/macOS without granting authoritative mutations. `AccountAuthenticationView` defaults to signup disabled; onboarding explicitly passes `allowsSignUp: true`. [Task 1]
- Subject colour is shared `RGBAColor` persistence on `Subject`, so cross-device colour mismatch points to source-of-truth/reconciliation rather than renderer-specific colour generation. `OwnerTimetableSyncService.cache(_:)` updates `Defaults[.timetable]`, owner visibility/id, last sync, Spotlight, and WidgetKit. [Task 2]
- Non-empty server subjects are canonical; local timetable data seeds only an empty server. Calendar import must await `ServerSyncCoordinator.saveOwnerTimetable` before committing local success progression. [Task 2]

## Failures and how to do differently

- The account and owner-sync changes were committed but not built, cross-device-synced, or exercised on devices; do not promote their runtime behavior beyond source-level intent. [Task 1][Task 2]
- Symptom: a narrow commit includes unrelated Watch files after SwiftFormat. Cause: the hook widened staging. Fix: run `git show --name-status --format=oneline HEAD`, `git status --short`, and `git diff --cached --name-status`, reset only the unrelated index paths, then amend with `--no-verify` when justified. [Task 1]

# Task Group: Timetable cached authenticated session startup across iOS, iPadOS, macOS, and watchOS

scope: shared `SessionStore` startup-auth policy; use for eliminating a restoring screen while cached account data is still valid
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=safe for Timetable authentication startup work across platform roots, but treat the current API error types and commit as checkout-specific

## Task 1: Preserve cached signed-in state during startup restoration, success

### rollout_summary_files

- rollout_summaries/2026-07-23T03-40-49-LHuA-timetable_cached_authenticated_startup_ui.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/23/rollout-2026-07-23T11-40-49-019f8d0f-c81a-74c3-8911-e4d9390b7c9c.jsonl, updated_at=2026-07-23T03:44:30+00:00, thread_id=019f8d0f-c81a-74c3-8911-e4d9390b7c9c, shared policy changed and committed; no build/test by instruction)

### keywords

- SessionStore, AuthenticationState, Defaults[.accountProfile], restore(), .authenticated(profile), .restoring, clearSessionState(), sessionExpired, HTTP 401, App Shared/Session/SessionStore.swift, WatchSessionRootView

## User preferences

- when the user said “all platforms ... show the signed in view with the @Defaults cached data until after it receives a response from whatever api that says its signed out or deleted.” -> render cached authenticated UI immediately on every platform; clear it only after explicit server invalidation [Task 1]
- the user’s standing instruction in this workflow was “never do swift builds. only i do. any builds for that matter.” -> do not run builds or tests unless they explicitly change that boundary [Task 1]

## Reusable knowledge

- `App Shared/Session/SessionStore.swift` is the centralized startup auth gate; platform roots switch on `AuthenticationState`, so changing this shared store updates iOS, iPadOS, macOS, and watchOS [Task 1]
- `Defaults[.accountProfile]` identifies a cached account. Initialize `.authenticated(profile)` when it exists and retain that state while `restore()` refreshes credentials; otherwise initialize `.restoring` [Task 1]
- Only confirmed HTTP 401 or server `.sessionExpired` responses should reach `clearSessionState()`. Transient `NetworkError`, decode, and silent-refresh failures preserve the cached authenticated surface [Task 1]

## Failures and how to do differently

- Symptom: a startup “Restoring Account…” screen hides a known signed-in session. Cause: initialization or `restore()` unconditionally replaces cached auth with `.restoring`. Fix: keep `.authenticated(profile)` until an explicit revoked/expired/deleted response arrives [Task 1]
- Symptom: a path search finds no session store. Cause: the path was guessed as `Shared/SessionStore.swift`. Fix: use `App Shared/Session/SessionStore.swift` [Task 1]

# Task Group: Timetable + pmstt notification lead-time multi-selection and Codable compatibility

scope: cross-platform notification timing selection, scheduler deduplication, and client/server Codable compatibility while migrating singular `notificationLeadTime` to `notificationLeadTimes`
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=safe for this field migration and analogous Codable compatibility work, but verify current stored properties, route contracts, and deployed commits before reuse




## Task 4: Make exact selected lead times and APNs expiry explicit, partial

### rollout_summary_files

- rollout_summaries/2026-07-24T08-29-59-vPGu-timetable_cross_device_live_activity_notification_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/24/rollout-2026-07-24T16-29-59-019f933e-e01f-7661-a109-5e7c4fb7f9be.jsonl, updated_at=2026-07-24T11:28:26+00:00, thread_id=019f933e-e01f-7661-a109-5e7c4fb7f9be, committed; tests/build/production delivery not run)

### keywords

- SchoolNotificationScheduler, SchoolNotificationDelivery, NotificationLeadTime, leadMinutes, collapse ID, duplicate APNs token, apns-expiration, NotificationService.apnsExpiration, 180s, 0981e75

## User preferences


## Reusable knowledge

- `SchoolNotificationScheduler` must evaluate every candidate event against each selected `NotificationLeadTime`; generate labels from the exact `leadMinutes`, include those minutes in claims/collapse IDs, and suppress duplicate identical tokens per debug/production environment while retaining distinct watch/phone tokens. `NotificationService.apnsExpiration(sentAt:)` returns `sentAt + 180s` and logs the header. [Task 4]

## Failures and how to do differently

- Exact-label, simultaneous-delivery, and three-minute-expiry tests were added but not run; do not claim production duplicate prevention from code-level claims/collapse IDs alone. [Task 4]

# Task Group: Timetable Live Activity APNs delivery diagnosis and school-day retention

scope: production Live Activity delivery investigation, token/device persistence, and APNs expiration behavior between Timetable and sibling pmstt
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=safe for Timetable/pmstt Live Activity APNs diagnosis, but treat production records, logs, and dismissal time as time-specific

## Task 1: Diagnose delivery and retain pushes through the Perth school-day dismissal, success

### rollout_summary_files

- rollout_summaries/2026-07-22T10-09-06-Uco6-timetable_live_activity_onboarding_ui_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/22/rollout-2026-07-22T18-09-06-019f894c-e793-7130-91a0-7940eb1320e6.jsonl, updated_at=2026-07-22T11:52:08+00:00, thread_id=019f894c-e793-7130-91a0-7940eb1320e6, production evidence isolated persistence/expiry rather than APNs topic failure)

### keywords

- APNs Live Activity response status: 200, DELETE /v1/devices/current/live-activity-token, DELETE /v1/devices/current, apns-expiration, Australia/Perth, 15:30, LiveActivityRegistrationService, LiveActivityAPNSService

## Task 2: Diagnose missing activities and restore stale or absent activity on authenticated launch, success

### rollout_summary_files

- rollout_summaries/2026-07-23T03-20-03-lrWx-live_activity_token_investigation_launch_reconciliation.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/23/rollout-2026-07-23T11-20-04-019f8cfc-c63f-7221-bc31-879e71eb8201.jsonl, updated_at=2026-07-23T03:30:05+00:00, thread_id=019f8cfc-c63f-7221-bc31-879e71eb8201, production pmstt deployment/health check passed; physical-device verification pending)

### keywords

- ActivityKit, LiveActivityRegistrationService, activeActivityKeys, UserDevice, SchoolDayLiveActivity, push-to-start-token, reconcile, APNs 200, PostgreSQL, /var/www/timetable, git push production main

## User preferences

- when the user asked to “read the git log to see what i mean” before editing -> inspect recent commits, token lifecycle, server path, production logs, and persisted device/activity records before attributing delivery failure to a refactor [Task 1]
- when the user asked for retention “for the whole school day ... until 3:30pm” -> calculate expiry against the Perth school-day dismissal [Task 1]
- when the user asked to “read the db, if any live activity tokens even exist, before continuing” -> inspect production `user_devices` and `school_day_live_activities` rows plus APNs/server behavior before changing code [Task 2]
- when the user asked whether launch can check whether the activity “should be running but isnt, then starts it again” -> compare actual local ActivityKit keys with active server records and only restore when absent. [Task 2]

## Reusable knowledge

- HTTP 200 responses for four production Live Activity starts proved the APNs topic/payload path worked in this incident. The device’s explicit deletion of both its Live Activity token and device registration left no current record to trigger [Task 1]
- `LiveActivityAPNSService` now supplies `apns-expiration` through 15:30 using the configured `Australia/Perth` calendar, so a phone offline at send time can receive the school-day activity later [Task 1]
- Delivery is row-driven from `UserDevice.liveActivityPushToStartToken` and `SchoolDayLiveActivity`; token presence and a current-day activity row are separate facts to inspect. The July 23 production database had four devices with both token types, but the newest registered after the scheduler start and had no current-day row. [Task 2]
- Launch reconciliation sends optional `activeActivityKeys` from `Activity<SchoolDayActivityAttributes>.activities`. pmstt preserves an active record whose key exists locally; if server records are active but none match local keys, it ends stale records and sends a replacement start push. Older clients omit the optional field and retain prior behavior. [Task 2]

## Failures and how to do differently

- Symptom: production Live Activity does not start after token-lifecycle work. Cause: assuming a token refactor caused it without checking APNs responses and persistence; this incident had accepted pushes but no current device/activity record. Fix: inspect APNs status/reason plus device and Live Activity rows before changing token code [Task 1]
- Symptom: an offline phone misses an otherwise valid start push. Cause: the APNs request has no expiration and behaves as immediate-only. Fix: add an expiry appropriate to the intended school-day window [Task 1]
- Symptom: ordinary authenticated launch registers its token but does not receive today’s activity. Cause: registration occurred after the scheduler run and launch did not reconcile. Fix: request launch reconciliation after token observation. [Task 2]
- Symptom: server thinks an activity is active while the device has none. Cause: the first launch repair only handled no server row. Fix: send and compare local ActivityKit keys, then replace stale server records. On production SSH, locate deployed source under `/var/www/timetable`; use `grep`/`find` because `rg` was unavailable. [Task 2]

# Task Group: Timetable iOS onboarding account gate, safe-area controls, and scroll-edge gradient semantics

scope: iOS first-run onboarding/auth ordering, reliable pager controls, in-place account confirmation, and `BlackGradientOverlay` directional offset behavior
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable; reuse_rule=safe for closely related Timetable onboarding/UI-effect repairs, but preserve macOS-only auth behavior and verify current view composition before reuse

## Task 1: Keep onboarding before full iOS sign-in/sign-up and gate signed-out content, success

### rollout_summary_files

- rollout_summaries/2026-07-22T10-09-06-Uco6-timetable_live_activity_onboarding_ui_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/22/rollout-2026-07-22T18-09-06-019f894c-e793-7130-91a0-7940eb1320e6.jsonl, updated_at=2026-07-22T11:52:08+00:00, thread_id=019f894c-e793-7130-91a0-7940eb1320e6, iOS post-onboarding auth gate and account page corrected)

### keywords

- TimetableApp, hasCompletedOnboarding, AccountAuthenticationView(), allowsSignUp, allowsAppleSignIn, sheet, fullScreenCover, OnboardingView, iOS, macOS

## Task 2: Repair bottom navigation hit areas and account-ready confirmation, success

### rollout_summary_files

- rollout_summaries/2026-07-22T10-09-06-Uco6-timetable_live_activity_onboarding_ui_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/22/rollout-2026-07-22T18-09-06-019f894c-e793-7130-91a0-7940eb1320e6.jsonl, updated_at=2026-07-22T11:52:08+00:00, thread_id=019f894c-e793-7130-91a0-7940eb1320e6, safe-area bar removed competing hit-test layer)

### keywords

- safeAreaBar(edge: .bottom), overlay(alignment: .bottom), ignoresSafeArea(), hit-testing, 56x56, contentShape(Circle()), OnboardingAccountView, Account Ready, blurReplace

## Task 3: Correct reverse-direction scroll-edge gradient offset, success

### rollout_summary_files

- rollout_summaries/2026-07-22T10-09-06-Uco6-timetable_live_activity_onboarding_ui_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/22/rollout-2026-07-22T18-09-06-019f894c-e793-7130-91a0-7940eb1320e6.jsonl, updated_at=2026-07-22T11:52:08+00:00, thread_id=019f894c-e793-7130-91a0-7940eb1320e6, edge-relative offset contract restored)

### keywords

- BlackGradientOverlay, scrollEdgeEffect, offset: 0.85, clearTopDarkBottom, darkTopClearBottom, logicalOffset, 1 - offset


## Task 6: Replace iPhone post-sign-out sheet with full auth over the onboarding splash, success

### rollout_summary_files

- rollout_summaries/2026-07-23T13-37-33-8lws-iphone_signout_authentication_splash_background.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/23/rollout-2026-07-23T21-37-33-019f8f32-1b40-7b62-a582-6a36cff909b0.jsonl, updated_at=2026-07-23T13:39:37+00:00, thread_id=019f8f32-1b40-7b62-a582-6a36cff909b0, targeted commit; no Xcode/MCP build)

### keywords

- IOSSignInGateView, AccountAuthenticationView, OnboardingBackground, ColorfulX, splash, signOut, TimetableApp, MacSignInGateView, d759ec3


## User preferences

- when the user said the auth view is “for and only for mac,” while iPhone must allow sign-up -> keep macOS-only login behavior separate; iPhone uses shared `AccountAuthenticationView()` with sign-up/Apple sign-in [Task 1]
- when the user required onboarding before sign-in/up and no sheet/full-screen-cover conflict -> show post-onboarding auth only after `hasCompletedOnboarding` is true [Task 1]
- when bottom buttons worked only “1/10 clicks” and the user asked for padding changes -> make hit targets explicitly large and safe-area positioned [Task 2]
- when the user wanted a sign-in success state as “just a checkmark” with `blurReplace` -> replace the form in place with `Account Ready` confirmation [Task 2]
- when the user specified `offset: 0.85` means 85% from the clear edge -> preserve logical edge-relative offset semantics and leave the default direction unchanged [Task 3]
- when the user asked that iPhone sign-out show `AccountAuthenticationView` with “the same one used by the splash view in the onboarding” -> reuse `OnboardingBackground(currentPageID: "splash")`, retain full iPhone sign-in/sign-up/Apple auth, and leave `MacSignInGateView` unchanged. [Task 6]

## Reusable knowledge

- Signed-out iOS renders no timetable content. After completed onboarding, `IOSSignInGateView` uses a `ZStack` with `OnboardingBackground(currentPageID: "splash")` behind a scrollable full `AccountAuthenticationView()`; macOS keeps its separate gate. [Task 1][Task 6]
- A bottom full-screen `.overlay(...).ignoresSafeArea()` can intercept pager taps. Use `.safeAreaBar(edge: .bottom)`; use 56x56 circular controls with wider horizontal and reduced bottom insets [Task 2]
- `OnboardingAccountView` can switch form -> checkmark “Account Ready” state using `.transition(.blurReplace)` keyed to authentication state [Task 2]
- `BlackGradientOverlay` must clamp `logicalOffset`, use it directly for `.clearTopDarkBottom`, and invert it only for `.darkTopClearBottom` [Task 3]

## Failures and how to do differently

- Symptom: iPhone cannot sign up or auth appears before onboarding. Cause: macOS-only login restrictions were applied to iOS or the auth sheet overlaps the onboarding full-screen cover. Fix: preserve the separate macOS behavior and gate iOS auth on completed onboarding [Task 1]
- Symptom: pager controls have unreliable taps. Cause: a full-screen safe-area-ignoring overlay competes for hit testing. Fix: move the controls to `safeAreaBar` and give the actual buttons explicit frames/content shapes [Task 2]
- Symptom: `.clearTopDarkBottom` treats `0.85` like `0.15`. Cause: `1 - offset` was applied unconditionally. Fix: invert only the direction whose coordinate system needs it [Task 3]
- The new onboarding/auth changes were not built or device-tested. For a targeted commit, a hook that runs `git add .` can include unrelated work: inspect hooks and `git show --name-only`; stage exact paths and keep unrelated modifications unstaged. [Task 6]

# Task Group: Timetable and pmstt custom human-readable share aliases

scope: implement and validate canonical timetable share aliases across the iOS client, Messages extension, and sibling pmstt server while preserving UUID links and identity/storage compatibility
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=use the alias/UUID compatibility and validation patterns for comparable sharing features, but recheck current routes, migrations, capability policy, and manual UI coverage in the active checkouts



## Task 3: Synchronize alias cache and restore public `/share` resolution, success but runtime unverified

### rollout_summary_files

- rollout_summaries/2026-07-26T07-08-05-GQTX-timetable_auth_sharing_admin_ui_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/26/rollout-2026-07-26T15-08-05-019f9d40-9ca7-7981-89a3-bce65b53257d.jsonl, updated_at=2026-07-26T08:32:08+00:00, thread_id=019f9d40-9ca7-7981-89a3-bce65b53257d, client/server commits 173a105 and e398bc4; no build/deploy/Safari verification)

### keywords

- fetchCurrentAlias, GET /v1/timetables/owner/share-alias, PUT, DELETE, ownerTimetableShareAlias, ShareSelectionSheet, TimetableShareURL.ownerURL, /share/:locator, AuthoritativeTimetableResolver.resolvePublic, e398bc4, 173a105

## User preferences

- when UUID fallback, stale defaults, and Safari “not found” appeared together -> verify the whole alias contract rather than only the editor: server authority, GET hydration, observed cache/UI state, canonical URL, and public route [Task 3]

## Reusable knowledge

- `fetchCurrentAlias()` is GET-only; PUT/DELETE mutate. Alias storage in `TimetableShareAlias` is authoritative while `@Default(.ownerTimetableShareAlias)` is cache/fallback. `ShareSelectionSheet` hydrates on appearance and observes the Default so `TimetableShareURL.ownerURL` updates from UUID to alias. Current source restores root public `/share/:locator`, resolving UUID/alias through `AuthoritativeTimetableResolver.resolvePublic`, while authenticated `/api/v1/shared-timetables/:locator` remains under `api`. Received-import storage remains UUID-based through `ReceivedTimetableImport.timetableID`; aliases are alternate public locators and server validation/uniqueness remains authoritative. [Task 3]

## Failures and how to do differently

- No build, deployment, server restart, or Safari runtime check was performed after restoring `/share/:locator`; do not claim public resolution until logs show a successful `/share/<alias>` request. [Task 3]





## User preferences

- when the user said “clicking any widget takes the user to the timetable tab” and “make the tab selection an enum, no approuter for now” -> prefer enum-backed selection state over introducing an app router for this navigation case [Task 3]

## Reusable knowledge

- `Main/Tabs/ContentView.swift` is the key place for enum-backed selection logic, and `timetable://` is the widget deep-link scheme that lands on the timetable tab while clearing old selected-slot state [Task 3]

## Failures and how to do differently


# Task Group: Timetable owner Wallet-pass remote updates

scope: owner timetable edits/visibility changes that must refresh the owner Wallet pass through the existing pmstt revision and APNs path
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=check current Wallet routes and pass-record schema before reuse

## Task 1: Owner timetable edits and visibility changes now bump the owner Wallet pass revision and send APNs updates, success

### rollout_summary_files

- rollout_summaries/2026-07-11T03-58-39-i1Ml-timetable_wallet_onboarding_defaults_reset.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/11/rollout-2026-07-11T11-58-39-019f4f53-c9b6-7ca2-babd-ad720bb4a8f9.jsonl, updated_at=2026-07-11T12:13:02+00:00, thread_id=019f4f53-c9b6-7ca2-babd-ad720bb4a8f9, owner-pass remote-update path was audited and then wired into the existing Wallet push machinery)

### keywords

- OwnerTimetableController, WalletPushService, WalletWebServiceController, AuthoredTimetableController, selfPassSerialNumber, PassRecord.revision, updateVisibility, ContiguousBytes

## User preferences

- when the user asked “can you check whether the server has the capability to remotely update wallet passes when its owner updates the timetable?” -> audit the actual owner-update path before promising behavior or starting implementation [Task 1]
- when the user then said “alright go ahead and implement everything” -> once the contract gap is proven, apply the missing owner-sync fix directly instead of staying in audit mode [Task 1]

## Reusable knowledge

- `WalletWebServiceController` already exposes the full Wallet registration/change-fetch/update-pass surface, and `AuthoredTimetableController` already had the correct revision-bump plus `WalletPushService.sendUpdate(...)` pattern to mirror for owner timetables [Task 1]
- The owner pass serial lives on `User.selfPassSerialNumber`; when owner timetable content or visibility changes, update the corresponding `PassRecord.revision`, clear deletion state if needed, and send the Wallet APNs update for that serial [Task 1]
- `WalletPushService` is intentionally non-fatal for timetable writes when registrations or APNs config are absent, so owner timetable saves should not fail just because the push path cannot deliver [Task 1]

## Failures and how to do differently
- Symptom: an owner’s Wallet pass never refreshes after owner timetable edits or visibility flips even though authored passes do. Cause: the owner path updates the timetable row but never bumps `PassRecord.revision` or calls `WalletPushService.sendUpdate(...)`. Fix: mirror the existing authored-pass revision/push flow in `OwnerTimetableController` using `selfPassSerialNumber` [Task 1]
- Symptom: release-build validation fails on `type 'SHA512256Digest' does not conform to protocol 'ContiguousBytes'` while validating an owner-pass patch. Cause: the checked-out `swift-crypto` package/SDK combination is mismatched, not the owner-pass source change. Fix: isolate the unrelated dependency/toolchain issue and do not attribute it to the Wallet update patch [Task 1]

# Task Group: Timetable watchOS auth/provisioning, device metadata/statistics, shared status badge parity, and verification workflow

scope: watch auth contract decisions, paired-iPhone watch-session provisioning, device-runtime metadata and Devices charts, phone-to-watch auth-state sync, watch-specific status badge rendering, and the accepted verification path for Timetable plus sibling pmstt support
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=safe for future Timetable watchOS auth, watch badge, and mixed watch/app/server verification work, but treat exact watch geometry, current `PLAN.md` wording, and current build-target list as checkout-specific



## Task 2: Shared iPhone/macOS badge contract was preserved while watch badge became a proportional `IrregularGradient` variant, success

### rollout_summary_files

- rollout_summaries/2026-07-06T02-22-56-HacQ-watch_badge_and_signin_refactor_with_shared_overlay_correcti.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/06/rollout-2026-07-06T10-22-56-019f353c-5e7a-70a3-ac5e-2cec1e8eeb0c.jsonl, updated_at=2026-07-06T03:13:06+00:00, thread_id=019f353c-5e7a-70a3-ac5e-2cec1e8eeb0c, watch renderer was rebuilt without changing the shared iPhone/macOS overlay)

### keywords

- WatchStatusBadgeOverlay, StatusBadgeManager, StatusBadgeOverlay, IrregularGradient, ColorfulX, 250x48, drag dismissal, debug badge buttons, widget reload

## Task 3: Watch, Timetable, and Watch Widget builds plus pmstt release build closed the accepted verification loop, success

### rollout_summary_files

- rollout_summaries/2026-07-06T02-22-56-HacQ-watch_badge_and_signin_refactor_with_shared_overlay_correcti.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/06/rollout-2026-07-06T10-22-56-019f353c-5e7a-70a3-ac5e-2cec1e8eeb0c.jsonl, updated_at=2026-07-06T03:13:06+00:00, thread_id=019f353c-5e7a-70a3-ac5e-2cec1e8eeb0c, user rejected `swift test` and accepted Xcode MCP plus pmstt release build)

### keywords

- Xcode MCP, Watch, Timetable, Watch Widget, swift build -c release, git diff --check, NEVER USE SWIFT TEST, production for the server

## Task 4: Defer the authenticated Watch root until paired-iPhone bootstrap completes, partial

### rollout_summary_files

- rollout_summaries/2026-07-25T11-06-07-Q5UF-watch_signin_cycle_and_messages_swiftui_migration.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/25/rollout-2026-07-25T19-06-08-019f98f4-30f3-7ff1-bd4e-0143deafa2ed.jsonl, updated_at=2026-07-25T11:21:01+00:00, thread_id=019f98f4-30f3-7ff1-bd4e-0143deafa2ed, committed 32e6ab8; source/diff validation only)

### keywords

- AttributeGraph: cycle detected, SessionStore.apply(_:bootstrap:), WatchAccountBootstrapService.bootstrap(), WatchSessionRootView, WatchTimetablesTabView, Defaults-driven TabView, 32e6ab8

## Task 5: Preserve Watch sessions while separating device-runtime metadata from APNs registration, partial

### rollout_summary_files

- rollout_summaries/2026-08-09T11-56-33-jkge-watch_auth_device_metadata_administration_statistics.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/09/rollout-2026-08-09T19-56-33-019fe661-bec6-7002-a363-39e2f6e19a26.jsonl, updated_at=2026-08-09T14:06:01+00:00, thread_id=019fe661-bec6-7002-a363-39e2f6e19a26, source/diff validation only)

### keywords

- WatchProvisioningService, SessionStore, PhoneWatchSyncBridge, DeviceSynchronizationService, /v1/auth/watch-session, /v1/devices/current/synchronize, /v1/devices/current, UserDevice, os_major_version, is_debug, is_beta, 67c08c8, 9779bd4, 8ca9b0f

## Task 6: Add Devices administration navigation and OS/build statistics, partial

### rollout_summary_files

- rollout_summaries/2026-08-09T11-56-33-jkge-watch_auth_device_metadata_administration_statistics.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/09/rollout-2026-08-09T19-56-33-019fe661-bec6-7002-a363-39e2f6e19a26.jsonl, updated_at=2026-08-09T14:06:01+00:00, thread_id=019fe661-bec6-7002-a363-39e2f6e19a26, compile follow-ups fixed; no build/tests run)

### keywords

- AdministrationDeviceStatisticsView, AdministrationController, LocationStatusDTOs, Swift Charts, SectorMark, DeviceOSVersionKey, Dictionary(grouping:), debug beta release, counts.11, generic parameter 'ElementOfResult' could not be inferred, flatMap

## Task 7: Show friend arrival/departure timestamp beneath the status capsule, partial

### rollout_summary_files

- rollout_summaries/2026-08-09T11-56-33-jkge-watch_auth_device_metadata_administration_statistics.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/09/rollout-2026-08-09T19-56-33-019fe661-bec6-7002-a363-39e2f6e19a26.jsonl, updated_at=2026-08-09T14:06:01+00:00, thread_id=019fe661-bec6-7002-a363-39e2f6e19a26, runtime appearance unverified)

### keywords

- FriendStatusCard, LocationStatusItem.updatedAt, Arrived:, Left:, secondary, trailing

## Task 8: Separate Debug/TestFlight/App Store channel metadata from OS-beta statistics, partial

### rollout_summary_files

- rollout_summaries/2026-08-10T06-40-13-TQJP-app_channel_badge_os_beta_statistics.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/08/10/rollout-2026-08-10T14-40-13-019fea66-7f98-7e80-9096-2142411657c1.jsonl, updated_at=2026-08-10T07:12:39+00:00, thread_id=019fea66-7f98-7e80-9096-2142411657c1, source/diff checks only; migration/runtime behavior unverified)

### keywords

- isTestFlight, isOSBeta, is_beta, is_os_beta, AddUserDeviceOSBetaFlag, DeviceSynchronizationService, AccountDTOs, LocationStatusDTOs, AdministrationDeviceStatisticsView, UserDevice, 4d26b6a, 403f8dc

## User preferences

- when the user asked whether the watch badge had actually copied the iOS overlay and called the result “insanely ugly” -> start watch badge changes from the existing iPhone/macOS overlay structure, then adapt proportionally for watch sizing [Task 2]
- when the user said “use IrregularGradient instead of colourful view” and “that bottom edge line effect and background should otherwise still exist” -> on watchOS, keep the existing lower-edge/background treatment and only swap the loading fill to `IrregularGradient` [Task 2]
- when the user asked “why did you change the iphone status badge” -> keep watch-only UI changes platform-scoped and leave the iPhone/macOS overlay untouched unless the user explicitly widens scope [Task 2]
- when the user said “make the watchos text a bit bigger bro” and later “ah yse but remove the manual dismissing” -> bias watch badge text slightly larger for readability and default watch dismissal to manager-driven expiry unless the user explicitly wants drag dismissal [Task 2]
- when the user said “NEVER USE SWIFT TEST OR SWIFT BUILD FOR DEBUG ITS ALWAYS PRODUCTION FOR THE SERVER AND ALWAYS USE XCODE MCP ANYWAY” -> default this watch/app/server verification pattern to Xcode MCP for app/watch targets and `swift build -c release` for pmstt, not debug shell builds or casual `swift test` [Task 3]
- when the user reported it “reliably happens when i sign in with apple watch” -> prioritize reproducing and validating the runtime watch sign-in transition, not merely explaining framework diagnostics. [Task 4]
- The user reported daily Watch sign-outs and asked not to delete tokens unless necessary -> preserve cached credentials and recover through the paired iPhone; do not force sign-in just to collect metadata. [Task 5]
- The user wants Devices as its own navigation link with charts and disclosure groups; denominator is users with one or more assessments, and device builds must be mutually exclusive debug, beta, and release categories. [Task 6]
- For friend detail, show trailing secondary text beneath the capsule, with no background: `Left: [time]` or arrival equivalent. [Task 7]
- The user said OS charts should not show the app’s Debug/Release state; identify OS beta from a final letter in the OS build number -> keep app installation channel and OS beta as independent fields and chart concepts. [Task 8]
- The user requested “rename build to TestFlight” and accurate TestFlight reporting -> use Debug, TestFlight, and App Store labels rather than generic Beta/Release app-build labels. [Task 8]

## Reusable knowledge

- The shared badge queue/priority logic remains in `App Shared/StatusBadge/StatusBadgeManager.swift`; watchOS should reuse that manager and the same badge view model rather than inventing a watch-only queue [Task 2]
- The iPhone/macOS renderer remains `Main/Views/StatusBadge/StatusBadgeOverlay.swift` and uses `ColorfulX`; the watch renderer is `Watch/WatchStatusBadgeOverlay.swift` and is the only place that should use `IrregularGradient` after this correction [Task 2]
- Watch badge geometry is derived from a single `250x48` reference so fonts, strokes, spacing, and indicators scale proportionally instead of being hand-tuned independently [Task 2]
- Watch developer badge testing lives in `Watch/WatchSettingsView.swift` and includes progress, success, info, error, warning, progress+gauge, and widget reload actions [Task 2]
- Validation that passed in this workflow: Xcode MCP builds for Watch, Timetable, and Watch Widget; `swift build -c release` in sibling `pmstt`; `git diff --check` clean after the final patch set [Task 3]
- `SessionStore.apply(_:bootstrap:)` must finish `WatchAccountBootstrapService.bootstrap()` before setting `state = .authenticated(profile)` on watchOS. The authenticated root mounts nested Defaults-driven `TabView`s, and switching it while bootstrap writes timetable/settings/calendar/received-timetable Defaults caused the observed `AttributeGraph: cycle detected` loop. Other platforms retain their existing order. [Task 4]
- Watch provisioning remains parent-bound to the iOS session through `/v1/auth/watch-session`; WatchConnectivity carries auth/provisioning, while runtime metadata is synchronized separately to `/v1/devices/current/synchronize` and APNs registration remains `/v1/devices/current`. [Task 5]
- `DeviceSynchronizationService` records OS major/minor plus debug/beta fields; sign-out removes device metadata, while the migration removes legacy device rows without deleting valid session tokens. [Task 5]
- Statistics DTOs are `App Shared/Networking/LocationStatusDTOs.swift` and `Sources/pmstt/DTOs/LocationStatusDTOs.swift`; the UI is `AdministrationDeviceStatisticsView.swift` and server aggregation lives in `AdministrationController.swift`. Use explicitly typed `[DeviceOSVersionKey]` before `Dictionary(grouping:)`. [Task 6]
- `FriendStatusCard.swift` can derive the timestamp directly from `LocationStatusItem.updatedAt`; no server contract change is needed. [Task 7]
- `DeviceSynchronizationService` and its DTOs now send `isTestFlight` and `isOSBeta` separately. `AdministrationDeviceStatisticsView` uses `isOSBeta` for minor-version and per-device-type labels/icons; server model, DTOs, controllers, migration, and integration-test fixtures were changed in tandem. [Task 8]
- The new migration is `Sources/pmstt/Migrations/AddUserDeviceOSBetaFlag.swift`. `UserDevice.isTestFlight` retains `@Field(key: "is_beta")` while `isOSBeta` adds `is_os_beta`; treat the first mapping as a backward-compatibility hypothesis that needs database/migration validation before release. [Task 8]
- Related skill: skills/timetable-change-verify-loop/SKILL.md [Task 3]

## Failures and how to do differently

- Symptom: a watch badge iteration is rejected as ugly or off-contract. Cause: the watch renderer diverged from the existing iPhone/macOS overlay, or the shared overlay was edited by accident. Fix: preserve the shared overlay unchanged and copy its structure proportionally into the watch renderer first [Task 2]
- Symptom: watch badge behavior keeps oscillating around dismissal. Cause: manual dismissal was assumed instead of requested. Fix: default watch badges to automatic expiry and only add swipe dismissal if the user explicitly asks for it [Task 2]
- Symptom: a watch overlay refactor hits a contextual-type SwiftUI compiler error around a `switch` plus modifier chain. Cause: a modifier such as `.allowsHitTesting(false)` was applied to a bare `switch` result. Fix: wrap the branch in a `Group` or another view container first [Task 2]
- Symptom: verification wastes time or gets corrected before the result matters. Cause: `swift test` or another debug-style server validation path was started for a watch/badge task. Fix: use Xcode MCP for app/watch schemes and `swift build -c release` for pmstt unless the task explicitly needs a different gate [Task 3]
- Symptom: repeated `AttributeGraph: cycle detected` follows successful owner/settings/calendar/received-timetable requests during watch sign-in. Cause: `.authenticated` mounts the watch hierarchy before bootstrap stabilizes its Defaults-driven pages. Fix: bootstrap before the authenticated state transition, then verify a real Watch sign-in and inspect AttributeGraph logs; debug-dylib/CoreUI/CFPreferences/`NSMapGet` noise was not established as root cause. [Task 4]
- Do not report daily Watch sign-out recovery, device synchronization, charts, or friend timestamp appearance as fixed without build/device checks; this rollout had no builds/tests. SwiftFormat hooks can add unrelated files, so inspect staged paths and restore hook-generated drift. [Task 5][Task 6][Task 7]
- Symptom: `generic parameter 'ElementOfResult' could not be inferred`. Cause: `compactMap`/`Dictionary(grouping:)` lacks an intermediate element type. Fix: construct `[DeviceOSVersionKey]` explicitly. Symptom: `value of type 'Int' has no member 'flatMap'`. Cause: tuple indexes drifted after release counts were inserted; replace positional tuples with named aggregates where possible. [Task 6]
- Symptom: channel/OS-beta changes appear source-clean but fail after deployment or misclassify historical metadata. Cause: `isTestFlight` still uses legacy `is_beta` while new OS status uses `is_os_beta`, and no build, integration tests, or migration validation ran. Fix: validate column preservation/migration behavior and run the coordinated client/server checks before release. [Task 8]
- Symptom: cross-repository stale-reference searches report missing paths. Cause: the command ran from the wrong repo root. Fix: rerun repository-specific searches from the Timetable and pmstt roots respectively. Preserve unrelated hook-formatted migrations and `Special/Localizable.xcstrings`; do not reset them blindly. [Task 8]

# Task Group: Timetable + pmstt Live Activities implementation, widget hardening, reconcile flow, and verification loop

scope: Timetable and sibling pmstt Live Activity work covering ActivityKit presentation, widget rendering limits, token lifecycle, re-enable/reconcile behavior, server APNs/scheduler persistence, and the validation loop that closed with app builds plus pmstt tests/release build
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=safe for future Timetable/pmstt Live Activity, ActivityKit, scheduler, and APNs payload work, but treat exact Xcode window ids, schedule times, routes, and commit hashes as checkout-specific and time-specific

## Task 1: Live Activity disappearing symptom isolated to local widget/render behavior, success

### rollout_summary_files

- rollout_summaries/2026-07-05T01-41-47-vzI6-timetable_live_activity_widget_and_reconcile_flow.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/05/rollout-2026-07-05T09-41-47-019f2ff0-5722-79f2-8bb2-794c191bf602.jsonl, updated_at=2026-07-05T10:32:25+00:00, thread_id=019f2ff0-5722-79f2-8bb2-794c191bf602, local debug harness proved the early disappearance was not a backend-only issue)

### keywords

- LiveActivityDebugView, ActivityKit, disappearing after 5 seconds, End Activity, SchoolDayLiveActivityWidget, nah i havent hooked up the server at all

## Task 2: Widget hierarchy simplified and native rendering restored for Lock Screen and Dynamic Island, success

### rollout_summary_files

- rollout_summaries/2026-07-05T01-41-47-vzI6-timetable_live_activity_widget_and_reconcile_flow.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/05/rollout-2026-07-05T09-41-47-019f2ff0-5722-79f2-8bb2-794c191bf602.jsonl, updated_at=2026-07-05T10:32:25+00:00, thread_id=019f2ff0-5722-79f2-8bb2-794c191bf602, heavy/custom subtrees removed and native primitives rendered reliably)
- rollout_summaries/2026-07-03T13-32-24-IQYM-live_activities_end_to_end_implementation_and_verification.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/03/rollout-2026-07-03T21-32-24-019f282e-33bb-7381-b61a-00ff089056b8.jsonl, updated_at=2026-07-03T14:11:31+00:00, thread_id=019f282e-33bb-7381-b61a-00ff089056b8, shared ActivityKit contract and initial widget surfaces shipped)

### keywords

- Dynamic Island, Lock Screen, WidgetKit, SchoolDayActivityAttributes, SchoolDayLiveActivityWidget, Text(endDate, style: .timer), ProgressView(timerInterval:), IrregularGradient, Current Subject

## Task 3: Minimal/watch presentation and timer-width behavior stabilized, success

### rollout_summary_files

- rollout_summaries/2026-07-05T01-41-47-vzI6-timetable_live_activity_widget_and_reconcile_flow.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/05/rollout-2026-07-05T09-41-47-019f2ff0-5722-79f2-8bb2-794c191bf602.jsonl, updated_at=2026-07-05T10:32:25+00:00, thread_id=019f2ff0-5722-79f2-8bb2-794c191bf602, minimal region changed to circular progress and watch layout/fonts were rebuilt)

### keywords

- minimal Dynamic Island, circular ProgressView, Text(endDate, style: .timer), .font(.system), 10:00 transition, width slot, watch layout, bottom aligned timer

## Task 4: Client token observation and re-enable reconcile flow hardened, success

### rollout_summary_files

- rollout_summaries/2026-07-05T01-41-47-vzI6-timetable_live_activity_widget_and_reconcile_flow.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/05/rollout-2026-07-05T09-41-47-019f2ff0-5722-79f2-8bb2-794c191bf602.jsonl, updated_at=2026-07-05T10:32:25+00:00, thread_id=019f2ff0-5722-79f2-8bb2-794c191bf602, activityUpdates observation and current-activity reconcile route added)
- rollout_summaries/2026-07-03T13-32-24-IQYM-live_activities_end_to_end_implementation_and_verification.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/03/rollout-2026-07-03T21-32-24-019f282e-33bb-7381-b61a-00ff089056b8.jsonl, updated_at=2026-07-03T14:11:31+00:00, thread_id=019f282e-33bb-7381-b61a-00ff089056b8, initial push-to-start and update-token upload/removal flow added)

### keywords

- LiveActivityRegistrationService, activityUpdates, pushToStartTokenUpdates, pushTokenUpdates, reconcile, POST /v1/live-activities/current/reconcile, liveActivitiesEnabled, Defaults[.installationID]

## Task 5: pmstt Live Activity API, persistence, APNs helpers, scheduler, and semantic contract implemented end-to-end, success

### rollout_summary_files

- rollout_summaries/2026-07-03T13-32-24-IQYM-live_activities_end_to_end_implementation_and_verification.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/03/rollout-2026-07-03T21-32-24-019f282e-33bb-7381-b61a-00ff089056b8.jsonl, updated_at=2026-07-03T14:11:31+00:00, thread_id=019f282e-33bb-7381-b61a-00ff089056b8, obsolete helpers deleted and typed runtime/services replaced them)

### keywords

- LiveActivityAPNSService, SchoolDayActivityProjector, SchoolDayActivityScheduler, SchoolDayLiveActivity, SchoolDayLiveActivityTransition, transition claim, APNSConfig, makeJWT, APNSClient, windowtab3

## Task 6: pmstt Live Activity tests and final verification gates completed without touching unrelated pmstt settings files, success

### rollout_summary_files

- rollout_summaries/2026-07-03T13-32-24-IQYM-live_activities_end_to_end_implementation_and_verification.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/03/rollout-2026-07-03T21-32-24-019f282e-33bb-7381-b61a-00ff089056b8.jsonl, updated_at=2026-07-03T14:11:31+00:00, thread_id=019f282e-33bb-7381-b61a-00ff089056b8, regression tests plus app/server build gates all passed)

### keywords

- swift test, swift build -c release, SchoolDayActivityProjectorTests, LiveActivityPayloadTests, LiveActivityIdempotencyTests, holiday comparison, year month day, Widget, Watch, Watch Widget, atomic commits

## Task 8: Add short-day projection and explicit overdue Live Activity endings, partial

### rollout_summary_files

- rollout_summaries/2026-07-24T08-29-59-vPGu-timetable_cross_device_live_activity_notification_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/24/rollout-2026-07-24T16-29-59-019f933e-e01f-7661-a109-5e7c4fb7f9be.jsonl, updated_at=2026-07-24T11:28:26+00:00, thread_id=019f933e-e01f-7661-a109-5e7c4fb7f9be, source-level tests added but not run)

### keywords

- SchoolStateEngine, activePeriods(for:), schoolEnd(for:), Wednesday, Friday, 14:32, 15:30, Last Period, LiveActivityRegistrationService, event: end, immediate dismissal, SchoolDayActivityScheduler, 68a945d, 3bb411e

## User preferences

- when the server was not hooked up, the user said “nah i havent hooked up the server at all” -> isolate local widget/client behavior before blaming APNs/server [Task 1]
- when the user said the Live Activity should show “basically the exact same thing as the app intent for current subject” -> mirror Current Subject semantics instead of inventing a separate Live Activity contract [Task 2][Task 5]
- when the user asked to “optimise the views for apple watch and dynamic island” -> include watch-sized and Dynamic Island-specific layouts as first-class surfaces, not just the Lock Screen card [Task 2][Task 3]
- when the user said the expanded Dynamic Island was “onyl showing the symbol” and the minimal view was “showing kinda truncated text” -> prefer a smaller native layout that visibly renders over a more ambitious custom hierarchy that gets dropped [Task 2][Task 3]
- when the user asked to “change all of the fonts everywhere in this live activity widget to be .font.system” -> use explicit system font sizing by default in this widget [Task 3]
- when the user asked “does the device push this token?” and then “alright fix that” -> new activities should auto-upload update tokens and token rotations should be observed, not left to manual reconciliation [Task 4]
- when the user wanted re-enabling to “start the activity again by requesting something from the server or something” -> provide an explicit reconcile/start path for the disable -> enable cycle [Task 4]
- once the plan was accepted, the user wanted implementation rather than more discussion, and later said “continue, if there is stll work that needs to be done” -> move into concrete edits quickly, then keep the verification loop going until the remaining gates are green [Task 4][Task 6]
- when the user said “completely redo the live activity helpers” -> replace obsolete helper code instead of incrementally patching it when the architecture is already wrong [Task 5]
- when the user asked to preserve unrelated dirty pmstt settings changes -> do not touch unrelated modified files during server work [Task 5][Task 6]

## Reusable knowledge

- `LiveActivityDebugView.swift` is the local start/update/end harness for School Day Live Activity debugging, and the only explicit local end path was the debug “End Activity” action [Task 1]
- `Shared/Models/SchoolDayActivityAttributes.swift` is the shared ActivityKit contract: static `activityKey`, `schoolDate`, and a `ContentState` carrying phase, title, symbol, RGBA color, next text, start date, and end date [Task 2][Task 5]
- `SchoolDayLiveActivityWidget.swift` renders more reliably when it stays conservative: native `Text`, `Image`, `ProgressView`, simple stacks, and light modifiers; removing `IrregularGradient`, custom timer wrappers, and other heavy/custom subtrees resolved dropped content in Lock Screen and Dynamic Island surfaces [Task 2]
- `Text(timerInterval:countsDown:)`, `Text(endDate, style: .timer)`, and `ProgressView(timerInterval:countsDown:)` are the validated autonomous timer/progress primitives for this feature; they avoid app-driven refresh loops [Task 2][Task 3]
- For highly size-limited Timetable surfaces such as widgets, Live Activities, and the timetable grid, constrain Dynamic Type instead of letting semantic sizing expand unpredictably; the safe defaults here are `.dynamicTypeSize(.medium)` or explicit `.font(.system(size:..., design:...))` sizing [Task 3] [ad-hoc note]
- For a fixed-width timer slot, bounded `Text(timerInterval: start ... end, countsDown: true)` plus an explicit monospaced font design remains the constrained-surface default [Task 3] [ad-hoc note]; however, `SchoolDayLiveActivityWidget` had a source-history regression with that initializer, so use its known-good `Text(.currentDate, format: .timer(countingDownIn: ...))` path there. [Task 3]
- Minimal Dynamic Island is best treated as an icon/progress surface, not a stable text timer surface; the validated fallback here was circular `ProgressView(timerInterval:)` [Task 3]
- Reserve a fixed timer slot based on the widest expected string such as `00:00` and center the live timer inside it; this prevents the 10:00 -> 9:59 width flip from shifting sibling layout [Task 3]
- `LiveActivityRegistrationService` should observe `pushToStartTokenUpdates`, `activityUpdates`, and each activity’s `pushTokenUpdates` as async sequences from app lifecycle code, not as one-off reads, and `Defaults[.installationID]` is the device-scoped identifier reused for registration requests [Task 4]
- Re-enabling `liveActivitiesEnabled` needs a pending reconcile path after token registration succeeds; the client/server route added here is `POST /v1/live-activities/current/reconcile` and the server creates a fresh current-period activity instead of trying to reuse an ended record [Task 4]
- The client already had a generic `NetworkManager.send` path, so Live Activity token upload/removal and reconcile requests fit cleanly into the existing networking layer and into settings/sign-out/device lifecycle hooks [Task 4]
- pmstt already had `APNSConfig`, `makeJWT`, and `APNSClient`; the replacement Live Activity APNs service reused that infrastructure instead of creating a parallel auth stack [Task 5]
- The school-day scheduler is driven by Perth school time and exact transitions: `08:00`, `08:50`, `09:48`, `10:46`, `11:08`, `12:06`, `13:04`, `13:34`, `14:32`, `15:30` [Task 5]
- `SchoolStateEngine.activePeriods(for:)` excludes period 6 on Wednesday/Friday (day indexes 2/4), giving `schoolEnd(for:) = 14:32`; regular days retain 15:30. The short-day projection labels period 5 `Last Period` and suppresses period 6. [Task 8]
- A stale date alone never ends an ActivityKit activity. `LiveActivityRegistrationService.startObserving()` cleans up prior-date/past-dismissal activities; pmstt retries overdue endings on every scheduler tick including non-school days, sends APNs `event: end` to active update tokens with immediate dismissal, and marks the record ended only after success/permanent invalidation. [Task 8]
- Idempotency is handled with a dedicated transition-claim table keyed by live activity and transition, and the old helper files `startLiveActivity.swift` plus `get_save PushStartTokens.swift` were removed in favor of typed services/controllers/models [Task 5]
- Historical pmstt suites exist for live-activity projection semantics, APNs payload parity, and transition idempotency (`SchoolDayActivityProjectorTests`, `LiveActivityPayloadTests`, `LiveActivityIdempotencyTests`), but current repo preference is to avoid `swift test` unless the user explicitly asks for it [Task 6]
- Final validation for this task family included Timetable, Widget, Watch, and Watch Widget builds plus `swift build -c release` in pmstt; older rollouts also recorded `swift test`, but that is no longer a default-acceptable gate here [Task 6]
- The checked Xcode routing in these rollouts was `windowtab1` for Timetable and `windowtab3` for pmstt, so workspace inspection mattered before assuming the active server project [Task 5][Task 6]
- Related skill: skills/timetable-change-verify-loop/SKILL.md [Task 4][Task 5][Task 6]

## Failures and how to do differently

- Symptom: a Live Activity seems to quit after a few seconds before the server is even connected. Cause: app, widget, and backend behavior were mixed together too early. Fix: start with `LiveActivityDebugView.swift` and the widget render path before blaming APNs/server [Task 1]
- Symptom: expanded Dynamic Island only shows a symbol or Lock Screen drops subviews. Cause: the widget hierarchy is too heavy or uses unsupported custom subtrees. Fix: collapse back to native ActivityKit primitives and lightweight stacks first [Task 2]
- Symptom: a Live Activity view contract starts diverging from the app’s Current Subject behavior. Cause: a new presentation model is invented locally. Fix: project the same semantic state machine into `SchoolDayActivityAttributes.ContentState` instead of designing a separate contract [Task 2][Task 5]
- Symptom: minimal presentation timer text truncates or layout shifts at 10:00 -> 9:59. Cause: timer text width is being treated as stable. Fix: use circular progress in minimal surfaces and reserve a fixed-width slot for timer text where larger layouts need it [Task 3]
- Symptom: text-heavy widget, Live Activity, or timetable-grid layouts expand or truncate unpredictably across sizes. Cause: unconstrained Dynamic Type or proportional timer fonts in a surface with fixed geometry. Fix: clamp the surface with `.dynamicTypeSize(.medium)` or explicit `.font(.system(size:..., design:...))`, and switch timer text to a bounded monospaced slot when width stability matters [Task 3] [ad-hoc note]
- Symptom: token upload logic misses rotations or activities created while the app is already running. Cause: ActivityKit tokens were handled as capture-once values or only scanned during reconciliation. Fix: observe `activityUpdates` and per-activity token streams from app lifecycle code and reconcile sign-out/settings/device changes too [Task 4]
- Symptom: re-enabling Live Activities does not restart the current period. Cause: reconcile fires before tokens are ready or tries to reuse an ended activity. Fix: keep reconcile pending until registration succeeds, then create a fresh current activity via the current-period reconcile route [Task 4]
- Symptom: server rewrite stalls on compiler errors. Cause: missing imports or wrong method labels after the coordinator/controller refactor. Fix: inspect the exact diagnostics, add `Foundation` where needed, and align the call sites to the actual function signatures before changing design again [Task 5]
- Symptom: holiday filtering tests fail even though school-day logic looks right. Cause: raw `DateComponents` equality/set semantics did not normalize the comparison. Fix: compare year/month/day fields explicitly for holiday exclusion [Task 5][Task 6]
- Symptom: a lightweight behavior test target starts failing for migration/shutdown reasons. Cause: the test harness initialized more of the app stack than the assertion needed. Fix: create only the minimum schema/runtime needed for the focused behavior test [Task 6]
- Symptom: the run stops too early after one build passes. Cause: unfinished tests or sibling-target validation were left pending. Fix: continue through the remaining explicit gates, then stop once the green boundary is reached and the user’s requested dirty-file boundaries are still preserved [Task 4][Task 6]
- The short-day/end implementation and added tests were not built, run, or device/APNs-verified by explicit instruction; describe “reliable” termination as intended behavior until those checks pass. [Task 8]

# Task Group: Timetable onboarding flow, background animation, APNs/defaults lifecycle, startup reset, and verification

scope: Timetable onboarding work covering flow structure, feature-page composition, calendar import and APNs/account lifecycle steps, background coordination and view identity, performance caps, startup defaults reset, verification workflow, and debug-only navigation gating
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with occasional sibling pmstt defaults work; reuse_rule=safe for future Timetable onboarding UI/state work in this checkout, but treat exact page ids, animation timings, defaults keys, and debug gating details as checkout-specific

## Task 1: APNs readiness moved out of settings and into the broader account/device lifecycle, success

### rollout_summary_files

- rollout_summaries/2026-07-03T08-58-18-chEY-timetable_onboarding_apns_calendar_import_xcode_mcp_builds.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/03/rollout-2026-07-03T16-58-18-019f2733-401b-7910-91da-7b8cda98fc50.jsonl, updated_at=2026-07-03T11:27:56+00:00, thread_id=019f2733-401b-7910-91da-7b8cda98fc50, settings-based readiness was replaced by lifecycle-driven registration)

### keywords

- APNs readiness, AccountAndSyncSettingsView, NotificationRegistrationService, MobileAppDelegate, AccountBootstrapService, hasRegisteredAPNsToken, pendingAPNsToken, windowtab2

## Task 2: Onboarding flow rebuilt around horizontal paging, calendar import, and streamlined account setup, success

### rollout_summary_files

- rollout_summaries/2026-07-03T08-58-18-chEY-timetable_onboarding_apns_calendar_import_xcode_mcp_builds.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/03/rollout-2026-07-03T16-58-18-019f2733-401b-7910-91da-7b8cda98fc50.jsonl, updated_at=2026-07-03T11:27:56+00:00, thread_id=019f2733-401b-7910-91da-7b8cda98fc50, onboarding pages added and calendar import embedded)

### keywords

- horizontal ScrollView, calendar import, VerticalPageTabViewStyle, CalendarImportView, hasCompletedOnboarding, notificationsEnabled: true, AccountSettings.default




## Task 6: Requested onboarding feature pages replaced placeholder content and expanded the pager, success

### rollout_summary_files

- rollout_summaries/2026-07-11T03-58-39-i1Ml-timetable_wallet_onboarding_defaults_reset.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/11/rollout-2026-07-11T11-58-39-019f4f53-c9b6-7ca2-babd-ad720bb4a8f9.jsonl, updated_at=2026-07-11T12:13:02+00:00, thread_id=019f4f53-c9b6-7ca2-babd-ad720bb4a8f9, search/friends/overview/completion pages replaced placeholders and used existing assets)

### keywords

- SearchTutorial, FriendsTutorial, OnboardingOverview, OnboardingCompletion, onboarding/search.imageset, onboarding/friends.imageset, "monkey", AnyView

## Task 7: Onboarding performance audit confirmed existing caps and tightened remaining animation hotspots, success

### rollout_summary_files

- rollout_summaries/2026-07-11T03-58-39-i1Ml-timetable_wallet_onboarding_defaults_reset.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/11/rollout-2026-07-11T11-58-39-019f4f53-c9b6-7ca2-babd-ad720bb4a8f9.jsonl, updated_at=2026-07-11T12:13:02+00:00, thread_id=019f4f53-c9b6-7ca2-babd-ad720bb4a8f9, source audit added explicit 60 FPS and renderScale=1 bounds where they were still loose)

### keywords

- OnboardingBackground, TimetableTypesTutorial, AnimatedGradientDemo, frameLimit, renderScale, TimelineView(.animation(minimumInterval: 1.0 / 60.0)), LazyHStack

## Task 8: One-time destructive reset now clears stale shared defaults before first launch of this release, success

### rollout_summary_files

- rollout_summaries/2026-07-11T03-58-39-i1Ml-timetable_wallet_onboarding_defaults_reset.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/11/rollout-2026-07-11T11-58-39-019f4f53-c9b6-7ca2-babd-ad720bb4a8f9.jsonl, updated_at=2026-07-11T12:13:02+00:00, thread_id=019f4f53-c9b6-7ca2-babd-ad720bb4a8f9, blanket App Group wipe was chosen over migration for stale release-state defaults)

### keywords

- resetPreReleaseStateIfNeeded, resetMarker, currentResetVersion, TimetableApp.init(), SharedDefaultsStore.removeAll(), group.omeriadon.timetable, UserDefaults.standard

## User preferences

- when the user said “use a horizontal scrollview bro” -> use horizontal scroll-based paging for onboarding, not a vertical `TabView` [Task 2]
- when the user said “also dont show the 3 toggles and name thing” -> do not add extra account-preference/name UI unless the user re-requests it [Task 2]
- when the user said “+ make it import calendar” -> include the real calendar import flow in onboarding rather than only a permission prompt [Task 2]
- when the user said “also add the onboarding pages i asked you to” -> treat already-requested feature pages as part of the onboarding contract, not optional follow-up polish [Task 6]
- when the user asked “did you also comb through the onbaording views and fix any potential performance problems? and cap the framerate to 60 and renderscale to 1?” -> answer onboarding performance questions with an explicit audit and exact cap locations, not a generic reassurance [Task 7]
- when the user said the old Defaults were “going to be fucked as shit” and “cant be bothered doing any migration,” then clarified “so just make it clear everything” -> when stale pre-release App Group state is the problem and the user accepts the tradeoff, prefer a one-time blanket reset over speculative migration logic [Task 8]

## Reusable knowledge

- Earlier settings-based APNs/device registration caused lifecycle coupling; the durable fix was to move readiness and registration behavior out of settings UI and into the account/device lifecycle [Task 1]
- `Shared/Defaults.swift` now includes `hasCompletedOnboarding`, `hasRegisteredAPNsToken`, and `pendingAPNsToken` for onboarding/APNs state [Task 1][Task 2]
- `VerticalPageTabViewStyle` was unavailable for iOS in the inspected SDK, so the onboarding pager was implemented with a horizontal `ScrollView` and button-only navigation [Task 2]
- `Main/Views/Calendar/CalendarImportView.swift` was adapted to be embeddable by adding a completion callback and retry path because the preexisting importer was sheet-coupled and self-dismissing [Task 2]
- `AccountSettings.default` and the corresponding pmstt defaults were changed to `notificationsEnabled: true` during this onboarding/account-flow redesign [Task 2]
- `OnboardingView` already had room for more pages, and `OnboardingPage` stores `AnyView` content, so feature walkthrough pages such as Search, Friends, Overview, and Completion can be added as separate small `View` types without changing the pager model [Task 6]
- The existing onboarding asset catalog already included `onboarding/search`, `onboarding/friends`, `onboarding/widget`, `onboarding/shareButton`, `onboarding/nextClass`, and `onboarding/broadcast`, so new onboarding pages should check existing assets before inventing new ones [Task 6]
- `OnboardingBackground.swift` already bounded `ColorfulView` with `frameLimit: .constant(60)` and `renderScale: .constant(1)`; the remaining hotspot in this pass was `TimelineView` inside `TimetableTypesTutorial`, which now uses `minimumInterval: 1.0 / 60.0` [Task 7]
- `AnimatedGradientDemo` also needs immutable `frameLimit: .constant(60)` and `renderScale: .constant(1)` bindings so the onboarding demo surfaces match the rest of the capped background behavior [Task 7]
- `SharedDefaultsStore.removeAll()` already existed for sign-out, but the one-time pre-release wipe needed a separate versioned `resetPreReleaseStateIfNeeded()` path with the marker stored outside the cleared App Group suite so the reset does not repeat [Task 8]
- `TimetableApp.init()` is the earliest practical hook for the one-time reset before the normal startup flow reconstructs onboarding, APNs, Wallet, and sync state [Task 8]

## Failures and how to do differently

- Symptom: notification readiness work keeps dragging settings UI into lifecycle logic. Cause: APNs/device registration is being treated as a local toggle problem. Fix: move readiness to account/device lifecycle services instead of keeping it in settings [Task 1]
- Symptom: onboarding/account work overbuilds extra profile/toggle pages before the user confirms them. Cause: early requirements were treated as stable. Fix: expect scope changes and keep extra account-edit UI out unless the user explicitly keeps it [Task 2]
- Symptom: onboarding placeholders linger as `"Here's an overview..."` or `"monkey"` even after the feature set is clearer. Cause: temporary copy stayed in the page list. Fix: replace placeholders with dedicated page views and reuse the existing onboarding asset set before adding new assets or copy [Task 6]
- Symptom: a performance answer overstates confidence. Cause: the code was not yet audited and runtime profiling did not happen. Fix: explicitly say when the first answer was only a feature edit, then do a source-level pass and report exact `frameLimit`, `renderScale`, and `TimelineView` caps that were inspected or changed [Task 7]
- Symptom: a one-time defaults wipe repeats every launch. Cause: the reset marker is stored in the same App Group suite that gets cleared. Fix: keep the marker outside the wiped suite, such as `UserDefaults.standard`, and version it [Task 8]
- Symptom: stale pre-release local state keeps leaking into onboarding/APNs/Wallet behavior. Cause: a migration path would be more complex than the remaining data is worth. Fix: if the user explicitly accepts destructive behavior, wipe the full `group.omeriadon.timetable` suite once on first launch and let normal startup rebuild the runtime state [Task 8]

# Task Group: Timetable app + pmstt APNs/sign-in, notification settings, sync-stall debugging, discovery, and deployment workflow

scope: mixed Timetable app plus sibling pmstt server work covering Sign in with Apple/APNs readiness and delivery behavior, notification-related settings flows, deployed env setup, sync-stage debugging, search/discovery rollout, and the accepted release/deploy loop
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=safe for future Timetable/pmstt auth, APNs, notification-setting, sync, discovery, and deployment work, but treat exact env vars, routes, remotes, signed entitlements, and deployed behavior as checkout-specific and time-specific

## Task 3: Independent broadcast notifications implemented across client and server, success

### rollout_summary_files

- rollout_summaries/2026-07-02T12-54-17-scVK-broadcast_notifications_client_server_implementation.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/pmstt, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/02/rollout-2026-07-02T20-54-17-019f22e4-f395-7290-a34f-6662f6206ebc.jsonl, updated_at=2026-07-02T22:15:44+00:00, thread_id=019f22e4-f395-7290-a34f-6662f6206ebc, separate broadcast toggle and developer endpoint shipped)

### keywords

- broadcast notifications, broadcastNotificationsEnabled, POST /v1/developer/broadcast-notification, subtitle, eligibleDeviceCount, deliveredDeviceCount, invalidatedDeviceCount, failedDeviceCount, best-effort delivery, Special Event Notifications

## Task 5: Sign in with Apple / APNs configuration and bootstrap behavior debugged, partial

### rollout_summary_files

- rollout_summaries/2026-07-01T12-45-08-A3b2-timetable_apns_signin_sync_debug_and_deploy.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/01/rollout-2026-07-01T20-45-08-019f1db6-3467-7ef0-a948-840802460ab8.jsonl, updated_at=2026-07-01T13:34:40+00:00, thread_id=019f1db6-3467-7ef0-a948-840802460ab8, code changes and deploy succeeded but runtime production-token issue remained signing-bound)

### keywords

- aps-environment, com.apple.developer.applesignin, production signing, TestFlight, get-task-allow, BadDeviceToken, SessionStore.apply, NotificationRegistrationService, TIMETABLE_APPLE_APPLICATION_IDENTIFIER

## Task 6: Owner timetable sync hang / timeout traced to server update path and fixed, success

### rollout_summary_files

- rollout_summaries/2026-07-01T12-45-08-A3b2-timetable_apns_signin_sync_debug_and_deploy.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/01/rollout-2026-07-01T20-45-08-019f1db6-3467-7ef0-a948-840802460ab8.jsonl, updated_at=2026-07-01T13:34:40+00:00, thread_id=019f1db6-3467-7ef0-a948-840802460ab8, server controller rewrite deployed and health-checked)

### keywords

- ServerSyncCoordinator, OwnerTimetableController, PUT /v1/timetables/owner, Profile, timeout, 25 seconds, revision checks, git push production, timetable.adonis.pt/health

## Task 8: Centralized sync, release validation, atomic commits, and production deployment completed, success

### rollout_summary_files

- rollout_summaries/2026-06-30T08-56-43-GaFn-timetable_global_search_sync_deploy_rollup.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/06/30/rollout-2026-06-30T16-56-43-019f17be-b942-7923-aeec-c885a8d1f0cd.jsonl, updated_at=2026-06-30T14:51:25+00:00, thread_id=019f17be-b942-7923-aeec-c885a8d1f0cd, client/server commits plus production restart verified)

### keywords

- swift build -c release, git push production, PM2 timetable-api, timetable.adonis.pt/health, atomic commits, Xcode visionOS churn, production remote

## Task 9: Global timetable discovery/search, authored management, and Wallet distribution implemented, success

### rollout_summary_files

- rollout_summaries/2026-06-30T08-56-43-GaFn-timetable_global_search_sync_deploy_rollup.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/06/30/rollout-2026-06-30T16-56-43-019f17be-b942-7923-aeec-c885a8d1f0cd.jsonl, updated_at=2026-06-30T14:51:25+00:00, thread_id=019f17be-b942-7923-aeec-c885a8d1f0cd, client/server feature set shipped and deployed)

### keywords

- FuzzyMatchingSwift, .searchable, global search, authored timetables, Wallet web service, StatusBadge, PASS_TYPE_IDENTIFIER, install count, hard delete

## Task 10: Signed-out auth handling and silent not-found status-badge behavior corrected, success

### rollout_summary_files

- rollout_summaries/2026-06-30T08-56-43-GaFn-timetable_global_search_sync_deploy_rollup.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/06/30/rollout-2026-06-30T16-56-43-019f17be-b942-7923-aeec-c885a8d1f0cd.jsonl, updated_at=2026-06-30T14:51:25+00:00, thread_id=019f17be-b942-7923-aeec-c885a8d1f0cd, shared networking and badge behavior cleanup)

### keywords

- NetworkError.authenticationRequired, NetworkError.suppressesStatusBadge, refresh token is missing, account-not-found, sign in to use, StatusBadgeManager, watch sync, reload widgets

## Task 14: Diagnose Apple auth route state and confirm full bootstrap after sign-in, partial

### rollout_summary_files

- rollout_summaries/2026-07-26T07-08-05-GQTX-timetable_auth_sharing_admin_ui_fixes.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/07/26/rollout-2026-07-26T15-08-05-019f9d40-9ca7-7981-89a3-bce65b53257d.jsonl, updated_at=2026-07-26T08:32:08+00:00, thread_id=019f9d40-9ca7-7981-89a3-bce65b53257d, routing diagnosis source/log validated; no deploy/restart/post-fix verification)

### keywords

- AuthController.register, emailAlreadyExists, 409, accountNotFound, 404, RouteNotFound.404, /api/v1/auth/login, /v1/auth/apple, SessionStore.apply, AccountBootstrapService.bootstrap, 8249a20, 0cf9e50

## User preferences

- when the user corrected the broadcast design with “no. the two are completely seperate.” -> keep broadcast notifications independent from the normal notifications toggle unless the user explicitly couples them later [Task 3]
- when the user said “dont set any development environments, its always production. yolo.” -> default Timetable APNs/server guidance to production-only configuration instead of introducing sandbox branching [Task 5]
- when the user said “dont add any tests, i will do all of the testing.” and later “dont do any uitests etc, i will do the testing. you just need to make sure both builds work.” -> in this notification/auth feature family, validate with builds and the requested manual testing boundary, not added tests [Task 3][Task 5]
- when the user said “once you update the server, use git push production” -> deploy pmstt server fixes through the production remote after validation [Task 5][Task 6][Task 8]
- when the user said “you will also need to make sure that signing will properly update current devices, cos rn it doesnt.” -> treat post-auth APNs re-registration/token refresh for already-installed devices as required behavior, not an optional follow-up [Task 5]
- when the user corrected validation with “you are always supposed to run swift build -c release not just swift build” -> default server validation to `swift build -c release` before shipping pmstt changes [Task 8]
- when the user said “commit changes and continue the next step of the plan. dont commit that yet.” -> commit only the finished behavior and do not pull the next pending step into that commit without explicit confirmation [Task 8]
- when the user said “no dont make your own search algorithm use the one i gave you” after attaching `seanoshea/FuzzyMatchingSwift` -> reuse that package instead of inventing a local matcher for timetable search/discovery work [Task 9]
- when the user said “there is no pagination. it shows everthing” and “use the .searchable modifier, obviously” -> default to unpaginated `.searchable` search UI unless they explicitly widen scope [Task 9]
- when the user said “make it a tab on the very right excluding the prominent tab” -> place Search as the far-right regular tab on iPhone [Task 9]
- when signed out and clicking a protected action, the user said “it tells me i need to sign in to use” -> protected actions should surface a direct sign-in-required badge/message instead of generic auth failures [Task 10]
- when the user said “the not found error is not actually an error dont send a status badge for that bro” -> 404/account-not-found should stay silent in normal flows [Task 10]
- when the user said “make the sync to watch use status badge, and same with reload widgets button” -> sync actions should use badge progress/success rather than alerts or banners [Task 10]
- when the user asked what duplicate-email signup and “not found” mean -> distinguish `emailAlreadyExists`/409 from later authenticated 404/account-lookup failures by tracing current request logs and server code [Task 14]

## Reusable knowledge

- `SessionStore.apply(... bootstrap: true)` is the right client bootstrap hook for auth side effects, including APNs re-registration for already-installed devices after sign-in/restore. [Task 5]
- `broadcastNotificationsEnabled` is JSON-backed on client and server, defaults to `true`, and should keep APNs registration active when either notification preference is enabled [Task 3]
- Broadcast delivery should be best-effort per device: query `UserDevice`, filter by the broadcast setting, include APNs `subtitle`, clear invalid tokens, and keep going after individual failures while summarizing counts in the response [Task 3]
- `pmstt` reads `TIMETABLE_APPLE_APPLICATION_IDENTIFIER` from PM2/process env in `configure.swift`; that env value controls Apple token audience verification on the server [Task 5]
- The server APNs senders use `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY_PATH`, and `APNS_BUNDLE_ID`; keep `.p8` keys and APNs secrets out of source and memory [Task 5]
- A successful client build does not prove production APNs compatibility; inspect the signed product entitlements with `codesign` when runtime behavior still disagrees with source config [Task 5]
- `ServerSyncCoordinator.syncEverything()` stages are `Profile`, `Timetable`, `Account settings`, `Received timetables`, `Authored timetables`, and the coordinator uses a 25-second per-stage timeout [Task 6]
- `OwnerTimetableController.updateOwnerTimetable` is the server route behind `PUT /v1/timetables/owner`; in this checkout it became reliable after a direct query/update path with revision checks replaced the stalling transaction block [Task 6]
- Server release validation command: `swift build -c release`, and the accepted deploy check is `git push production` followed by `curl -fsS https://timetable.adonis.pt/health` [Task 8]
- `pmstt` now includes global timetable discovery/search, timetable detail, authored management, and Wallet web-service plumbing tied to the current account/pass model [Task 9]
- `NetworkError.authenticationRequired` is the local fast-fail for protected endpoints when no access token exists, and `NetworkError.suppressesStatusBadge` keeps 404/account-not-found from becoming user-facing badge noise [Task 10]
- The current post-auth path is `SessionStore.apply(..., bootstrap: true)` -> configured `AccountBootstrapService.bootstrap()`, concurrently reconciling owner timetable, alias, account settings, received/created timetables, school calendar, and calendar events; do not add a second full-sync trigger without evidence. Current Timetable/5 logs send `POST /api/v1/auth/login`; retain `let api = app.grouped("api")`, keeping `/health` and AASA at root. [Task 14]

## Failures and how to do differently

- Symptom: a broadcast setting proposal is rejected immediately. Cause: it was implicitly coupled to `notificationsEnabled`. Fix: keep broadcast preferences fully independent unless the user explicitly asks for a master gate [Task 3]
- Symptom: source entitlements and production APNs code paths look correct, but runtime sends still fail with `BadDeviceToken`. Cause: the installed app is still development-signed (`aps-environment = development`, `get-task-allow = true`) even if the source file or Release build says otherwise. Fix: inspect the signed app entitlements with `codesign` and use distribution signing when production APNs validity matters [Task 5]
- Symptom: APNs debugging gets stuck on whether the key supports both environments. Cause: provider-key scope is being confused with device-token environment validity. Fix: treat those as separate layers and debug the signed app / token environment directly [Task 5]
- Symptom: sync-to-server “does nothing forever.” Cause: a stage-specific server request is stalled until the client timeout. Fix: trace the exact `ServerSyncCoordinator` stage, hit the backing endpoint directly, and inspect the corresponding server controller/logs before blaming the client UI [Task 6]
- Symptom: server validation passes locally but the user rejects the workflow. Cause: a debug build or generic `swift build` was used. Fix: run `swift build -c release` before shipping pmstt changes [Task 8]
- Symptom: Xcode validation causes unrelated project-file churn before commit. Cause: visionOS/platform auto-mutations during build. Fix: remove generated project-file changes before committing requested work [Task 8]
- Symptom: search/discovery work is pushed back immediately. Cause: the first pass overreached into pagination, popularity/download metrics, or soft-delete behavior the user explicitly rejected. Fix: collapse back to unpaginated `.searchable`, hard deletes, Wallet install-count semantics, and `FuzzyMatchingSwift` [Task 9]
- Symptom: protected actions show “refresh token is missing” when signed out. Cause: authenticated requests reached refresh logic with no access token. Fix: fail locally with `NetworkError.authenticationRequired` before refresh handling [Task 10]
- Symptom: not-found/account-not-found paths create noisy badges. Cause: 404 handling is treated like a visible error path. Fix: mark those cases with `NetworkError.suppressesStatusBadge` and keep them silent in normal flows [Task 10]
- Symptom: an Apple sign-in failure prompts a session-generation/race fix. Cause: stale logs or UI state were treated as current route evidence. Fix: inspect client version, current request path, server logs, and controller reachability first; the temporary route change `8249a20` and session fix were reverted once current evidence restored `/api`. [Task 14]


# Task Group: Timetable app + pmstt account settings, notifications, current-day highlight sync, and received timetable contracts

scope: implemented and corrected account settings scope, notification settings authorization/sync, current-day highlight persistence, received timetable projection sync, signed metadata preservation, and typed `SourceKind` handling across the Timetable app and sibling pmstt server
applies_to: cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable with sibling server work in /Users/omeriadon/Documents/Xcode_App_Library/pmstt; reuse_rule=safe for future Timetable/pmstt account-sync, notification, current-day-highlight, and received-timetable implementation work, but treat deployed route sets, DTOs, auth rules, and current field lists as checkout-specific and time-specific

## Task 1: Received timetable and name-override sync APIs implemented end-to-end, success

### rollout_summary_files

- rollout_summaries/2026-06-27T23-44-38-EJG1-received_timetable_sync_and_sourcekind_enum.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/06/28/rollout-2026-06-28T07-44-38-019f0b78-8fab-7a41-9e64-c86566be8be1.jsonl, updated_at=2026-06-28T11:06:41+00:00, thread_id=019f0b78-8fab-7a41-9e64-c86566be8be1, implemented and deployed)

### keywords

- pmstt, received timetables, received-name-overrides, AccountBootstrapService, WatchAccountBootstrapService, ReceivedTimetableSyncService, TimetablePassManager, swift build, git push production, Defaults projection, PM2 timetable-api

## Task 2: sourceKind enum migration with raw-string fallback, success

### rollout_summary_files

- rollout_summaries/2026-06-27T23-44-38-EJG1-received_timetable_sync_and_sourcekind_enum.md (cwd=/Users/omeriadon/Documents/Xcode_App_Library/Timetable, rollout_path=/Users/omeriadon/.codex/sessions/2026/06/28/rollout-2026-06-28T07-44-38-019f0b78-8fab-7a41-9e64-c86566be8be1.jsonl, updated_at=2026-06-28T11:06:41+00:00, thread_id=019f0b78-8fab-7a41-9e64-c86566be8be1, model-typing cleanup kept DB as text)

### keywords

- sourceKind, SourceKind.swift, ReceivedPassMirror, PassRecord, rawValue fallback, accountOwner default, PostgreSQL text column, DTOs.swift, typed Swift enum

## User preferences

- when a missing project API gap is identified and the contract is understood, the user replied “alright then implement them!” -> in this Timetable/pmstt workflow, move from gap analysis into implementation instead of extending discussion [Task 1]
- when requirements are unknown, the earlier instruction to “check with me for things you dont know about” still applies -> ask before inventing server URL or product decisions, then implement concretely once the contract is clear [Task 1]
- when the user asked “shouldnt soruceKind be an enum? dont bother making it interop into psql enums but do make it convert from : String rawValue with a default” -> prefer typed Swift domain models while keeping database storage simple unless the user explicitly asks for schema complexity [Task 2]

## Reusable knowledge

- `pmstt` accepted and deployed these received-sync routes: `GET /v1/timetables/received`, `PUT /v1/timetables/received`, `GET /v1/received-name-overrides`, `PUT /v1/received-name-overrides/:serialNumber`, and `DELETE /v1/received-name-overrides/:serialNumber` [Task 1]
- Received projection syncing is modeled as a full replacement endpoint plus a separate override-list endpoint, with transactional replacement, strict validation, and per-user ownership checks. [Task 1]
- Watch data flow uses credentials/session envelope only; timetable data itself is fetched from the server during bootstrap and stored back into Defaults so widgets can refresh without watch-UI changes [Task 1]
- Wallet projection upload is triggered from the client after reconciliation, using the current Defaults projection via `TimetablePassManager` [Task 1]
- A typed Swift enum can wrap a text-backed PostgreSQL column; `SourceKind: String, Codable, Sendable` kept DB storage as `TEXT` while models/DTOs exposed typed accessors, and unknown raw values should fall back to `.accountOwner` [Task 2]

## Failures and how to do differently

- Symptom: client/watch sync wiring assumes more received-timetable structure than the server currently exposes. Cause: the first pass modeled the payload too optimistically. Fix: verify the current server DTOs and endpoints before wiring client decoding or bootstrap flows [Task 1]
- Symptom: a type cleanup starts to look like a schema migration. Cause: wrapping raw strings in strongly typed Swift models touches many files. Fix: keep the DB schema unchanged and only add enum/raw-value wrappers unless the user explicitly asks for PostgreSQL enum complexity [Task 2]
