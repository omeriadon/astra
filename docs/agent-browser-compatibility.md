# Agent browser integration feasibility

Checked 2026-10-11. Direct Playwright attachment to Astra's macOS WKWebViews remains
blocked. Astra's separate native MCP integration is documented in
[Browser Use](browser-use.md); it does not depend on a Playwright inspector transport.

## Original attachment investigation (2026-10-11)

Reuse an existing browser automation backend and MCP package to operate Astra's
live tabs. Preserve the WebKit engine, session ownership, private browsing,
navigation policy, and site permissions. The original investigation evaluated direct reuse of an inspector backend. The
Browser Use implementation instead uses public WKWebView execution and capture
APIs behind Astra's own MCP adapter; it does not emulate CDP.

The acceptance gate is an existing backend inspecting, clicking, filling,
navigating, and taking a screenshot of an actual Astra tab. A separate Chrome or
Playwright WebKit browser does not satisfy this gate.

## Verified upstream behavior

| Component | Verified behavior | Missing part for Astra |
| --- | --- | --- |
| Chrome DevTools MCP | Uses Puppeteer to connect to Chrome's built-in debugging endpoint | macOS WKWebView does not expose that Chrome endpoint |
| Playwright core 1.64.0 | Includes the stock WebKit WebView backend and routes WebKit attachment through `connectOverRDP` | A transport exposing Astra's macOS Web Inspector targets |
| Playwright MCP 0.0.83 | Depends on Playwright 1.64.0-alpha-1790635538000; its existing debugging-endpoint factory calls `playwright.chromium.connectOverCDP` | Selecting WebKit attachment alone would still leave the macOS transport missing |
| ios-webkit-debug-proxy | Bridges iOS Web Inspector traffic to target discovery and WebSocket endpoints | Its device/simulator transport does not attach to a local macOS WKWebView |
| OpenAI Browser package installed locally, 26.915.31945 | Its client sends setup and execution requests through the desktop Node REPL browser service; its manifest identifies a proprietary package | The installed client is not a redistributable standalone backend or an Astra browser registration API |

Sources:

- [Chrome DevTools MCP connection implementation](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/src/BrowserManager.ts)
- [Playwright 1.64.0 WebKit attachment](https://github.com/microsoft/playwright/blob/v1.64.0/packages/playwright-core/src/server/webkit/webkit.ts)
- [Playwright 1.64.0 stock WebView backend](https://github.com/microsoft/playwright/blob/v1.64.0/packages/playwright-core/src/server/webkit/webview/wvBrowser.ts)
- [Playwright stock Mobile Safari backend reference](https://github.com/microsoft/playwright/blob/main/.claude/skills/playwright-dev/webview.md)
- [Playwright WebView test fixture](https://github.com/microsoft/playwright/blob/v1.64.0/tests/webview/webviewTest.ts)
- [ios-webkit-debug-proxy implementation and supported targets](https://github.com/google/ios-webkit-debug-proxy)
- [Playwright simulator verification workflow](https://github.com/microsoft/playwright/blob/main/.github/workflows/tests_webview_simulator.yml)
- [Published Playwright core 1.64.0 metadata](https://registry.npmjs.org/playwright-core/1.64.0)
- [Published Playwright MCP 0.0.83 metadata](https://registry.npmjs.org/@playwright/mcp/0.0.83)
- [OpenAI's supported browser extension setup](https://learn.chatgpt.com/docs/chrome-extension)

The published Playwright core tarballs were inspected directly. The relevant
implementations are bundled into `package/lib/coreBundle.js`; absence of separate
`webkit/webview` files in the archive does not mean the backend is absent.

## Astra already exposes inspection

`BrowserDesktopCommands.configureWebInspector` sets `WKWebView.isInspectable`.
`BrowserController` applies the existing `webInspectorEnabled` setting when
creating a WebView and observes later changes. The developer settings view
already provides the toggle. No additional inspection toggle is needed.

[Apple's supported inspection path](https://developer.apple.com/documentation/safari-developer-tools/enabling-inspecting-content-in-your-apps)
uses Safari Web Inspector. This does not itself create a target-discovery HTTP
endpoint or a WebSocket transport for Playwright.

Astra also explicitly disables extension native messaging in
`BrowserExtensionManager.enable`. Merely importing OpenAI's Chrome extension or
removing that restriction would not supply debugger compatibility, its native
host, or desktop browser discovery.

## Exact blocker

The stock Playwright backend expects Web Inspector messages through an existing
transport. The maintained bridges inspected target iOS devices or iOS Simulator.
No maintained reusable bridge to Astra's local macOS WKWebView process was found.
The ordinary Playwright WebKit launcher uses its own browser and cannot substitute
for Astra's live tabs.

The other inspected projects do not close this gap:

- [pymobiledevice3](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/webview-debugging.md)
  connects through iOS device services.
- [MCP Browser](https://github.com/brainfuel/mcp-browser) owns its own WKWebView
  browser and MCP implementation.
- [MCPWebKit](https://github.com/Sunalamye/MCPWebKit) exposes JavaScript tools
  through an application callback. It is a different automation interface, not a
  Playwright transport, and needs a separate access-control review.
- [computer-use-mcp](https://github.com/minghinmatthewlam/computer-use-mcp)
  provides desktop Accessibility and screenshot control, not Playwright DOM
  attachment.

Implementation can resume when a reusable macOS Web Inspector transport is
identified, or when the integration scope explicitly changes to desktop control
or a native MCP interface. Adding dependencies or connection UI before resolving
that choice would produce a nonfunctional feature.

## Verification limits

Completed: Astra source inspection, upstream source inspection, published npm
package inspection, and an independent primary-source transport investigation.

Not completed: live Playwright attachment, browser interaction, MCP handshake,
or signed-app runtime verification. No compatible macOS endpoint was identified
to exercise. No Swift source, project configuration, dependencies, or Codex
configuration were changed; no build was required for this document.

## Native MCP comparison (2026-10-14)

| Property | Astra Browser Use | Playwright MCP | Chrome DevTools MCP |
| --- | --- | --- | --- |
| Browser connection | Astra-owned WKWebViews and website sessions | Playwright browser backend | Chrome debugging endpoint through Puppeteer |
| Native browser organization | Astra tabs, Spaces, library and related models | Backend page/context management | Chrome targets and developer tooling |
| Semantic inspection | Bounded DOM-derived role/name/state data; not the platform accessibility tree | Accessibility snapshots with element references | Chrome inspection backend |
| Input | DOM-generated pointer input is synthetic; targeted AppKit keyboard and opt-in pointer paths report dispatch without guaranteeing DOM trust | Backend input mechanisms | Backend input mechanisms |
| Cross-origin frames | Only frames actually reached are inspected; inaccessible frames are explicit | Backend frame targeting | Backend frame targeting |
| Network observation | Page instrumentation is partial and must be identified as such | Backend network observation | Chrome developer network observation |
| Protocol | Focused adapter around official Swift MCP tool DTOs | Its published MCP server | Its published MCP server |

This comparison describes backend capabilities, not an interoperability test.
Astra does not gain Playwright's auto-waiting or CDP coverage by exposing similarly
named tools. Synthetic keyboard and pointer events cannot establish native
user activation. Closed shadow roots are not accessible through normal DOM
traversal. A frame-specific WKWebView execution API is public, but a reference to
an actual frame is still needed; its existence does not prove arbitrary frame
enumeration or cross-origin inspection in Astra.

Primary sources reviewed for the overhaul:

- [Current MCP versioning](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/versioning.mdx)
- [July 2026 discovery](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/server/discover.mdx)
- [July 2026 HTTP metadata binding](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/transports/streamable-http.mdx)
- [Official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk), whose README identifies 2025-11-25 support; package updates alone do not implement July 2026 behavior
- [Playwright aria snapshots](https://playwright.dev/docs/aria-snapshots)
- [Playwright MCP source](https://github.com/microsoft/playwright-mcp)
- [Chrome DevTools MCP source](https://github.com/ChromeDevTools/chrome-devtools-mcp)
- [Apple frame-specific evaluation](https://developer.apple.com/documentation/webkit/wkwebview/evaluatejavascript(_:in:in:completionhandler:))
- [Apple snapshot capture](https://developer.apple.com/documentation/webkit/wkwebview/takesnapshot(with:completionhandler:))
- [Apple upload-panel delegate](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:runopenpanelwith:initiatedbyframe:completionhandler:))
- [W3C accessible name computation](https://www.w3.org/TR/accname/)

No upstream source is copied into the compatibility document or adapter. The
implementation and test commands are documented in [Browser Use](browser-use.md)
and [Browser Use architecture](browser-use-architecture.md). Runtime limitations
must be established against the actual Astra build; the historical attachment
investigation above is not a passing Browser Use integration test.
