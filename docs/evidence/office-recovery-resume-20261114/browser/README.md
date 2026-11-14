# Browser recovery-copy continuation

The unchanged real Office recovery-copy wrapper and web adapter compile with
Dart 3.13.7. The compiled JavaScript SHA-256 matches the separately retained
successful macOS browser probe exactly. The local browser attempt stopped at
Chromium startup: this sandbox denied its process-singleton socket. No download
or browser assertions executed in that attempt, and no new browser pass is
claimed.

[validation.json](validation.json) binds the commands' source inputs, compiler
output and logs. [compile-receipt.json](compile-receipt.json) records the explicit
package configuration. [dependency-resolution.json](dependency-resolution.json)
verifies all 12 packages in the `universal_html` dependency closure against the
application lock, including archive hashes. This is an SDK-only adapter probe;
the full native application's dependency graph was not resolved here.

The harness now accepts `--packages` for this scoped probe; its default remains
the application's resolved package configuration. Recreate the small dependency
workspace from `probe-pubspec.yaml` and `probe-pubspec.lock`, run `dart pub get`,
then invoke the unchanged acceptance entry point through the repository harness:

```sh
python3 test/support/verify_office_device_export_web.py \
  --dart /path/to/dart \
  --packages /path/to/probe/.dart_tool/package_config.json \
  --chromium /path/to/chromium \
  --output build/office-web-copy
```

`package-config.json` is the recorded environment snapshot; its absolute paths
are not portable. Generate a new package configuration when reproducing.
`acceptance.js.gz` preserves the compiled bytes with a deterministic gzip header.

The Office fidelity workflow now has an independent browser-copy job. It uses
the app's normal dependencies, installed Chromium, and the real download harness,
and uploads compilation/browser receipts even when the job fails. Its acceptance
covers exact downloaded bytes, filename sanitization, caller-byte isolation,
temporary anchor removal and object-URL cleanup. Hosted execution remains a
separate status from this local compilation record.
