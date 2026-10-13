# Swift 6.4 compiler and strict diagnostics

Astra's first-party targets are compiled with **Swift 6.4** from Xcode 27, using
**Swift 6 language mode** (`SWIFT_VERSION = 6.0`). The compiler version is
not itself a supported Swift language-mode value; `6.4` in `SWIFT_VERSION`
is invalid.

## Enforcement

All five targets (Astra, website template, website installer, website runtime,
updater runtime) opt into:

- `SWIFT_VERSION = 6.0`: Swift 6's concurrency-safety violations are errors.
- `SWIFT_STRICT_CONCURRENCY = complete`: explicit full checking, also implied
  by Swift 6 language mode.
- `SWIFT_STRICT_MEMORY_SAFETY = YES`: diagnostics for unsafe constructs and
  APIs (warnings by design, requiring acknowledgement where appropriate).
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO`: ordinary warnings remain warnings.

At project level, `ENABLE_SECURITY_COMPILER_WARNINGS`,
`CLANG_WARN_SUSPICIOUS_IMPLICIT_CONVERSION`, `CLANG_WARN_OBJC_REPEATED_USE_OF_WEAK`,
and `GCC_WARN_SHADOW` are enabled and
`GCC_TREAT_WARNINGS_AS_ERRORS = NO`. Exclusive-access enforcement is `full`,
while disabling runtime safety checks is explicitly prohibited.

The current `SWIFT_APPROACHABLE_CONCURRENCY` and per-target default actor
isolation settings are retained. The former doesn't disable Swift 6 safety;
it makes safe sequential code easier to express. Third-party packages retain
their own Swift language modes and are not modified.

## No performance-mode changes

Debug remains `-Onone` with Debug diagnostics and testability. Release retains
its existing optimisation, whole-module compilation, stripping, and linking
configuration. We do **not** force Release-style optimisation into Debug or
enable unchecked/unsafe optimisation.

## CI checks

`python3 checks/compiler-safety-settings-check.py` validates the settings
and verifies that the selected Xcode toolchain is Swift 6.4.x. For source-only
configuration checks on a non-macOS host, use
`python3 checks/compiler-safety-settings-check.py --skip-toolchain-check`.

The complete macOS Debug and Release build jobs are responsible for typechecking
the application with the Swift 6 language mode. Do not bypass errors using
`@preconcurrency`, `nonisolated(unsafe)`, or `@unchecked Sendable` without
individual review and a documented, real safety invariant.
