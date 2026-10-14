# Website apps and Mini Astra

[Wiki home](index.md)

Mini Astra is a compact browser surface. Standalone website apps use a helper
application with a Mini-style browser and a toggleable top bar. These are
native wrappers around websites, not proof of Safari-equivalent installed-PWA
capabilities.

## Installation records

`BrowserWebsiteAppRegistry` owns installations under Application Support's
`Astra/Website Apps` directory and writes `registry.json` atomically. Each
installation has a stable ID, launch URL, bundle path, and timestamps. Names
and URLs are bounded and validated; URLs must be credential-free HTTP/HTTPS.

Installation requires the bundled `AstraWebsiteAppTemplate.app`. Missing or
invalid templates and local-signing failures are explicit errors. Uninstall,
rename, reveal, and updates check that the target remains inside the owned
installation directory, including resolved filesystem paths.

Launch Services registration must **not** happen inside Astra's sandboxed file
worker. macOS can return `-10819` (`kLSNotRegisteredErr`) for
`LSRegisterURL` from a sandboxed process. The worker only stages, signs,
publishes, and persists generated bundles. Astra then invokes the separately
signed, non-sandboxed `AstraWebsiteAppInstaller.app` with `--prepare`;
that helper validates the canonical installation path and bundle signature,
removes quarantine from the bundle and executable, and registers the final
published path via `LSRegisterURL`. `--pin` also verifies and registers
before editing Dock preferences. Renames and icon updates re-register via the
helper, while launches repair and register older generated apps.

New installs are rolled back if preparation/registration fails. If rollback
itself fails, the registry keeps the installation visible for recovery rather
than silently hiding its on-disk record. Runtime registration and Dock behavior
require an interactive macOS test; source-level checks cannot prove them.

The helper's menu maps Command-S to top-bar visibility. Launching a helper,
placing it in the Dock, and keeping it permanently in the Dock are distinct
operations. The existing flow directs the user to the normal Keep in Dock
operation rather than promising automatic permanent pinning.

## Boundaries to preserve

The website-app window uses `Browser(isMini: true)`. Mini excludes normal
window persistence and sync, but it is not synonymous with private browsing;
its web session still follows the running helper's normal-session setup.
Do not infer shared or isolated account cookies without checking the helper's
bundle and data-store behavior on the target OS.

Generated bundles, helper signing, sandbox permissions, fresh-Mac launch, and
Dock persistence require distribution/runtime acceptance beyond source review.

Related: [architecture](architecture.md), [releases](releases-and-updates.md).

## Source entry points

- [BrowserWebsiteAppRegistry.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/App/BrowserWebsiteAppRegistry.swift)
- [BrowserWebsiteAppHelperMain.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/App/BrowserWebsiteAppHelperMain.swift)
- [BrowserWebsiteAppWindowController.swift](https://github.com/omeriadon/astra/blob/8652ae2c4d060b43169e151901b46749af66b632/astra/UI/Shell/BrowserWebsiteAppWindowController.swift)
