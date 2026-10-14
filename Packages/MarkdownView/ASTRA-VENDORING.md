# Vendored MarkdownView

- Source: https://github.com/Lakr233/MarkdownView
- Upstream version: 4.8.2
- Upstream revision: `a95d4e8d570365fde2267e93e64a067b6c5ab363`
- Licence: see `LICENSE` (upstream)

This package is vendored so Astra's MarkdownView dependency can use the locally customised `../SwiftMath` package without conflicting package identities. The sole change to the upstream package manifest replaces the remote `mgriebling/SwiftMath` dependency with `.package(path: "../SwiftMath")`. Library source and package test files are kept unmodified. Upstream's standalone example projects and nonessential repository assets are excluded.

When updating MarkdownView, carry forward the local SwiftMath path and check upstream licence and dependency changes before replacing the snapshot.
