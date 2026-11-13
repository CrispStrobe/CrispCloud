# Canonical parser and Office refresh qualification

This is a new local qualification of CrispCloud commit
`a065ee6e7c2aa18574a72ac6232d4d01845bdee9`, using parser
`0f9f085f2c0d38d540ea31622edc4a1609ec4ae7` and Quds
`05a581de9526dba2e7fffff68d56dab9180bbd2d`. The checks ran in an isolated
checkout; no canonical source, tracked app manifest, lockfile or test was changed.

## Source and ancestry

The Office source guard passed before and after execution against immutable Git
objects from the canonical repositories: 1,925 managed files, comprising 1,497
parser files and 428 Quds files. Parser bytes and Git executable modes match its
canonical pin. Quds bytes match its canonical pin. An additional mode audit found
34 Quds Dart files with app mode `100755` and canonical mode `100644`; all 34
differences already existed before this refresh. The Quds synchronizer's contract
checks file bytes. No new mode difference was introduced or normalized here.

The previous parser pin `840f8af1f645cd6ed85277ba6e619dc120d99277` is an ancestor
of the new pin by 13 commits. Previous Quds pin
`e82c997b6df8746fe86fb83b9f416a89bb3e3b80` is an ancestor by seven commits.
The manifest SHA-256 is
`410ef9a5abe63816c52595669b314eb02872163a13e77a4398193df9335d98af`.
`source-boundaries.json` records exact revisions, changed runtime paths and counts.

The parser changes touch six library files: early UTF-16 validation, bounded
inspection of actual compound-container bytes before OLE/VBA activation, literal
and ancestor numbering-label handling, and preservation of tab characters in
numbering XML attributes. The Quds runtime changes touch two editor files: loaded
font fallback selection and bounded shortcut text in context menus. The Quds
engine runtime is unchanged; its conversion regression now expects invalid UTF-16
to fail at parser entry.

## Results executed for these pins

| Gate | Result |
| --- | --- |
| Complete parser Dart suite | 1,422 passed |
| Parser Python oracle controls | 184 passed |
| Actual Dart-to-JavaScript compilation and Node execution | 18 acceptance groups passed |
| Complete parser strict analyzer | No issues |
| Changed Quds and app-host behavior | 16 focused tests passed |
| Engine legacy Word conversion | Seven tests passed |
| Changed editor files/new fallback test and engine conversion test, strict analyzer | No issues |
| Immutable-source guard before and after execution | 1,925 files verified |

These are separate gates; their numbers are not added to historical runs. The
JavaScript gate includes the new text-Unicode and public compound-container
controls, as well as existing CFB, media, field, numbering, ink, symbol and
font-charset acceptance. It executes compiled JavaScript under Node; it does not
qualify a browser renderer or WebAssembly build.

The 16 host tests cover explicit loaded/unloaded font fallback, host font
registration, note editing, the app's font asset registration, and missing-font
preview fallback. The included qualification-only probe exercises the actual
public context menu at 320 by 480 logical pixels in both LTR and RTL: the long
bilingual label stays hit-testable, the menu stays within the window, and a tap
selects the action and dismisses the menu. Its third test checks actual Calibri,
Carlito and Roboto registration and unknown-face fallbacks. The probe source is
included in the archive and was not added to a canonical package.

## Runtime resolution and reproduction

Flutter 3.47.8 / Dart 3.13.7 and Node 24.22.1 were used. Parser and engine packages
were resolved independently for their development test runners, then only their
generated package configurations were aligned to the app's complete reachable
runtime dependency graph. In particular, both used the app's `archive 4.6.0`,
`path 1.9.1`, `posix 6.5.4`, `meta 1.19.0` and `ffi 2.2.0`. Direct resolved
`test 1.33.0` runners prevented automatic Pub re-resolution during Dart tests.

The archive contains the exact app/parser/engine package-config snapshots,
runtime-resolution reports with dependency versions and pubspec hashes, the
qualification-only probe, command records, environment versions, and the local
native profile scripts. Config snapshots contain workspace paths; regenerate or
rebase them when using a different checkout. After resolving the app from its
lock and each pure Dart package normally, `align_runtime_resolution.py` reproduces
the runtime-graph alignment without editing tracked manifests. Invoke it for
`packages/legacy_doc_parser` and `packages/quds_office_engine`, then run the
commands recorded in `commands.json`. The app's registered assets are required
for host tests, so run those from the app checkout with its package configuration.

The local native host profile temporarily disables the optional native ebook
hook, uses verified system SQLite and the repository-pinned libsmb2, and restores
the app manifest and lock byte-for-byte. This qualification does not cover native
ebook conversion. The exact profile scripts are retained for inspection; their
referenced toolchain/native library files must be provisioned separately.

## Corrected setup attempts and evidence boundaries

The first host command also passed the pure-Dart engine test to the Flutter app
runner, whose package configuration does not contain `package:test`. The engine
test failed to load; the other 16 host cases passed. Its matching analyzer attempt
reported missing-test cascade errors. The corrected host gate passed separately,
and the engine's seven cases passed using its own test runner and the app runtime
graph. Initial offline engine resolution could not find uncached `lints ^6.0.0`;
normal resolution succeeded without altering constraints. Those initial logs are
retained and are not presented as product failures or successful gates.

The Python controls deliberately exercise compile/schema failures and then
finish `OK`. The host missing-font regression deliberately emits an asset warning.
These expected negative-control messages remain in the raw logs.

No new Open XML SDK, Word, LibreOffice, platform golden, device, full app-suite or
release-build acceptance is claimed here. Upstream `docs/integration-20261113.md`
attributes its larger Office gate to an earlier runtime before final font/menu
and screenshot reconciliation. The two changed note goldens retain upstream
source run `43416958976` and source commit `e82c997b...`; they were not regenerated
or relabeled by this qualification. Earlier parser receipts, including the
1,361-test integration receipt and fourth-pass source-specific evidence, retain
their original source attribution. The new 1,422-test result above was rerun at
the exact current pin.

The immutable parser includes a historical extra EOF blank line in
`doc/evidence/independent-acceptance-1b8cc9e2/seal_validation_evidence.py`;
canonical bytes were preserved. No new material source-integration defect was
found in this scoped qualification.
