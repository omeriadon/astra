# Synced-tab Handoff

Astra advertises the selected public HTTP(S) tab using `com.omeriadon.astra.browse`
on macOS and iOS. The activity carries the **stable `BrowserTab.id` UUID**,
not instructions to open a URL. The URL is provided only as Handoff's webpage
metadata for platforms where Astra is not installed; Astra itself never uses it
to construct a tab during continuation.

## Receiving

1. Wait for the browser's persistence hydration and Astra Sync's saved
   credentials to load.
2. Attach the receiving browser to `BrowserSync` and explicitly call
   `syncNow()`. If another sync is running, wait for it instead of silently
   treating a queued sync as finished.
3. Find the requested UUID in the merged tab collection. If it is missing,
   retry a few times to accommodate the sender's normal debounced upload.
4. Select that existing UUID with `Browser.selectTab`, reusing its space,
   title, and synced navigation state. **Never call `addTab` or navigate to
   `activity.webpageURL`.** If the ID is unavailable, show an error.
5. On macOS, queue cold-launch activities until window restoration completes.
   When already running, use a nonprivate browser window.

Neither device deletes the original tab. Both devices refer to the same
logical tab ID; each has its own local `WKWebView` instance.

## Privacy and limitations

- No activity is published for private, Mini Astra, internal, new-tab overlay,
  signed-out, or inactive browsing windows.
- File URLs are excluded. Handoff URL metadata is stripped of HTTP credentials.
- Apple Handoff requires a compatible signed-in Apple Account, Bluetooth,
  Wi-Fi, and apps signed with the same Apple Developer Team ID. Astra Sync
  additionally requires both devices to be signed into the same Astra account.
- This transfers synced tab metadata, not live JavaScript process memory, DOM
  state, form inputs, playback sessions, or unsynced WebKit back-forward state.
  Astra's portable sync projection deliberately removes WebKit restoration data.
- An unavailable or deleted tab is not recreated by URL fallback.

## Verification

Runnable pure identity check:

```sh
swiftc astra/Models/Core/BrowserHandoffTabReference.swift checks/handoff-payload-check.swift -o /tmp/astra-handoff-check
/tmp/astra-handoff-check
```

Physical-device test matrix (both signed with the same developer team):

1. Mac to iPhone, then iPhone to Mac: the selected tab's UUID and space
   membership remain unchanged, and tab count does not increase from Handoff.
2. Change the source URL just before triggering Handoff: the receiver fetches
   sync, retries while the sender uploads, and selects the original tab ID.
3. Receiver cold launch: wait for local hydration and Keychain sign-in before
   synchronizing and selecting the incoming tab.
4. Receiver already has the same UUID selected, hibernated, or open in another
   window: no duplicate; selecting wakes or claims the existing tab.
5. Close the tab on the source before synchronization: receiver must not create
   a substitute tab even though the activity carries a webpage URL.
6. Private, Mini Astra, internal pages, signed-out sessions, and inactive
   windows do not publish browsing Handoff.
7. Fail the sync server or sign out on the receiving device: display an error
   without navigating to a URL or opening a new tab.
8. Deliver the same activity twice and switch windows during its download:
   do not race or create duplicate tabs.

A macOS/iOS Xcode build and physical-device Handoff smoke test are still
required; Linux cannot exercise AppKit, UIKit, or SwiftUI continuation.
