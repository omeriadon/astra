# Desktop Web Push and application links

Scope: system WebKit in the macOS desktop shell. Spatial audio and signed-release work are excluded from this pass. Verification used source inspection and an app-only Xcode MCP build. No application was launched and no tests were added or run.

## Web Push feasibility

The installed macOS 27.2 SDK has no public WKWebView host API for website notification permission, pending push delivery, or notification-click dispatch. Safari's website support does not establish support for an arbitrary WKWebView host: Apple's website documentation describes Safari and installed web apps. [Apple Web Push documentation](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers).

Upstream WebKit exposes the relevant host operations privately: pending-message retrieval, push processing, and persistent-notification click/close processing are declared in `WKWebsiteDataStorePrivate.h`. Notification display and permission callbacks are likewise in a private data-store delegate. [Private host operations](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStorePrivate.h), [private delegate](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/_WKWebsiteDataStoreDelegate.h).

The decisive boundary is beyond missing Swift declarations. WebKit's push daemon checks the host's audit token for `com.apple.private.webkit.webpush` and rejects connections without it. A macOS open-source-build branch skips that check for WebKit's development environment; that branch does not establish access to Apple's system daemon. The source also permits Apple-internal additions, so this finding is specifically about the inspected public integration path. [Daemon authorization](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/webpushd/PushClientConnection.mm).

Conclusion: real Web Push cannot be completed through the current public system-WKWebView host integration. Calling private selectors or adding native notifications would not resolve the daemon's authorization check. No pretend Notifications/Push API, polling service, or notification substitute was added. The general earlier "unresolved public API" finding is now supported by this concrete authorization boundary.

## Links to macOS applications

Ordinary HTTP/HTTPS links retain `.allow`. In WebKit's Cocoa navigation client, that policy invokes app-link interception through LaunchServices; a failed interception returns to normal website navigation. The app-link feature is enabled for macOS in WebKit's platform definitions. [Native handoff and fallback](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/Cocoa/NavigationState.mm), [platform support](https://github.com/WebKit/WebKit/blob/main/Source/WTF/wtf/PlatformHave.h).

WebKit also decides whether a link is eligible: the inspected main-frame path excludes same-host navigation and back/forward navigation, and tracks the external-URL policy. Astra retains those decisions rather than routing every HTTPS URL back through the default browser. Modifier gestures continue to create browser tabs or peeks. [Eligibility rules](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebPageProxy.cpp).

Custom application schemes are dispatched through the installed macOS handler, including telephone, messages, email, FaceTime, calendar, store, and third-party protocols when an appropriate app is installed. Astra resolves the receiving app, names it in a confirmation attributed to the requesting frame's origin, and opens the original URL through `NSWorkspace` with that specific app. Missing handlers and launch failures now produce a visible message. The selected app is fixed before confirmation, concurrent prompts from one controller are coalesced, navigation/close invalidates pending consent, self-handoff is refused, and dispatched links are omitted from Recent Items. [Native application dispatch](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)).

Web-content schemes stay in the engine. This includes HTTP/HTTPS universal links, local files, blobs, data URLs, `about:`, JavaScript links, and native extension pages. The existing mailto-copy preference still takes precedence; disabling that preference allows dispatch to the mail app. Authentication-session callback matching still runs before external-application dispatch.

The app-only build passed. Source tracing verifies the configured paths and confirms that macOS's native universal-link path remains reachable. Actual installed-app launch, domain association, and user-disabled universal-link behavior were not executed under the project's source/build-only restriction; those outcomes depend on the receiving app and macOS association state.
