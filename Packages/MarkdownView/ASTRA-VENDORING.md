# Vendored MarkdownView

- Source: https://github.com/Lakr233/MarkdownView
- Upstream version: 4.8.2
- Upstream revision: `a95d4e8d570365fde2267e93e64a067b6c5ab363`
- Licence: see `LICENSE` (upstream)

This package is vendored so Astra's MarkdownView dependency can use the locally customised `../SwiftMath` package without conflicting package identities. The sole change to the upstream package manifest replaces the remote `mgriebling/SwiftMath` dependency with `.package(path: "../SwiftMath")`. Astra also patches the inline math and inline code attachment caches to evict on the main actor, including during memory pressure. `MainActorLRUCache` disables the upstream global-queue pressure handler and installs an actor-hopping handler; regression tests cover background pressure delivery and count-based eviction. Upstream's standalone example projects and nonessential repository assets are excluded.

When updating MarkdownView, carry forward the local SwiftMath path and main-actor attachment cache fix and check upstream licence and dependency changes before replacing the snapshot.
