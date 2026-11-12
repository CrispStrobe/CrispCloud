# Ebook implementation continuation — 2026-11-12

## Recovery point

The interrupted session's implementation was recovered from remote branch
`feature/ebook-reader-editor`, commit
`e6f98d33c3064a0ba0af778da2b269855a7e8cf9`, based on main
`f8dd29db4a00607513b7f687b21e4dc16e075735`.

The user approved all four proposed stages: package-preserving EPUB editing,
the foliate-js reader, structural and bounded prose editing, and conversion
with evaluation of Kindling export. MPL dependencies are explicitly allowed.
The legacy EPUB text viewer must remain accessible. Save coherent checkpoints
to the remote feature branch throughout implementation; do not wait for final
validation. No merge to main is requested.

## Continuation checkpoint 1

- Preserve contextual OPF, XHTML and NCX namespace prefixes during mutations;
  keep foreign/structured line breaks out of bounded prose editing.
- Preserve valid bundled CSS imports in the reader and normalized EPUB copies.
- Add regression fixtures for prefixed XML and chained imported stylesheets.
- Reader parser smoke suite passes. Full Chromium smoke launch is currently
  blocked by the executor's socket permission restriction, before test startup.
- Dart/Flutter verification is pending SDK setup. These are implementation
  checkpoints, not a declaration that all platforms have passed validation.

## Recovered implementation and verification

Remote checkpoints `cbb31ab`, `ffce45f` and `ae25973` preserve the continuation
work. Draft PR [#53](https://github.com/CrispStrobe/CrispCloud/pull/53) contains
the feature branch. Keep new edits on this branch and checkpoint them remotely.

Implemented since recovery:

- Visible legacy EPUB text fallback, including strict package-load failures,
  pre-existing chapter defects and invalid drafts. Previewing a valid draft uses
  a separate package snapshot; an invalid draft retains the last readable copy.
- Namespace, percent-encoded filename, fragment, nested contents, navigation,
  directory-collision and encryption-classification preservation fixes.
- Reader CSS imports, SVG targets, non-link contents groups, web view lifecycle,
  JPEG bounds and startup/parse deadlines.
- Restored Kindling's upstream CSS parser using the user-approved MPL grants;
  restored nested navigation in the legacy KF7 stream of MOBI exports.
- Native asset dependency tracking and complete Apple deployment versions.
- Exact vendor manifests, patches and notices, including 125 Rust dependencies.
- Scoped native loopback transport settings and the bundled SJCL license entry.
- Editor modal-route close protection, stale preview detection, image-read error
  handling and portable chapter-reader URL/lifecycle fixes.
- Strict serialization of XML namespace declarations and removal of consumed
  Kindle addressing attributes after navigation/resource resolution.
- A complete, portable Kindle-to-editable-EPUB regression gate using actual
  Foliate parsing, normalization, core import, serialization and reopen.

Verification completed:

| Gate | Result |
| --- | --- |
| EPUB core | 30 tests pass; Dart analyzer clean |
| Reader Flutter package | 3 tests pass; analyzer clean |
| Converter Dart/native assets | 17 tests pass; analyzer clean |
| Focused application regression suite | 76 tests pass across editor, chapter reader, edit session, annotations and existing file services |
| Focused application analyzer | No issues in the 8 changed app/session/annotation/license and widget-test files |
| Rust bridge | 4 tests pass; release library/helper build succeeds |
| Independent Kindle smoke | AZW3/MOBI text, Unicode, metadata, no-op/source preservation, navigation and budgets pass |
| Independent Foliate parser | EPUB/FB2/CBZ and generated AZW3/dual-MOBI/legacy-MOBI pass; both decompression paths pass |
| EPUBCheck 5.4.0 | Seven fixtures (new, relocated-package, edited-copy, conversion source and three Kindle imports): zero fatal errors, errors or warnings |
| Actual Kindle-to-EPUB import chain | AZW3, dual MOBI and legacy MOBI preserve source hashes, metadata, Unicode, nested contents, links and non-XHTML asset hashes |
| Vendor/license checks | Reader hashes/notices and converter source/license inventory pass |

The first application web build was terminated with process exit -9 while
app tests and analysis were also running; it emitted no Dart diagnostic. An
isolated release build with the optional Wasm dry run disabled is in progress.

The focused CI workflow covers package preservation, desktop native conversion,
the complete import chain, browser rendering and the app's actual web build.
GitHub runs are queued; these local results do not claim remote CI completion.
Actual Chromium rendering cannot launch in this executor because of its socket
restriction; the dedicated workflow exercises that path on a GitHub runner.

For automated Flutter commands set `CI=true BOT=true` to prevent Flutter's
optional Azure environment-detection request. Suppressing analytics alone does
not disable that probe. A blocked initial invocation was stopped; subsequent
commands explicitly skip the metadata probe using Flutter's supported CI flags.

The existing Linux path is a Flutter chapter reader plus EPUB editing. The
embedded foliate WebView is currently available on Android, iOS, macOS,
Windows and web. Keep this capability distinction explicit.
