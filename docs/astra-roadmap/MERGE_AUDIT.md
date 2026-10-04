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
