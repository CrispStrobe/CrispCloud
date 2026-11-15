# Dependency setup — 2026-11-15

All five dependency graphs resolved successfully using the pinned Flutter 3.47.8 / Dart 3.13.7 toolchain. Application and CLI lockfiles remain byte-for-byte unchanged. Package-local development graphs had no previous local locks; their exact resulting locks, package configuration and graphs are preserved in compressed snapshots. These are setup receipts, not runtime qualification.

| Graph | Resolution | Duration | Declaration | Lock | Receipt under dependencies |
| --- | --- | --- | --- | --- | --- |
| Application | Enforced committed lock | 26.9 s | Unchanged | Unchanged | `06-app-final-locked/receipt.json` |
| CLI | Enforced committed lock | 88.7 s | Unchanged | Unchanged | `02-cli-locked/receipt.json` |
| Office engine | Package development graph | 30.0 s | Unchanged | Created ignored local lock | `04-engine-dev/receipt.json` |
| Office editor | Package development graph | 30.9 s | Unchanged | Created ignored local lock | `05-editor-dev/receipt.json` |
| Embedded parser | Package development graph | 32.3 s | Unchanged | Created ignored local lock | `03-parser-dev/receipt.json` |

The first application attempt (`01-app-locked`) completed its Pub command successfully and retained the committed lock. It overlapped the intended parser git-ref update in the application declaration, so its recorder correctly marks `pubspec_unchanged: false` and does not accept it as a stable declaration resolution. The final application attempt (`06-app-final-locked`) reran on the saved final declaration and passes all stability checks. Both attempts are preserved.

No application dependency declarations were edited by setup. The engine development graph includes the archive development dependency added by canonical-source integration before that graph was resolved. No native hook was disabled, and no GitHub Actions run was awaited.

Native dependency prefetch also passed for the catalogue and the pinned ebook converter using `cargo fetch --locked --target x86_64-unknown-linux-gnu`. Both manifest/lock pairs were unchanged. These receipts are in `native-dependencies/`; prefetch is not a native build or acceptance test.
