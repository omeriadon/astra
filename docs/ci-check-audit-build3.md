# Build 3 CI quality audit — 19 October 2026

## Standard for retaining checks

A passing check must demonstrate something observable: production Swift compiling
and executing in a regression fixture, production browser JavaScript running in a
fixture, a complete Debug/Release build, an inspected *built* app, or a real
external contract (project target graph, compiler safety settings, release rules).
The existence, location, text, exact statement order, timing constant, or spelling
of an implementation detail is not equivalent to working behaviour.

## Scope and changes

Reviewed Astra's **25 GitHub Actions workflows** and the scripts they invoke.
Removed **30 standalone jobs**, **25 brittle/source-only scripts** and three
workflows whose only activity was checking literal implementation text:

- `validate-persistence.yml`: eight structural assertions; actual sync and
  persistence Swift fixtures remain under `validate-sync.yml`.
- `validate-extensions.yml`: two source-layout assertions. The app continues
  to build but extension activation is not covered by an integration test.
- `validate-swiftui.yml`: two tests requiring particular observation variable
  names, revision counters, view modifiers and magic numbers.

Pruned source inspection jobs from **Downloads** (three plus redundant Swift
syntax parsing), **Sidebar** (one), **Browser Chrome** (two),
**WebKit** (two), and **Website Apps** (two redundant validator self-tests).
Removed the unbenchmarked library scaling run from **Swift Models**; the
baseline-vs-candidate library benchmark still exists in its informational
workflow. Removed exact-source AI browser action assertions and new-tab shader
source spelling checks but retained actual website augment/page extraction
JavaScript fixtures and real Metal shader compilation.

The website tint regression test now finishes after its executable color and
lifecycle cases, rather than checking private Swift identifiers and constants.
The startup framework guard now tests Xcode target dependencies, embedding,
package membership and browser-only source exclusion, not arbitrary UI class
names or private implementation strings.

Fixed the library benchmark to compare the PR candidate against the **PR base
commit**, rather than the candidate's immediate parent. Manual runs retain
the previous-commit fallback. The experimental Browser Use WebKit E2E remains
nonblocking but now publishes its outcome and a warning when it does not pass.

## Retained evidence

- macOS Debug build; unsigned Release archive, website runtime / bundle checks,
  Sparkle audit, optional assets and compiler safety settings.
- Executed Swift tests for native sidebar and split containers, persistence and
  sync, window ownership, automatic hibernation, download file workers, history
  ranking, Boost models, navigation failures and website-app preparation.
- Executed browser JS: Boosts, Reader, favicon observation, chrome tint
  sampling, page extraction and website augmentation.
- Browser Use protocol/DOM/listener fixture and automation-core package tests.
- Release metadata and **Validate Release**, the only status required by
  the currently published main-branch ruleset.

## Coverage gaps — not proven by a green check

Full WebKit drag/drop and file uploads; real extension installation;
segmented-download interruption/recovery; smooth sidebar drag and hover UI;
tab split gesture behaviour; AI tool consent, expiry and destructive-action
safety; Siri/Services dispatch; Handoff on physical devices. Actual end-to-end
tests must replace the deleted source-string guards when those areas are
prioritised. An app build does not validate interaction semantics.

Startup, WebKit and library performance runs are *informational*; a successful
job is not a performance improvement claim, and unavailable measurements
are not passing performance evidence.

## Rules for future additions

1. Execute production logic; use independent fixtures with defined expected outputs.
2. Do not check `"someString" in Source.swift`, magic constants, regex order,
   UI modifier text, or private function naming as acceptance criteria.
3. Do not create standalone CI jobs that merely parse source already compiled
   by the full app build or self-test an artifact validator instead of checking
   an actual artifact.
4. Report measured, skipped, experimental, and failed outcomes distinctly.
5. Do not rename the required `Validate Release` status without updating rulesets.

## Additional CI consolidation

The Browser Use macOS job no longer compiles the same Debug app once for
protocol tests and again for experimental WebKit E2E. It builds once and then
runs both steps with distinct reports. The CI/instrumentation workflow now
runs its small policy/asset/parser checks in one Ubuntu job and Swift safety
plus the process-birth executable in one Xcode job, instead of seven separate
runner allocations. Deleted the workflow diagnostics source-string guard and
run the real timing-report parser self-test directly. Optional asset checks
now examine actual source/bundle resources instead of checking for private
names inside the extension manager.
