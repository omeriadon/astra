# SwiftMath — Astra-local source

- Upstream: https://github.com/mgriebling/SwiftMath
- Revision: `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7` (1.7.3)
- Reason: MarkdownView's math renderer uses SwiftMath's default Latin Modern Math.
- Retained: `latinmodern-math.otf`, `latinmodern-math.plist`, original source and licenses.
- Removed: other math font assets, tests and upstream documentation unrelated to building the package.

The resource bundle must keep the original `mathFonts.bundle` path because
`MTFont.fontBundle` and the SwiftMath font loader resolve it through `Bundle.module`.
If MarkdownView begins selecting additional fonts in the future, update the
resource set together with equation-rendering tests.
