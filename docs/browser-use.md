# Browser Use

Astra exposes an opt-in local MCP server on macOS. It operates Astra's existing
WebKit tabs, independently of the OpenAI Browser extension and Playwright.

## Connect Codex

1. Open Settings → Developer → Browser Use and enable Browser Use.
2. Wait for Status to show Ready.
3. Select Copy Codex Configuration and paste the TOML into `~/.codex/config.toml`.
4. Reload the MCP connection in Codex.

The copied configuration contains the local bearer credential. Keep it private.
Disabling Browser Use or quitting Astra clears the credential and every tab grant.
Enable again and copy the new configuration to reconnect. The server is disabled
on every app launch and does not modify Codex configuration automatically.

If enabling immediately turns off, inspect Status. A sandboxed build must include
the Incoming Connections capability. Rebuild and relaunch the intended checkout;
an already running build from another checkout retains its previous signature and
permissions. The Browser Use worktree enables this capability for the main app.

## Share and revoke tabs

Agents can create an ordinary HTTP(S) tab through `open_tab`; that new tab is
shared automatically. Existing tabs require the Share with Browser Use button in
the page's top bar. `list_tabs` lists only accessible shared tabs.

Shared pages have a blue-and-white dashed border and a Controlled by Browser Use
label. The adjacent Revoke Browser Access button removes that tab's grant, clears
its element references, and cancels pending operations. Other shared tabs remain
accessible. An agent cannot restore the grant; sharing again is a user action.
Revocation prevents subsequent work but cannot undo an action already dispatched
to the website.

Private tabs, internal pages, Mini Astra windows, and standalone website apps are
excluded. A grant belongs to a specific tab in a specific window. Closing the tab
or window, or moving its WebView ownership to another window, invalidates access.

## Tools

| Tool | Purpose |
| --- | --- |
| `list_tabs` | List shared tab and window IDs |
| `open_tab` | Create a shared HTTP(S) tab; optional `windowID` selects its window |
| `navigate` | Navigate a shared tab |
| `read_page` | Read rendered text, excluding form values |
| `snapshot` | Inspect controls and generate temporary element references |
| `click` | Click an element reference |
| `fill` | Fill a text field; password and file fields are excluded |
| `select_option` | Choose an available select option |
| `scroll` | Scroll vertically by bounded CSS pixels |
| `screenshot` | Return the viewport as MCP image content |
| `wait` | Wait for page readiness or visible text, with a bounded deadline |

Tab tools require `tabID`. Element tools also require a `ref` from the latest
snapshot. References expire after navigation, controller changes, or another
snapshot. A reference retains its original DOM node and does not silently target
a replacement element. Concurrent operations on the same tab are rejected.

## Boundaries and limitations

- The endpoint binds to `127.0.0.1:8766` and authenticates every request. Host and
  Origin validation prevent a website from driving the endpoint. Requests have
  framing, size, connection-count, and lifetime limits.
- MCP protocol handling uses the official Swift SDK's stateless Streamable HTTP
  transport. The server returns JSON responses and does not offer SSE streaming.
- Shared tabs retain their normal website session. Their visible account content
  and screenshots can become part of the agent's conversation.
- Page content is untrusted input. Clicking can submit forms or change remote
  data; tool annotations identify mutations. The server does not infer the
  consequence of every website button.
- Actions use JavaScript DOM events. Websites requiring trusted input, native
  dialogs, or browser user activation require manual interaction.
- Element snapshots cover the main frame and open shadow roots. Frame-specific
  control, closed shadow roots, arbitrary JavaScript, cookie access, file access,
  and upload/download tools are excluded.
- Hibernated or unavailable pages must be made ready before page tools can operate.
  Reader mode supports reading and screenshots; DOM element actions require the
  underlying webpage view.

## Focused verification

HTTP framing checks use the production parser:

```sh
swiftc -swift-version 6 -parse-as-library \
  astra/Agent/BrowserAgentHTTP.swift scripts/check_agent_http.swift \
  -o /tmp/astra-agent-http-checks
/tmp/astra-agent-http-checks
```

After an Xcode MCP build, run the combined checks with its products directory:

```sh
scripts/check_browser_use.sh /path/to/DerivedData/astra/Build/Products/Debug
```

The combined checks run the production HTTP parser, real WebKit page scripts, and
the production MCP server against minimal host-model fixtures without user data.
Port 8766 must be free. They cover initialization, tools discovery, unauthorized
requests, Origin rejection, URL validation, revoked and private tabs, revocation
during a suspended read, and credential rotation. The DOM checks cover input-value
privacy, fill, select, click, and rejection of replaced nodes.
The listener checks also reproduce network-binding denial in a restricted child
process and verify that the permission failure stays visible in Status.

Completed verification: these checks pass, and the main app builds through Xcode
MCP. Full interactive UI verification remains pending: native computer-use startup
failed, and Xcode's preview service could not render the controls. The fixtures do
not substitute for a complete Codex-to-visible-Astra-tab exercise.
