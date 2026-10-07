# Desktop pane sizing and animation investigation

Date: 2026-10-07. Scope: normal and private desktop browser windows.

This is a source and primary-documentation investigation. Application code was not changed. The app was not launched or operated, in accordance with this project's inspection restrictions. The arithmetic findings below were checked against the actual `BrowserChromeMetrics` implementation. Timing, visible centering, and Auto Layout conflicts remain runtime hypotheses, not reproduced findings.

## Conclusion

The application has a shared collection of size constants, but it does not have a shared layout contract. Window constraints describe three abstract pane minima; the rendered hierarchy contains additional fixed widths, nested content, padding, and independently animated geometry. Increasing a single minimum or changing an easing curve cannot address all of those differences.

The smallest coherent repair is to retain the current shell, make the window and pane allocator consume the same content-aware width budget, establish sufficient space before presenting a pane, and animate pane visibility through one geometry calculation. A native `NSSplitViewController` is a credible alternative if native pane resizing and coordinated collapse behavior are part of the intended design. It is a larger integration change, not a prerequisite for correcting the width budget.

## Current ownership

| Component | Current responsibility | Gap |
| --- | --- | --- |
| [BrowserWindowController](../astra/UI/Shell/BrowserWindowController.swift) | Restores/creates the window, embeds a hosting view, initially sets a 270-point content minimum | Initial minimum does not include visible sidebar or active content requirements |
| [DesktopBrowserShell](../astra/UI/Shell/DesktopBrowserShell.swift) | Derives visibility, changes window minimum, animates window growth | Constraint update occurs after view state changes; owns an AppKit animation separate from pane animations |
| [BrowserChromeMetrics](../astra/UI/Chrome/BrowserChromeMetrics.swift) | Adds nominal pane minima and clamps preferred sidebar widths | Assumes enough available space; does not describe nested pages or control overflow |
| [BrowserSplitView](../astra/UI/Shell/BrowserSplitView.swift) | Allocates one sidebar and remaining content, masks and clips both | Nested instances independently compute and animate frames; fixed frames use default center alignment |
| [BrowserSpacePager](../astra/UI/Shell/BrowserSpacePager.swift) | Embeds hosted sidebar pages and manages horizontal transitions | Inner hosts retain automatic sizing; resize code also touches the page controller's private transition hierarchy |

The shell nests a leading split around a trailing split. The leading split reserves `270 + 300` when AI is requested, and the trailing split reserves 270 for the page. AI visibility also depends on the selected tab, feature preferences, private browsing, and URL availability. Therefore pane changes occur through tab selection and settings as well as explicit toggle buttons. Fixes placed only in a toggle handler would miss these paths.

The left sidebar is a global Defaults preference exposed through each `Browser`; AI visibility is per-browser state. Any repair must preserve these semantics and apply constraints separately to each window.

## Confirmed source findings

### 1. Endpoint arithmetic is correct only within its assumed domain

The nominal window minima are:

| Left sidebar | AI sidebar | Content minimum |
| --- | --- | ---: |
| Hidden | Hidden | 270 |
| Shown | Hidden | 400 |
| Hidden | Shown | 570 |
| Shown | Shown | 700 |

For widths at or above those minima, the existing pure arithmetic check passes. It would be incorrect to claim that the endpoint formula simply forgets the AI pane.

However, `sidebarWidth` always returns at least its lower bound, even when `availableWidth - minimumContentWidth` is smaller. Calling the actual helper for both requested panes at width 400 gives:

```text
left = 130
right = 300
nominal remaining content = -30
BrowserSplitView clamps the content frame to 0
```

This is an invalid allocation for a real page. Clamping the final frame to zero prevents a negative frame argument; it does not make the allocation fit or preserve the page minimum. The current allocator has no explicit insufficient-space outcome.

### 2. The 270-point page budget does not include Settings' internal panes

[BrowserSettingsView](../astra/UI/Settings/BrowserSettingsView.swift) contains a fixed 230-point navigation list, a divider, and usually 16-point padding on both sides of its detail view. [ShellContentColumn](../astra/UI/Shell/DesktopBrowserShell.swift) adds 4-point horizontal page gutters when chrome is visible.

At the allowed 270-point central pane width, the remaining detail budget is:

```text
270 - 8 page gutters - 230 navigation - 32 detail padding = 0
```

That is before the divider and any detail controls. Even the About page, which omits the 32-point detail padding, has a fixed 200-point image. A universal page minimum of 270 cannot represent the existing two-column Settings design. AI is unavailable on internal pages, so this failure can occur with the left sidebar alone at a nominal 400-point window width.

The website toolbar is another independent width demand: navigation, zoom, screenshot, monitoring, translation, optional reader/developer actions, address controls, extension actions, spacing, and window-control reservation. Pinned extension actions have no fixed count limit. A single fixed page minimum cannot guarantee that this row always fits. It needs an overflow layout as well as a usable address-field budget.

### 3. Sidebar reservation and sidebar minimum disagree

The left sidebar lower bound is 130, while `ShellNavigationBarControls` is explicitly framed at `persistentControlsAreaWidth`, 160. This is a declared subtree footprint larger than the allowed pane width. That particular view is currently largely a spacer, so this mismatch alone does not establish that traffic-light buttons visibly clip. It does establish that the declared widths are not a consistent description of the hierarchy.

### 4. Window enforcement is late and does not coordinate presentation

`DesktopBrowserShell` updates `contentMinSize` from `.task(id: minimumWindowWidth)` and the window-attachment callback. Pane visibility and body layout have already changed by the time the task runs. If growth is necessary, the shell starts a separate 0.3-second AppKit animation and returns without a completion dependency for pane presentation.

On collapse, the minimum immediately reflects the new visibility Boolean, although the old pane can remain visually present during its closing animation. There is no explicit transition-period minimum. Full-screen growth is deliberately skipped, and the screen adjustment clamps the origin rather than resolving a width larger than the screen.

Apple documents that `contentMinSize` constrains user resizing, but excludes the commonly used `setFrame(_:display:)` and `setFrame(_:display:animate:)` setters from minimum enforcement. Assigning the minimum is therefore not a universal frame invariant. The current growth code computes an adequate endpoint itself; the documentation exception does not prove that its endpoint is wrong. Every programmatic frame path still needs a valid allocation. [Apple: contentMinSize](https://developer.apple.com/documentation/appkit/nswindow/contentminsize).

### 5. Resizing and visibility share animation modifiers

`BrowserSplitView` places content frame and padding changes inside `.animation(_:body:)`. Those values depend on both pane visibility and current geometry. Ordinary window resizing can therefore enter the same animated modifiers used to reveal a sidebar. Sidebar width and trailing offset are outside the sidebar's mask animation, while content frame and padding are inside another animation scope.

The outer and inner split allocations also depend on one another. The AppKit window animation uses an ease-in/ease-out timing function; SwiftUI uses `.smooth`. Matching their durations does not give them a shared progress value, start time, or interruption policy. The outer sidebar transaction and selected-tab animation suppressors add further transaction boundaries.

Apple confirms that `.animation(_:body:)` applies to the animatable modifiers inside its closure. That supports the resize-animation concern; it does not establish the precise visual timing without a rendering probe. [Apple: animation(_:body:)](https://developer.apple.com/documentation/swiftui/view/animation(_:body:)).

### 6. Centering has two relevant framework mechanisms

The fixed sidebar and content frames omit `alignment`, whose default is `.center`. The outer ZStack's `.topLeading` alignment does not change the alignment inside those fixed frames. A child that requires more width can be centered within its smaller wrapper and then clipped. [Apple: frame(width:height:alignment:)](https://developer.apple.com/documentation/swiftui/view/frame(width:height:alignment:)).

The root hosting view disables automatic sizing using `sizingOptions = []`. This makes the shell responsible for fitting its content. Inner sidebar page hosts do not disable sizing options, so they retain automatic minimum, ideal, and maximum constraints. Apple explicitly documents hosted-content centering when the hosting frame differs from the required content size. [Apple: NSHostingView.sizingOptions](https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions).

These mechanisms explain why clipping can look centered even though the root stack is leading-aligned. Which hosting boundary actually overflows requires runtime inspection. Blindly enabling root `.minSize` is not a demonstrated fix: the root geometry-based layout does not expose the complete required width, and inner constraints can still compete.

## Secondary animation concern

`BrowserSpacePageController.viewDidLayout()` assigns every direct subview the same bounds and calls `completeTransition()` whenever its bounds size changes. Apple documents that `NSPageController` uses a private hierarchy while transitioning and completes that transition after the new content is ready or the animation ends. Resizing during a space transition can therefore interfere with that private hierarchy or terminate a transition early. This is a source-level concern, not a confirmed cause of window clipping. Keep any repair limited to application-owned content and verify resize-during-swipe separately. [Apple: NSPageController](https://developer.apple.com/documentation/appkit/nspagecontroller).

## Repair options

| Option | What it resolves | Limit |
| --- | --- | --- |
| Retain shell; unify width budgets and presentation order | Current minimum mismatch, invalid intermediate allocations, separate resize/reveal animation behavior | Application continues to own sizing and transitions |
| Use NSSplitViewController for the outer three panes | Native pane constraints, holding priorities, collapse behavior and animations | Larger host integration; still needs correct content minima and toolbar overflow |
| Replace outer shell with NavigationSplitView | Native navigation column management | Intended for hierarchical selection; AI is an inspector-like sibling, and column widths are preferences rather than universal hard constraints |
| Add leading alignment or geometryGroup only | Some centering or descendant animation artifacts | Neither creates missing width nor coordinates the window minimum |

Apple's native split controller supports Auto Layout-driven pane collapse/reveal. `NSSplitViewItem.minimumThickness` sets pane minima and `holdingPriority` controls which pane absorbs resizing. Collapse behaviors can prefer resizing sibling panes, prefer resizing the window, or use constraint animation. Even native constraint collapse needs external constraints to manage window position and screen bounds. [Apple: NSSplitViewController](https://developer.apple.com/documentation/appkit/nssplitviewcontroller), [minimumThickness](https://developer.apple.com/documentation/appkit/nssplitviewitem/minimumthickness), [holdingPriority](https://developer.apple.com/documentation/appkit/nssplitviewitem/holdingpriority), [collapse behaviors](https://developer.apple.com/documentation/appkit/nssplitviewitem/collapsebehavior-swift.enum), [useConstraints](https://developer.apple.com/documentation/appkit/nssplitviewitem/collapsebehavior-swift.enum/useconstraints).

`NavigationSplitView` tries to accommodate column preferences but may adjust them for other constraints; it is not a drop-in guarantee for this browser's pane minima. [Apple: NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview), [column widths](https://developer.apple.com/documentation/swiftui/view/navigationsplitviewcolumnwidth(min:ideal:max:)).

`geometryGroup()` resolves and animates parent geometry before passing it to descendants, which can help nested animations move together. It cannot fix insufficient width. Evaluate it only after correcting the layout contract. [Apple: geometryGroup()](https://developer.apple.com/documentation/swiftui/view/geometrygroup()).

## Minimum coherent implementation plan

Goal: every visible pane receives its actual usable width during startup, resize, content changes, and transitions.

Non-goals: change browsing state, persistence format, global sidebar preference semantics, WebView retention, themes, mobile layout, or introduce a generic layout framework.

1. Define page requirements in the existing sizing boundary. Include page gutters and Settings' internal navigation/detail budget. Establish a usable sidebar minimum from its actual contents. Give website controls an overflow presentation so extension count cannot force unbounded width.
2. Use those same requirements for window creation/restoration and pane allocation. Represent insufficient space explicitly. Full-screen and narrow-screen states need an adaptive presentation, not a zero-width content frame or an offscreen window.
3. Put native minimum/frame mutation under one window owner. When expansion needs more space, establish that space before revealing the pane. The smallest reliable initial behavior is immediate window growth followed by pane animation. If simultaneous growth is required, use one coordinated native transition rather than unrelated AppKit/SwiftUI clocks. Retain the old required minimum through collapse completion.
4. Make visibility progress the animated input. Derive mask, reserved width, content origin, and content width from that progress in one allocation. Live window geometry must apply immediately. Share allocation between leading and trailing panes if independent nested calculations cannot maintain the invariant.
5. Audit inner hosting constraints and use explicit leading alignment where oversized content should be pinned. Preserve view identities so AI chat and WebViews are not recreated on collapse. Keep Reduce Motion, hidden-pane hit testing, and accessibility behavior.
6. Update the existing checks to test behavioral invariants instead of requiring a particular animation implementation. Investigate pager resizing only if its separate transition scenario fails.

Acceptance criteria:

- At every layout sample, allocated pane widths plus gutters fit the actual content bounds; no visible page receives less than its required budget.
- New and restored windows begin with valid constraints, including when the global sidebar preference changes.
- Live resizing has no delayed pane catch-up; opening/closing either pane at the narrowest supported width preserves content.
- Rapid reversals and tab changes during transitions settle to the latest requested state without stale window growth or disappearing page content.
- Settings detail remains usable, and website controls remain reachable with many pinned extensions.
- Full-screen, smaller displays, multiple windows, and Reduce Motion have explicit valid behavior.

## Verification performed and limits

The existing arithmetic check passed:

```sh
DEVELOPER_DIR='/Applications/Xcode-beta 27.2 beta 2.app/Contents/Developer' swiftc astra/UI/Chrome/BrowserChromeMetrics.swift checks/desktop-pane-sizing-check.swift -o /tmp/astra-desktop-pane-sizing-check && /tmp/astra-desktop-pane-sizing-check
```

Output: `Desktop pane sizing checks passed`.

A temporary Swift check compiled the actual metrics implementation and confirmed the 400-point invalid allocation, 130/160 reservation mismatch, and zero Settings detail budget. Its temporary source and executable were removed. This verifies arithmetic, not rendered animation timing.

The older check failed immediately:

```sh
python3 checks/internal-page-chrome-check.py
```

It expects `let visibleWidth = width * sidebarVisibility` and an `Animatable` split view. The current split uses a Boolean endpoint and scoped modifier animations. The check also substitutes an incomplete metrics stub for the current initializer. Its failure establishes that the check is stale; it does not reproduce the user's visual bug.

The configured developer directory points at a missing Xcode beta 1 installation. Only the standalone check invocation was overridden to the installed beta 2 path. No global configuration was changed. Xcode MCP tools were unavailable; no application build or UI session was run.

The remaining verification seam is the rendered window hierarchy: sample window content width, each pane's actual bounds, hosting fitting sizes/constraints, and transition progress during narrow-window toggles and resize. That is required before claiming that clipping and centering are fixed.
