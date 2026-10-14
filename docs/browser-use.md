# Browser Use

Astra's optional macOS MCP endpoint automates the actual Astra tabs and their WebKit sessions. It is independent of Playwright and the OpenAI Browser extension.

## Connect and authorize

1. In Astra, open Settings → Developer → Browser Use and enable Browser Use. Wait for **Ready**.
2. Select **Copy Codex Configuration**, paste the TOML into `~/.codex/config.toml`, and reload Codex's MCP connection.
3. Create a tab with `open_tab`, or share an existing ordinary tab with **Share with Browser Use** in its top bar.

The copied configuration contains a bearer credential; keep it private. Astra listens at `http://127.0.0.1:8766/mcp`, validates Host and Origin, and requires authorization on every request. Browser Use begins disabled on app launch. Disabling it or quitting Astra clears the credential and grants. Enable it again and copy a fresh configuration to reconnect. Astra does not modify Codex configuration automatically. A sandboxed macOS build needs the **Incoming Connections** entitlement. If enabling immediately switches off, read the displayed Status and rebuild the intended checkout with that capability.

New HTTP(S) tabs opened by the agent are shared automatically. A shared tab uses Astra's regular website session, including authentication cookies, sign-in forms, redirects, and navigation across origins. Browser Use does not impose per-origin approval. Private tabs, internal pages, Mini Astra windows, and standalone website apps are excluded. A controlled tab shows a border and **Controlled by Browser Use** label. Its **Revoke Browser Access** button removes only that grant, clears refs, and cancels pending work. An agent cannot regrant an existing tab. Revocation cannot reverse a website action that already took place.

Developer settings have separate toggles for arbitrary JavaScript evaluation, native library changes, and Boost changes. These reset when Browser Use stops. Ordinary page navigation and form use do not require these toggles.

## Protocol and output

The adapter advertises `2026-07-28`, `2025-11-25`, `2025-06-18`, and `2025-03-26`. The July 2026 route uses `server/discover`, per-request `_meta` version and client capabilities, and matching `MCP-Protocol-Version` and `MCP-Method` headers. A `tools/call` request also binds `MCP-Name` to `params.name`. Modern successful results contain `resultType: "complete"` and `_meta.io.modelcontextprotocol/serverInfo`. Older clients use `initialize` and `notifications/initialized`. `tools/list` returns the immutable catalog without pagination. The endpoint returns JSON over stateless Streamable HTTP; it does not stream SSE or resume sessions. Only the tools capability is advertised. The official Swift MCP SDK supplies tool DTOs, but its own stated protocol support must not be mistaken for interoperability proof of this adapter.

Successful tool calls use MCP text content containing JSON and, for most tool calls, `structuredContent`. Screenshots instead return MCP image content with PNG or JPEG MIME type. Tool failures have `isError: true` and explanatory text; do not assume a dispatched click or navigation proves a remote postcondition. `navigate` reports `navigationStarted`, and an agent should use a wait or read to verify the destination. Protocol errors use JSON-RPC codes including `-32700` (parse), `-32600` (invalid request), `-32601` (unknown method), `-32602` (invalid parameters), `-32020` (mismatched modern metadata/headers), and `-32022` (unsupported version). HTTP authentication and validation can instead return 401, 403, 404, 405, 406, or 415. Tool errors include revoked access, stale ref, unavailable page, invalid arguments, busy tab, and separately permissioned operations.

All tab-specific tools require a UUID `tabID`; `list_tabs` returns granted `tabID` and owning `windowID`. `open_tab` accepts `url` and optional `windowID`; absent `windowID`, it chooses the active eligible window or an eligible fallback. URLs must be credential-free HTTP(S). Use explicit IDs in multiwindow automation. Grant validity is tied to the owning tab and window. Closing either or transferring ownership invalidates the grant. Different tabs can have suspended operations concurrently; a conflicting second operation on the same tab returns busy.

## Tool arguments

The MCP `tools/list` catalog is authoritative for JSON schema properties. IDs and text fields are JSON strings; flags are booleans; offsets, limits, geometry, quality and timeouts are numbers; `values`, `modifiers` and `properties` are arrays of strings. Only fields explicitly marked required in the tables are schema-required; page actions validate their operation-specific target/value requirements at runtime. All schemas reject additional top-level properties. Here is the shared page-tool contract; individual operations interpret only their relevant fields.

| Tools | Arguments in addition to required `tabID` | Result/behavior |
| --- | --- | --- |
| `list_tabs` | None; no `tabID` | Granted tabs and window IDs. |
| `open_tab` | Required `url`; optional `windowID`; no `tabID` | New shared tab ID and owning window ID. |
| `navigate` | Required `url` | `navigationStarted`, not completed navigation. |
| `read_page` | None | Rendered text up to 50,000 characters, title, URL, `truncated`; form values omitted. |
| `snapshot` | `mode` (`compact` or `detailed`), `offset`, `limit` (up to 1,000), `includeHidden` | `controls`, `frames`, `snapshotID`, pagination/truncation metadata and timing. |
| `click`, `double_click`, `right_click`, `hover`, `move_pointer`, `drag`, `drag_and_drop`, `scroll`, `scroll_element`, `scroll_into_view` | `ref` or selector/role/name/text target; applicable `targetRef`, `dx`, `dy`, `x`, `y`, `inputMode`, `block`, `inline` | DOM-generated pointer/scroll actions by default; `drag`/`drag_and_drop` need a target ref. `inputMode: "native"` uses targeted AppKit delivery for click/double/right-click/hover/move in the selected visible tab, returning unverified dispatch metadata. |
| `fill`, `clear_field`, `type_text`, `select_option`, `set_checked`, `select_radio`, `submit_form` | Target as above; applicable `value`, `values` (string array), `checked` | Changes and verifies supported DOM control state where possible. Password entry is supported while existing protected values remain redacted. File fields require the upload path. |
| `press_key`, `key_down`, `key_up`, `focus_element`, `blur_element` | Target as above; applicable `key`, `modifiers`, `value` | Focus/blur are DOM operations. Keys use targeted AppKit responder delivery in the selected tab of a visible window. Named navigation keys and letter shortcuts are supported; unsupported keys fail explicitly. Native event dispatch does not prove website effects or DOM trust. |
| `find_elements`, `inspect_element`, `get_element_attributes`, `get_element_geometry`, `get_element_text`, `get_element_state`, `get_selected_text`, `get_dom_fragment` | Target as above; applicable `limit`, `offset`, `maxLength` | Bounded DOM inspection with protected field values omitted. |
| `wait`, `wait_for_element`, `wait_for_text`, `wait_for_url`, `wait_for_navigation`, `wait_for_load_state` | Applicable `ref`, `selector`, `text`, `url`, `state`; `timeout` in seconds, default 5, maximum 300 | Condition result or timeout; navigation/loading waits observe browser state and DOM waits observe page changes. |
| `screenshot` | `mode` (`viewport`, `region`, `element`, `full_page`); applicable `selector`, `x`, `y`, `width`, `height`, `maxWidth`, `format` (`png` or `jpeg`), `quality` | Image content. Region/element must be in the current viewport; scroll first. Full page renders via WebKit PDF with a 16-million-pixel bound. |
| `get_console_messages`, `get_javascript_errors` | `enable`, `clear` | Opt-in, bounded page instrumentation. Network data comes from Resource Timing, with no response bodies/status/headers guarantee. |
| `get_network_requests` | `clear` | Last 200 Resource Timing entries; no status, headers or bodies. |
| `inspect_css` | Required `selector`, optional string-array `properties` | Selected computed CSS properties. |
| `inspect_dom`, `get_performance_metrics` | Optional `selector` for DOM | Bounded DOM summary or available Navigation/Resource Timing and DOM counts. |
| `evaluate_javascript` | Required `expression` and `contentWorld` (`page` or `isolated`) | Separately permissioned expression, bounded output; executing code may have page effects. |
| `upload_file` | Required `scopeToken`, `ref` | Activates the referenced file input with native delivery and waits up to 30 seconds for WebKit file selection. Returns `status: "selected"`, `uploadComplete: false`; verify website upload separately. No arbitrary path argument. |

Native browser and library tools use the following exact required arguments. The catalog's descriptions and JSON schemas are authoritative for every connected build.

| Tools | Required arguments | Behavior and limits |
| --- | --- | --- |
| `list_windows`, `list_boosts` | None | Eligible nonprivate windows or Boost metadata without executable code. |
| `get_active_tab`, `list_spaces`, `list_bookmarks`, `list_reading_list`, `list_history`, `list_easels`, `list_downloads` | `windowID` | Browser/window state; `get_active_tab` requires its selected tab to be granted. Collection results use `items`, `offset`, `total`, `truncated` and `nextOffset`; optional integer `offset` and `limit` select a page, default limit 100 and maximum 200. |
| `get_tab`, `get_tab_state`, `get_navigation_history`, `close_tab`, `select_tab`, `duplicate_tab`, `reload_tab`, `go_back`, `go_forward`, `add_bookmark`, `add_to_reading_list`, `get_media_state`, `get_resource_info` | `tabID` | Granted tab actions. Navigation commands report started, not loaded. Media state comes from WebKit when available. Resource memory measurements are explicitly unavailable through the supported inspection surface. |
| `move_tab_to_space` | `tabID`, `spaceID` | Move the tab and revoke its grant. |
| `pin_tab`, `set_favourite` | `tabID`; `set_favourite` also requires `favourite`; `pin_tab` optionally accepts `pinned` (default true) | Update tab organization. |
| `create_space`, `create_easel` | `windowID` | Create native objects. |
| `select_space`, `delete_space` | `windowID`, `spaceID` | Select or delete; deletion refuses a Space that needs the user's confirmation. |
| `rename_space`, `create_pinned_folder` | `windowID`, `spaceID`, `name` | Rename/create within a Space. |
| `list_pinned_folders` | `windowID`, `spaceID` | Folder metadata. |
| `remove_bookmark` | `windowID`, `bookmarkID` | Remove a bookmark. |
| `remove_reading_list_item` | `windowID`, `itemID` | Remove a Reading List item. |
| `get_easel` | `windowID`, `easelID` | Bounded Easel item content. |
| `cancel_download` | `windowID`, `downloadID` | Request cancellation for an active download; does not prove cancellation has finished. |
| `create_boost`, `set_boost_enabled`, `delete_boost` | `domain`; `boostID`, `enabled`; `boostID`, respectively | Separately permissioned Boost changes. Boost updates can include CSS/JavaScript only behind the separate Boost permission. |

Native library mutations require **Allow Native Library Changes**; Boost mutations require **Allow Boost Changes**. Selection, duplication, reload and navigation have no extra native-mutation toggle. `close_tab` requires the native-mutation toggle. Native read results and window listings do not grant access to an unshared page. There is no create-download tool. Use **Approve Upload Files for Active Shared Tab** in Developer settings and copy the returned token. Upload uses a tab-bound opaque scope token from that native user file approval, never an agent-supplied local path; approval allows at most 16 files, expires after ten minutes and is consumed once. The tool attempts native file-input activation; unsupported activation fails explicitly. Confirm the website received the bytes before reporting success.

## Additional native tools

The following tools extend the native reference above. Read descriptors also permit optional integer `offset`, `limit` and string `query`; operations returning a single object may ignore pagination. Mutation fields listed as optional can still be required by the selected operation at runtime.

| Tools | Required arguments | Optional arguments / semantics |
| --- | --- | --- |
| `get_space`, `list_space_tabs`, `list_space_folders` | `windowID`, `spaceID` | Read fields; explicit Space identity. |
| `get_current_space` | `windowID` | Read fields. |
| `create_space_folder` | `windowID`, `spaceID`, `name` | Alias for pinned-folder creation. |
| `rename_space_folder` | `windowID`, `folderID`, `name` | Names bounded to 256 UTF-8 bytes. |
| `move_tab_to_folder` | `tabID`, `spaceID`, `folderID` | Revokes grant after move. |
| `move_tab` | `tabID`, `spaceID`, `area` | Area is `normal`, `pinned` or `favourite`; revokes grant. |
| `rename_tab` | `tabID`, `name` | Name bounded to 512 UTF-8 bytes. |
| `unpin_tab`, `favourite_tab`, `unfavourite_tab` | `tabID` | Organization aliases; native mutation permission. |
| `hibernate_tab`, `wake_tab`, `mute_tab`, `unmute_tab` | `tabID` | Hibernation revokes grant; wake requires a valid grant. Mute verifies available WebKit state. |
| `get_tab_resource_usage`, `get_tab_media_state` | `tabID` | Read fields; memory telemetry remains unavailable without private APIs. |
| `search_bookmarks`, `search_history` | `windowID`, `query` | Read fields and bounded collection output. |
| `create_bookmark` | `windowID`, `name`, `url` | Optional `folder`; safe link URL. |
| `update_bookmark`, `move_bookmark` | `windowID`, `bookmarkID` | Optional `name`, `folder`, boolean `isFavorite`; updates verified. |
| `delete_bookmark` | `windowID`, `bookmarkID` | Removal alias. |
| `list_bookmark_folders` | `windowID` | Read fields. |
| `create_bookmark_folder` | `windowID`, `name` | Native mutation permission. |
| `get_history_entry`, `open_history_entry` | `windowID`, `visitID` | Read fields only for get; opening grants the created tab. |
| `remove_from_reading_list`, `open_reading_list_item` | `windowID`, `itemID` | Remove alias or open and share. |
| `open_easel`, `get_easel_contents`, `add_easel_text`, `add_easel_link`, `add_easel_quote` | `windowID`, `easelID` | Optional `tabID`, `text`, `url`, `prefix`, `suffix`; link needs URL, quote needs granted source tab and valid quote text. Text limited to 8 KiB. Contents has read fields. |
| `get_boost`, `toggle_boost` | `boostID` | Get has read fields; toggle requires Boost permission. |
| `update_boost` | `boostID` | Optional `name`, `domain`, `css`, `javascript`, boolean `enabled`; Boost permission. |
| `get_download`, `open_download`, `reveal_download`, `delete_download`, `wait_for_download` | `windowID`, `downloadID` | Optional numeric `timeout`; get/wait also have read fields. Wait defaults to 30 seconds, maximum 300; native state is polled every 250 ms. Opening/revealing reports requested, not external-app presentation. |
| `get_browser_status`, `get_download_summary`, `get_active_media_tabs` | `windowID` | Read fields and available native state. |
| `search_web` | `windowID`, `query` | Opens through Astra's configured search flow and shares its tab. |

`list_boosts` also accepts optional integer `offset` and `limit`. Native organization and library mutations require the native-mutation control; Boost code and state changes use the Boost control. Lifecycle/media actions have their own model preconditions and can fail when a tab is active, hibernated, or not loaded.

## DOM references and WebKit boundaries

Snapshot controls include role, accessible-name approximation, description, state, frame identity, and (in detailed mode) further attributes and geometry. The result is DOM-derived, not macOS's accessibility tree. It traverses open shadow roots and reachable same-origin frames. An inaccessible frame has explicit status in `frames`; cross-origin control is not implemented through WebKit's public frame-specific execution path. Closed shadow roots remain inaccessible. Collection is bounded; inspect `pagination`, `truncated`, and `frames` rather than treating a partial result as complete.

A `ref` identifies a node within a snapshot and its tab, controller, document, and frame. A fresh snapshot (offset zero), navigation, DOM replacement, ownership change, or revocation expires it. Continuation pages with a positive offset retain the current snapshot identity and previously collected refs. On stale-reference errors, take a fresh snapshot. Selector targeting must resolve unambiguously. The page can change while an operation is suspended; read back state after consequential actions. DOM pointer actions are synthetic (`isTrusted` is false). Keyboard actions and explicit native pointer mode use AppKit responder APIs; their result reports `trusted: null` because DOM trust and user activation have not been established. Sites requiring a trusted gesture or native dialog may still need manual interaction.

Screenshots and visible authenticated content can enter the agent conversation. The endpoint never places its bearer token in page JavaScript. Page content is untrusted. Console and Resource Timing inspection is partial, and page scripts can alter instrumentation. Arbitrary local-file access, native network interception, and complete cross-origin frame automation are not provided by these page tools. Upload is limited to explicit user-selected scopes; download listing/cancellation use Astra's native manager.

## Local verification

The focused HTTP check compiles the production HTTP parser with a minimal driver. On a macOS host with the supported Swift toolchain and Xcode build products, run:

```sh
scripts/check_browser_use.sh /path/to/DerivedData/astra/Build/Products/Debug
```

The deterministic HTTP website lives in `tests/browser-use/site/`; `server.py --ready-file /tmp/astra-browser-use-site.json` starts two loopback origins and writes their URLs and known download checksum. It exercises forms, authentication cookies, frames, dynamic DOM, download bytes, and observable state. The site by itself does not prove that a real MCP client controls Astra. A complete integration run must connect an external client to an explicitly isolated app instance, discover the live catalog, exercise every tool against Astra's real WebKit views, and verify website/browser postconditions. See [architecture](browser-use-architecture.md) for concurrency and validation boundaries.

On Linux, AppKit and WebKit compilation and live browser tests are unavailable. Do not treat syntax inspection, local website checks, or mocked fixtures as a passing macOS build or end-to-end run.

## Troubleshooting and test isolation

Use the copied endpoint and credential from the same running Astra instance. A 401 means the credential was rotated or Browser Use stopped; a 403 means Host or Origin was rejected. A 406 means `Accept` must include both `application/json` and `text/event-stream`. A 415 means the POST needs `Content-Type: application/json`. Modern clients must bind method/name headers to the JSON request and include per-request version/capability metadata. Tool errors are returned inside successful HTTP responses, so inspect `isError` before reading a result.

If a tab is missing, share it explicitly and confirm it belongs to an ordinary nonprivate window. For `busy`, finish or cancel the current operation in that tab. For stale refs, take a new snapshot and target its new ref. For an offscreen screenshot region, scroll first. A timeout result means the condition was not established, rather than that the action succeeded. Verify native input effects on the website. Synthetic input has no trusted activation; use normal Astra interaction if a native dialog or trusted gesture cannot be established.

The real external-client entry point is:

```sh
scripts/test-browser-use-e2e.sh /absolute/path/to/Debug/astra.app
```

It requires macOS and a Debug build. The script copies the app, gives it a unique test bundle identifier, ad-hoc signs the copy, starts the two-origin fixture, and verifies the private handshake against the expected process, run and profile. The DEBUG-only bootstrap requires both the explicit test environment flag and the test bundle prefix. Normal windows in that test process share a nonpersistent WebKit store; private windows use separate nonpersistent stores. The runner never selects an unrelated existing Astra instance. The shell trap terminates started processes and deletes temporary app, handshake and website files.

`tests/browser-use/client/run.py` discovers tools from the real endpoint and must reject any name lacking an executable case. A documented command and an implemented runner do not establish a passing runtime result; record the actual macOS run separately. Local checks and fixture state assertions are useful independent evidence, but are not an Xcode build or production WebKit integration test.

## Transport and output budgets

| Budget | Limit |
| --- | --- |
| HTTP request body | 1 MiB |
| HTTP headers | 16 KiB |
| Concurrent TCP connections | 32 |
| Incomplete request deadline | 30 seconds |
| Complete request deadline | 310 seconds |
| Tool wait timeout | 0–300 seconds; default 5 |
| Structured browser output | 1 MiB |
| Encoded screenshot | 16 MiB |
| Screenshot image pixels | 16 million |
| Full-page PDF data | 32 MiB |
| Full-page source geometry | 40 million CSS pixels |
| Snapshot traversal | 20,000 nodes; at most 1,000 returned controls per page |

Oversized output is an explicit failure; request a smaller collection, region or image width. Browser Use binds loopback only and closes each HTTP connection after its response; connection reuse and request pipelining are not supported.
