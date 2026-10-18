# Left sidebar resize and scroll investigation

## Findings from build 3 source

The active desktop shell uses `ShellSpaceTabList`, which fades between spaces. It does **not** use `BrowserSpacePager`, so the existing AppKit horizontal pager is not the resize bottleneck in this path.

The left tab viewport was a SwiftUI `ScrollView` containing a `LazyVStack`, favourite `LazyVGrid`, reorder scopes, and hosted controls with glass, title masks, hover tracking, and drag/drop. The right AI sidebar shares `BrowserSplitView`'s resizing code but has different content. That content difference is a plausible reason for the reported asymmetry; this investigation has no on-device frame-time trace proving its relative contribution.

There was also a concrete feedback path on either divider:

1. Each pointer change wrote the split's local `resizedWidth`.
2. Every eight points, `onWidthChange` published a width to `DesktopBrowserShell`.
3. The derived minimum window width changed, invoking `updateWindowMinimumSize`.
4. That method always started a new 0.3-second visibility animation and completion, even when neither sidebar's visibility changed.

For the left divider, the inner right split and page also sit inside the resized content subtree. Repeated parent updates and redundant animation transactions add work beyond the required frame changes.

## Implementation

- Keep width changes local during the drag. Commit the exact width on release; external window-size clamps and accessibility adjustments still publish changes. Only actual visibility changes start the shell's show/hide animation.
- Replace the public and private **tab** viewports with `NSScrollView` + `NSCollectionView` on macOS and `UICollectionView` on iOS. AppKit/UIKit owns scroll momentum, clipping, native cell reuse, and drop destinations.
- Retain `BrowserTabRow`, `BrowserFavouriteTile`, folder controls, split rows, group actions and New Tab as SwiftUI content. The native viewport does not contain another SwiftUI `ScrollView` or a tall hosted `LazyVStack`.
- Use known row heights and four-column favourite geometry. AppKit hosts use `sizingOptions = []`, avoiding min/ideal/max SwiftUI measurement passes. Width-only changes resize visible cells without replacing their SwiftUI roots. Semantic updates refresh visible roots; offscreen rows receive current data when dequeued.
- Index vertical frames for O(log n + visible items) layout queries. A width change recomputes inexpensive frame rectangles, rather than measuring every tab view.
- Keep selected tabs from scrolling into view automatically. Structural edits preserve the first visible item and its pixel offset when that item survives.
- Route native insertion destinations through the existing `moveTabs` operations, including favourites, pinned tabs, folders, Today groups, and multi-selection. Existing macOS SwiftUI tab drag payloads and row split-drop handlers remain in place. Empty regions have destinations too.
- Fix hover-preview coordinates across separate hosting roots. Only hovered rows install a native frame reader; it converts into common window coordinates and observes the enclosing clip view. It publishes no frame state for non-hovered rows.
- Preserve the existing alpha fade, Haze blur and its compositing isolation. Downloads/library views and AI chat scrolling are outside this tab-viewport change.

## Validation and remaining measurement

Local structural checks cover native container ownership, visible-root updates, hover-only tracking, reorder destinations, the resize publication guard, observation, and helper-framework separation. They are not frame-time measurements.

`checks/native-sidebar-check.swift` compiles the production AppKit viewport independently of the full Xcode 27 app. The Sidebar workflow exercises 10,000 rows, checks visible-only cell creation, verifies width changes do not replace hosted roots, checks selection and structural scroll anchoring, validates cross-host preview coordinates, and compares indexed layout queries with brute force. It also typechecks the UIKit implementation against the simulator SDK. The normal Xcode 27 Debug build and archive workflows validate full-app integration.

This editing environment is Linux and has neither `xcrun` nor AppKit. The native tests therefore run in macOS CI; their results must be read separately from the local structural checks.

For device verification, use a Release build with representative favourites, folders, groups and 100–1,000 tabs. Compare left/right divider frame times and vertical scrolling in Instruments (SwiftUI, Time Profiler, Animation Hitches). Exercise reorder across every boundary, multi-select moves, tab split drops, rename/context menus, preview anchoring while scrolling, private mode, VoiceOver and Reduce Transparency. Inspect glass/Haze GPU cost if hitches remain. No measured FPS improvement is claimed here.
