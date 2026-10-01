# Desktop browser fixtures

Start the local fixture with:

```sh
python3 tests/browser-fixtures/server.py
```

The server binds to `127.0.0.1`. Its page is `http://localhost:8765`. It does not log request URLs, headers, or bodies. Optional `--cert` and `--key` arguments enable HTTPS using an existing local test certificate.

The page has explicit controls for dialogs, POST/navigation, popups and opener messages, uploads, storage, service workers, cache validation, permissions, screen sharing, passkeys, HTML audio, Web Audio HRTF positioning, and downloads. Nothing requests hardware access until clicked.

Use synthetic test data. Creating a localhost passkey can create an entry in the system credential provider. The range-download link deliberately downloads 256 MiB; the small attachment link does not.

For normal/private isolation, compare the storage values in one normal window and two separate private windows. Closing and reopening a private window must lose its storage. Its completed downloads remain as explicitly downloaded files; its browsing and download records must not enter normal history, sync, or extensions.

For offline behavior, register the worker, reload, and then test a reload with the network disconnected. An exposed API alone is not a passing result. Test registration, actual interception, cache reads, update/unregister, and website-data clearing.

For sharing protection, start screen-only capture, switch tabs, and check that sharing continues. Automatic destructive tab hibernation has been removed; WebKit's native idle policy is retained.

For audio, test the native media controls and the sidebar card. HRTF positioning validates website positional audio. It does not validate Dolby Atmos, fixed AirPods spatialization, or dynamic head tracking. Those require known reference content, supported Apple hardware, and a comparison on the same machine.

For downloaded-file security, inspect quarantine attributes on completed normal, resumed, segmented, and private downloads. Verify that renaming preserves them. Native update installation and notarized release behavior require separate signed-artifact tests.

## Swift checks

`astraInfrastructureTests` is included in the `astra` scheme. It covers atomic snapshots, backup recovery, corrupt/future snapshot preservation, history deletion, private stores/permissions, origin normalization, bookmark interchange, sync tombstones, retention, credential stripping, and rejection of local files/restoration blobs in sync.

The test host skips normal startup restoration, automatic downloads, update checks, and shortcut registration when launched by XCTest. Tests operate on temporary directories and independent private stores.

The app and test bundle have been built through Xcode MCP. The tests and browser fixtures have not been executed against the app; the project's source/build-only verification restriction remains in force.
