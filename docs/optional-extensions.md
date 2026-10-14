# Optional extension sources

Astra does not distribute third-party extension packages. Users opt in from
**Settings → Extensions**, and the official release archives are downloaded,
SHA-256 verified, copied to user Application Support, and enabled only after
permission review.

| Extension | Pinned upstream release | SHA-256 |
| --- | --- | --- |
| uBlock Origin Lite (Safari WebExtension) | https://github.com/uBlockOrigin/uBOL-home/releases/tag/2026.926.2202 | `d37553c11ce52260b67312a2ac72fe12d1ed1eb8365d4f4a27f123682303c78d` |
| Dark Reader (Chrome MV3) | https://github.com/darkreader/darkreader/releases/tag/v4.9.133 | `a5a1a9c78d377fafd8c9190ce9d57b96f89bc95d21f077888601e4c445b20ebf` |

uBlock Origin Lite: GPL-3.0. Dark Reader: MIT. The original license
files are retained in this repository under `docs/extension-licenses/`,
not in the app bundle. Check published updates and verify digests before
refreshing the catalog entries.

Existing user-installed extensions are preserved. Astra does not
automatically fetch previously bundled extensions on upgrade.
