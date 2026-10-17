# Sync and conflict resolution

[Wiki home](index.md)

Astra keeps a local cache and synchronizes a versioned `BrowserSyncDocument`.
The client merges documents; the server stores one snapshot per Apple subject
and device ID. A server revision is transport metadata, not the winner for
every individual browser item.

## Merge rules

Stable IDs identify records. Modification timestamps choose between competing
versions of tabs, bookmarks, reading-list entries, history, spaces, and
portable settings. Timestamped deletion records prevent older snapshots from
resurrecting deleted data. Workspace ordering and selection have their own
merge handling. New fields must preserve backward decoding and deletion rules.

Before uploading, the projection removes local-only tab state, file-access
bookmarks, peeks, restoration data, and nonportable URLs. It strips URL
credentials. Only allowlisted preferences may leave the device.

## Request flow

After hydration, the signed-in client fetches snapshots, validates their
structure, merges them with local data, protects edits made while
the request was in flight, persists the result, and uploads its current device
snapshot when needed. Generation and endpoint checks reject stale account work.

Sync does not reject documents because of their version marker. The server
returns marker `1` for installed clients that still check it, while preserving
stored payloads and all other fields. Unknown fields are ignored by the client;
incompatible field types and invalid structures still fail validation.

Transient GET/PUT failures can retry. Authentication and AI POST requests do
not automatically retry. Offline browser data remains local; a sync error is
not an instruction to clear it.

## Payload limits and large accounts

The client and server enforce **5,000,000 bytes of raw JSON per device snapshot**
(not 5 MiB or 16 MiB). Before each PUT, the client serializes the portable sync
document off the main actor and checks its actual encoded byte count. The server
also enforces this limit. The full PUT envelope is also encoded and checked off the main actor before network I/O. The JSON PUT envelope carries the payload as Base64:
a maximum-size snapshot encodes to 6,666,668 Base64 bytes, plus a small JSON
wrapper, within the server's **7 MB collected request-body limit**.

A document above 5,000,000 bytes is not truncated, silently dropped, or
partially uploaded. Sync displays an explicit size error; all local data remains
intact, though the oversized snapshot cannot upload until it is reduced or the
server protocol is expanded.

GET /v1/sync returns **all device snapshots** in one Base64-encoded JSON array.
The client allows at most **64 MiB** for this aggregate sync response while
retaining the **16 MiB** cap on other HTTP responses. Each decoded device
snapshot is independently checked against the server's 5,000,000-byte limit
before it can be merged. Extremely large multi-device accounts may still hit
the aggregate GET limit; this endpoint has no pagination.

The regression check covers realistic large tab, bookmark, reading-list,
history and deletion-record sets; exact byte-limit boundaries; Base64 request
overhead; and multi-device response sizes. An HTTP 413 indicates the server
rejected the request, not that Astra may discard its local cache.

Related: [authentication](authentication.md), [settings](settings-and-search.md).

## Source entry points

- [BrowserSyncDocument.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Models/Core/BrowserSyncDocument.swift)
- [BrowserSync.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/Storage/BrowserSync.swift)
- [routes.swift](https://github.com/omeriadon/browser_server/blob/2b6d5583994b3d4c6a5b1e417b7e8088cbc925d5/Sources/brower_server/routes.swift)
- [SyncSnapshot.swift](https://github.com/omeriadon/browser_server/blob/2b6d5583994b3d4c6a5b1e417b7e8088cbc925d5/Sources/brower_server/Models/SyncSnapshot.swift)
