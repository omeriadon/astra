# Desktop release pipeline

The release-branch convention and merge trigger remain unchanged. Pull requests compile an unsigned archive without distribution credentials. After a release PR merges, publication requires a Developer ID archive/export, signed-capability validation, accepted notarization of the app and DMG, stapled tickets, and a signed Sparkle update archive. There is no ad-hoc production fallback.

The pipeline follows [Sparkle's distribution guidance](https://sparkle-project.org/documentation/) and [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). Xcode handles nested helper signing during distribution export; the workflow does not recursively re-sign the app or replace generated entitlements with the source plist.

## Required repository secrets

| Secret | Content |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded PKCS#12 export containing a Developer ID Application certificate and its private key. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password protecting that PKCS#12 export. |
| `DEVELOPER_ID_PROFILE_BASE64` | Base64-encoded Developer ID provisioning profile for Astra's explicit bundle identifier and capabilities, including Sign in with Apple. |
| `APPLE_TEAM_ID` | The certificate/profile's Apple developer team ID. |
| `APPLE_NOTARY_KEY_BASE64` | Base64-encoded App Store Connect API private key (`.p8`) authorized to use notarization. |
| `APPLE_NOTARY_KEY_ID` | API key ID. |
| `APPLE_NOTARY_ISSUER_ID` | API issuer ID for a team API key. |
| `SPARKLE_PRIVATE_KEY` | Existing Sparkle Ed25519 private signing key matching the app's public key. |

No credentials were created, retrieved, or installed by this implementation. Missing credentials cause publication to stop before archiving. Secrets are passed through environment variables, not interpolated into shell source. Credential-command output is withheld on failure. A temporary keychain and profile are removed in an always-run cleanup step, and the original keychain search list is restored. Release jobs are serialized on the runner.

## Failures that intentionally block publication

The signed app must retain sandboxing, outgoing networking, Downloads access, camera/microphone/location access, persistent file bookmarks, Sign in with Apple, and Sparkle's installer Mach-lookup permissions. It must have Hardened Runtime, a secure signing timestamp, the expected developer team, an HTTPS Sparkle feed, a valid-length Ed25519 public key, download quarantine, and web-content-only ATS exceptions. A debugger entitlement or global native ATS exception is rejected.

The Xcode entitlement integration previously rejected the bookmark and Sparkle Mach-lookup keys. No manual workaround was added. If an exported app still lacks those permissions, artifact validation will reject it. Signing credentials alone do not resolve that gate.

The artifact validator includes a stdlib self-check used by PR validation. It checks that missing permissions, development signatures, incorrect teams, disabled quarantine, insecure feeds, and global ATS exceptions are rejected. This implementation was checked locally through Python source parsing and workflow YAML/shell syntax inspection. The production archive, export, credential operations, notarization, publication, and updater were not executed.

## Distribution acceptance still required

An actual signed release must pass fresh-Mac Gatekeeper launch, offline stapled-ticket launch, normal/private session recovery, security-scoped file reopening, and a sandboxed Sparkle update from an older signed build. Invalid update signatures and canceled/failed updates must preserve the installed app and browsing data. The configured minimum OS and system WebKit version must also be tested; this pipeline does not establish browser compatibility or spatial-audio/Web Push support.
