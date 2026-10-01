# Dispatch and worktree procedure

This file is an execution handoff for later implementation. The current request creates documentation only. Nothing in the commands below has been executed by the planning task.

## 1. Establish the baseline

The primary agent reads [the roadmap](README.md), the chosen packet, applicable global instructions at `~/.codex/AGENTS.md`, and the source entry points. These documents are task references, not repository-specific `AGENTS.md` files. Preserve the current Browser project restrictions.

Use a committed baseline containing the intended current source and the roadmap. A worktree does not inherit uncommitted files from the main checkout. If necessary, the user or an explicitly authorized preparation step checkpoints the current implementation first. Do not silently stash, reset, discard, or include unrelated work. Record the exact baseline commit in the dispatch message; no baseline hash is invented in this plan.

Task 00 establishes the baseline inventory/capability decisions. Each later task starts from a commit that already includes its prerequisites. The default integration base is the user's designated local integration branch. Preserve the existing branch conventions; `astra/roadmap/*` names only the new task branches.

## 2. Reserve ownership

One implementation agent receives one task branch and worktree. Worktrees isolate working copies, not behavior or merge conflicts. Two agents may run only when their write sets are disjoint and dependencies are merged. Read access can overlap.

| Shared file/boundary | Tasks that may need it | Rule |
| --- | --- | --- |
| `Models/Core/Browser.swift` | 01, 03, 04, 07–10, 15, 27, 29 | One active writer; later tasks start after prior changes merge |
| `Web/Navigation/BrowserController.swift` | 01, 02, 05, 06, 13, 16, 18, 20, 22, 24–27 including 24a | Same rule; ownership includes extensions/private declarations in this file |
| `Web/Navigation/BrowserWebsiteUI.swift` | 05, 13, 23 | Permission work before auth/upload changes; re-read merged prompt behavior |
| `Web/Navigation/BrowserWebSession.swift` | 01, 04, 18, 21, 30 | Session semantics are a prerequisite; reserve any new service wiring |
| `Storage/BrowserPersistence.swift` and persisted DTOs | 03, 07–10, 18, 28–30 | Schema changes serialized; new values have decoding defaults/migration cases |
| `Storage/BrowserDefaults.swift` | 05, 12, 14, 16, 18, 19, 21, 28–30 | Feature tasks own their keys while reserved; 28 reconciles final schema/UI |
| Settings views | 05, 12, 14, 18, 21, 22, 26, 28–30 | Prefer a feature-owned section/component; final navigation/layout wiring belongs to 28 |
| `App/AppDelegate.swift` | 01, 03, 08, 17, 24a, 25, 31–34 | Serialize edits; preserve responder/menu and termination ownership |
| Project/scheme/Info.plist/entitlements | 00, 23, 27, 31–33, test membership as needed | Primary reserves each change; use Xcode MCP; no simultaneous writers |
| Existing tests and fixture root files | All | Each task uses a unique test/fixture file; root harness edits are serialized |
| Roadmap contracts and capability decisions | 00 plus primary | Workers report deltas; primary owns shared roadmap updates |

Paths in the table are relative to `astra/` unless explicitly identified otherwise. Packet ownership names starting files; reserve any extra file before editing it. The primary can resolve routine ownership decisions without a new user question. An out-of-scope feature is reported, not implemented.

## 3. Create the task worktree

Run from the repository root. Replace `task_id` and `baseline_commit` with the dispatched packet and the recorded commit. Create worktrees just before dispatch, not all against the original baseline: later packets need earlier interfaces and migrations.

```sh
task_id='01-lifecycle'
baseline_commit='<recorded commit containing prerequisites>'
worktree_root='../astra-worktrees'

mkdir -p "$worktree_root"
git worktree add -b "astra/roadmap/$task_id" "$worktree_root/$task_id" "$baseline_commit"
```

For task 00 only, the baseline is the checkpoint prepared in step 1. Copy its task references into the dispatch context if the documentation has not yet been committed; do not pretend they exist in that worktree.

Start the agent with the worktree as its current directory. Tools that default to the original checkout must receive explicit worktree paths. Existing collaboration agents can share a filesystem; therefore the dispatch must name the absolute worktree path and every edit/check must target it.

## 4. Send this prompt with the packet

```text
Implement task <ID-slug> from docs/astra-roadmap/tasks/<ID-slug>.md.

Worktree: <absolute path>
Branch: astra/roadmap/<ID-slug>
Baseline commit: <exact commit>
Prerequisites: <merged packet IDs and commits, or recorded gate decisions>
Selected scope: <baseline features plus explicitly selected optional features>
Reserved write set: <packet files plus approved extra files>

Read docs/astra-roadmap/README.md and dispatch.md before editing.
You are not alone in the codebase. Preserve others' changes and re-read
prerequisite implementations. Work exclusively in the assigned worktree.
Trace the existing flow and reuse it. Implement only this packet.
Do not launch or operate Astra. Use source inspection and Xcode MCP
diagnostics/builds when compilation risk requires them. Never use xcodebuild.
Write the smallest meaningful runnable regression check for changed logic;
compile hosted checks and leave execution pending under the project restriction.
Use the existing SwiftUI style, accessible symbol labels, identifiers and sheets.

Do not push, merge, modify another worktree, create repository AGENTS.md files,
or perform unrelated cleanup. Resolve routine decisions within the packet.
For an unsupported public API, record the precise capability gate and preserve
a working fallback; do not replace it with private API or a pretend feature.

Return the bounded implementation, a packet-specific handoff report, changed
files, verification evidence, pending runtime cases, migrations and unresolved
issues. Leave integration and final reporting to the primary agent.
```

The primary Sol agent selects the work and reviews it. Use one `gpt-6-luna` implementation agent with medium reasoning. Use a second only for independently reserved work. These packets require behavior tracing; low reasoning is reserved for later mechanical changes. For a task requiring several implementation checkpoints, use the user's established commit style after inspecting it in the authorized Git workflow. Leave an isolated one-off edit uncommitted; the primary/user creates a checkpoint when it is part of the multi-step integration process. A handoff must state whether changes are committed.

When using the collaboration tool, set `model: "gpt-6-luna"`, `reasoning_effort: "medium"` and `fork_turns: "none"`, and include the complete dispatch context above. Do not select a fixed-model agent role that overrides the requested model. Pass the packet content if the branch does not yet contain the roadmap; otherwise provide its absolute worktree path.

## 5. Apply these implementation constraints

- Keep new Swift declarations and assignments on ordinary separate lines; copy local indentation and view patterns.
- Use `List` and sections, preserve backgrounds/pickers, and avoid `Form`.
- Buttons have a system symbol and accessibility label/identifier; icon-only controls use `labelStyle`. Cancel uses `Button(role: .cancel)`.
- Confirm controls use `role: .confirm` and `.glassProminent`. Small sheets use a fraction between 0.5 and 0.7, such as `.fraction(0.6)`, with one host namespace and unique matched source/zoom transition IDs. Apply platform availability correctly.
- WebKit callbacks and script bridges validate their origin/frame/document/session as applicable. Cancellation cannot become a saved refusal. Sensitive state never leaks into diagnostics, normal persistence or sync.
- Preserve existing storage until a migration succeeds. Make deletion, corrupt data and future-version handling explicit.
- Keep dependencies native/existing. Use Bun for any necessary JS/TS scripts. Do not run formatters or edit release/server behavior outside ownership.

## 6. Verify the correct worktree

Use Xcode MCP to open the assigned worktree's project. Record the workspace ID/path, scheme, destination, tool result and affected-file diagnostics. Confirm the workspace points to the task worktree before building. Serialize Xcode checks because scheme/destination changes can affect the shared IDE session. Close only task workspaces opened for the check; preserve the user's original workspace.

No full build for a small UI-only edit. Model, delegate, concurrency, project, entitlement or dependency changes normally require diagnostics and a relevant Xcode MCP build. Hosted tests remain unexecuted under the current source/build-only restriction. For package-only work, use the required `pipefail`/`xcsift` Swift command pipeline. For website fixture JS/TS checks use Bun; fixture/browser execution stays pending. Do not rewrite CI merely to fit local tool limitations.

## 7. Produce the handoff

Create `docs/astra-roadmap/handoffs/<ID-slug>.md` in the task worktree. This directory is created only when an actual task finishes. Include:

```text
Task / selected optional scope:
Branch / worktree / baseline commit:
Status: source complete | build verified | gated | blocked
Commit(s), or explicit uncommitted state:
Changed files and behavior:
Acceptance cases satisfied, with evidence:
Checks run, scheme/destination/workspace and results:
Checks written but not executed:
Pending runtime/hardware/provider cases:
Migration, compatibility and private-data impact:
Capability gates / unresolved issues:
Merge prerequisites / follow-up ownership:
```

A gate report is a valid result for an optional unsupported feature. Do not mark baseline work complete if its required behavior is missing. The primary reviews the report and source, checks ownership and data/security invariants, and records merge readiness. Wait for the implementation agent before reporting task completion.

## 8. User-controlled integration

The user merges later. Agents leave branches/worktrees intact. No push occurs. The integration reviewer takes the following sequence per branch:

1. Confirm its prerequisites and capability decisions are already integrated.
2. Review changed files, the packet and handoff. Account for any uncommitted files before attempting a merge.
3. Bring the task branch onto the current integration base using the user's chosen merge/rebase workflow. Resolve conflicts against both packets' acceptance criteria, not by taking one side wholesale.
4. Commit/checkpoint the task in the user's style if needed, then merge the reviewed task branch into the integration branch.
5. Perform the smallest relevant check on the integrated source; use Xcode MCP for required builds. Recheck shared-file behavior after conflict resolution.
6. Record the merged commit, then create dependent task worktrees from that new baseline.

Never merge a branch as “complete” solely because it compiles. Preserve pending runtime gates. Keep worktrees until the user accepts integration; cleanup is a separate action. Release publishing and server changes are outside this dispatch authorization.
