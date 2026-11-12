# Gap closure validation — 12 November 2026

[Gap register](README.md) · [Current capability audit](../file-manager-capability-audit.md).

## Scope and checkpoint

The requested feature inventory is consolidated into 51 stable gaps across six
lanes. Each scope has implementation boundaries, dependencies, acceptance
criteria and source starting points. Eight implementation increments have been
preserved remotely. Five scopes are closed; three features are implemented with
named target-runtime acceptance pending. There are 31 scoped implementation
items, ten research items and two cross-cutting acceptance items still open.

The complete implementation stack is present at code checkpoint
`ebede8d596e8a5f83cf78ccd420573505a2e4531` on
`feature/file-conversion-20261112`. Later documentation-only checkpoints record
this evidence without changing the compiled implementation.

## Remote checkpoints

All pull requests below are drafts, open and unmerged. Each branch is stacked on
the preceding branch. The first scope branch builds on the earlier feature
implementation branch. Updates preserve previous commits and use fast-forward
leases; no main-branch merge or deployment is part of this work.

| Scope | Remote branch | Checkpoint | Review |
| --- | --- | --- | --- |
| All 51 gap scopes | `feature/file-manager-gap-closure-20261112` | `9887b53` | [PR #58](https://github.com/CrispStrobe/CrispCloud/pull/58) |
| G03 conflict previews | `feature/conflict-review-20261112` | `132f70e` | [PR #59](https://github.com/CrispStrobe/CrispCloud/pull/59) |
| G12 external terminal | `feature/external-terminal-20261112` | `f798f27` | [PR #60](https://github.com/CrispStrobe/CrispCloud/pull/60) |
| G01 incoming drops | `feature/incoming-drop-routing-20261112` | `a452b7a` | [PR #61](https://github.com/CrispStrobe/CrispCloud/pull/61) |
| G02 direct Quick Open | `feature/quick-open-actions-20261112` | `baccf47` | [PR #63](https://github.com/CrispStrobe/CrispCloud/pull/63) |
| G37 FTP transport lifetime | `feature/ftp-transport-lifetime-20261112` | `c8f4561` | [PR #64](https://github.com/CrispStrobe/CrispCloud/pull/64) |
| G04 configurable menus | `feature/configurable-menus-20261112` | `55dd210` | [PR #65](https://github.com/CrispStrobe/CrispCloud/pull/65) |
| G27 SOCKS4/4a HTTP routing | `feature/socks4-http-routing-20261112` | `42ae79c` | [PR #66](https://github.com/CrispStrobe/CrispCloud/pull/66) |
| G13 file conversion | `feature/file-conversion-20261112` | implementation `ebede8d` | [PR #67](https://github.com/CrispStrobe/CrispCloud/pull/67) |

## Automated gates

Toolchain: Flutter 3.47.8, Dart 3.13.7; Linux test host. These are separate gates,
with overlapping suites. Their counts must not be summed as unique tests.

| Gate | Observed result | Evidence covered |
| --- | --- | --- |
| G03 conflict review | 140 passed across four suites | Bounded real image decoding, original-source validation, safe metadata, cancellation, conflict choices and enlarged localized layouts |
| G12 terminal preferences and existing terminal/settings behavior | 45 passed across five suites; one existing macOS-only skip | Literal arguments, stale preparation, local grants, executable/path errors, persistence and disposal; later argument-bound fixes also passed in the 118-test gate |
| G01 incoming drops plus terminal-service regression | 118 passed across seven suites | Actual pane routing, secondary remote destinations, native/browser source adapters, bounded streams, directory hierarchies, cancellation and source release |
| G02 Quick Open/navigation/rename plus conversion regressions | 193 passed across 12 suites | Saved-item identity, unavailable targets, noninteractive tab restoration, newer pane intent, preset review, keyboard activation and translated layouts; conversion was subsequently extended and rerun separately |
| G37 FTP transport lifetime and transport regressions | 145 passed across nine suites | 24 native lifetime cases observe peer closure during stalled control/data TLS, pending login, deadlines and owner close/logout; FTP/SOCKS/TLS regression coverage |
| G04 menus and screen integration | 96 passed across 11 suites | Schema/import bounds, serialized persistence/recovery, command context, real-screen registry, native editor/terminal ownership, keyboard/toolbar/header compatibility, translated narrow layouts and SQLite runtime |
| G27 final proxy/security regression | 197 passed across six suites | SOCKS4/4a and existing SOCKS5 wire/TLS behavior, DNS choices, fragmented/coalesced replies, 2 MiB streams, peer closure, late lookup cancellation, settings and embedded-NUL host validation |
| G13 final conversion regression | 80 passed across three suites | Independent vectors, all-byte/chunk boundaries, strict filenames/headers, source mutation, staged corruption, cancellation, exclusive publication, real local-filesystem roundtrip and localized UI |

Independent code review accompanied the implementation gates. The final reviews
found no remaining concrete issue in the reviewed changes. New implementation
files passed focused analysis; findings in touched pre-existing files remain
reported rather than treated as a lint-clean application.

### Test-environment correction

The menu screen gate initially failed before tests because an existing SQLite
native-asset download failed its checksum. The repository's existing opt-in
`tool/with_ci_system_sqlite.py` helper was used with the installed Linux library,
including the existing SQLite runtime probe. The helper restored the original
package configuration. Release dependency verification was not weakened.

The final conversion dialog regression initially waited on a completion future
created in Flutter's fake asynchronous zone from `tester.runAsync`. A diagnostic
comparison showed that the real service had already returned the required
malformed-input error. The observer is now created under real asynchronous
scheduling; the final test still asserts the precise error, unchanged input,
zero staging/publication and zero selection-memory writes. No production logic
was altered to accommodate that test-harness correction.

## Full analysis and release compilation

`flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos` completed with
**0 errors, 96 warnings and 1,038 informational findings**. This matches the
repository's error gate; it does not claim that all lint findings are resolved.
The final focused conversion analysis also confirmed no findings in its new
files; three unused-import warnings and two style findings remain in the
pre-existing context-menu file.

The JavaScript release build completed successfully in 200.1 seconds:

```sh
flutter build web --release --no-pub \
  --dart-define=APP_VERSION=1.1.0+12 \
  --dart-define=GIT_HASH=ebede8d
```

The optional WebAssembly dry run exited **247**. This repeated the earlier
checkpoint's outcome. The JavaScript build still completed; WebAssembly remains
unvalidated under G51. The exit code alone does not establish a particular
resource or dependency cause. A compilation result does not establish actual
browser permission, drag/drop, provider or keyboard behavior.

At the final review inspection, the feature pull requests were open, draft and
unmerged, and hosted workflow checks were queued. Hosted CI success is not
claimed here. `git diff --check` passed. The 51 scope headings are unique and
consecutive, relative document links resolve, and the changed-file naming scan
found no competing product names.

## Remaining acceptance boundaries

- **G01:** actual operating-system drag sessions, signed macOS access scopes and browser directory handles.
- **G04:** actual native menu presentation and keyboard dispatch on supported platforms.
- **G12:** launching installed terminal applications and verifying their working folder on each claimed desktop OS.
- **G13:** native macOS grant behavior; MIME multipart/quoted-printable/continuations and browser-local exclusive output remain outside the delivered format/storage scope.
- **G27:** live proxy/server configurations and target-platform acceptance; direct FTP/SSH/SMB proxy routing is G28.
- **G37:** generic queue stop before an upload subscribes or asynchronous read setup completes can still wait for the owned transport deadline; see the [FTP API boundary](../ftp-transport.md).
- **G50/G51:** signed application, live-provider and browser-runtime acceptance, plus successful WebAssembly build/runtime evidence.

No new third-party dependency was introduced in these eight increments. Existing
permissive dependencies and first-party implementations are retained; new
dependencies in future lanes still require version/provenance and license review.
