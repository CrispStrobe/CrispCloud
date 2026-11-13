# DOC preview continuation: executed app checks

13 November 2026. The application consumes standalone parser
`e4427725cc720eaefad97c2cb921a6fe1e36749d`, with canonical parser `419864b`
preserved. The app's exact tested source and lockfile hashes are retained in
[source-hashes.json](source-hashes.json). The final placement qualifier was
tested as a working-tree change above `e8e46b5`; these hashes identify those
bytes independently of the subsequent checkpoint commit.

## Executed checks

| Check | Result | Receipt |
| --- | --- | --- |
| DOC story services/widgets, existing Word/localization and actual metafile painting | **42/42 passed** | [app-doc-tests.log](app-doc-tests.log) |
| MBOX/email components and document integration/routing/source | **36/36 passed** | [app-mail-routing-tests.log](app-mail-routing-tests.log) |
| F3 EML/MSG decoded search, cache replacement, bounds, attachments and existing formats | **11/11 passed** | [app-f3-email-tests.log](app-f3-email-tests.log) |
| Focused analyzer over nine app/test paths | **No issues found** | [app-analyze.log](app-analyze.log) |
| Parser mirror sync and runtime-verifier positive/negative controls | **23/23 passed** | [provenance-tests.log](provenance-tests.log) |
| Selected engine test entry after the default-checkout repair | **61/61 passed; zero skips** | [selected-engine-tests.log](selected-engine-tests.log) |

The three Flutter invocations contain **89 distinct tests**, including 18 newly
authored story-projection/service/widget cases. They are not added to the
historical 69-test receipts or the standalone parser's 1,019-test result.
The Node receipt is from the separately identified `ee7531c` tooling checkpoint;
the selected production engines were not modified by the DOC preview work.
Trailing terminal line padding is removed from the copied continuation logs;
their diagnostics and outcomes are unchanged.

The cases exercise real binary DOC/DOT content, six- and linked-textbox fixtures,
generated-label localization without changing source text, hidden/private
anchors and comment descendants, shape visibility without an encoded textbox
ID, explicit unpositioned labels, bounded composition, F3/side preview, clipboard,
and search when returning from Hex. Existing EML/MSG/MBOX checks cover the search
machinery shared by the Office projection.

## Commands

Run with the genuine pinned Flutter 3.47.8 / Dart 3.13.7 SDK and the normal app
dependency graph after `flutter pub get --enforce-lockfile`:

```sh
flutter test --no-pub --reporter expanded --concurrency=1 \
  test/legacy_word_preview_test.dart \
  test/office_preview_strings_test.dart \
  test/legacy_word_document_test.dart \
  test/widget/legacy_word_story_preview_test.dart \
  test/widget/document_preview_review_test.dart \
  test/widget/office_metafile_preview_test.dart
```

The exact file names for the second and third invocations are retained in their
logs. The third command selects `test/widget/extended_format_viewer_test.dart`.
The analyzer covers the nine source/test paths in `source-hashes.json`, excluding
the manifest/lockfile entries. Verifier controls run from `tool/`:

```sh
python3 -m unittest test_sync_legacy_doc_parser test_verify_document_runtime
```

The real source guard also verified **1,500 Office-managed files**, exact
standalone source identity and Git modes. The document-runtime guard verified
**174 runtime, notice, overlay and corresponding-source records**. Their
commands are `tool/verify_office_fidelity.py --legacy-source <parser-checkout>
--require-tracked` and `tool/verify_document_runtime.py --require-tracked`.

## Environment and limits

The initial Flutter invocation stopped in the normal Kindling build hook before
loading tests because its filtered environment did not retain the workspace
Rustup location. The [initial output](native-hook-first-attempt.log) remains
available. Workspace-only launchers then restored compiler/cache/temp locations
and executed the unchanged pinned compilers, preserving arguments and exit codes.
Genuine C and Rust compile/link/run checks also passed under an environment with
only PATH supplied. The subsequent normal Flutter hooks and all tests completed.
No app manifest, SDK, dependency or hook was replaced or disabled. Actual compiler
versions, original distribution checksums and launcher hashes are retained in
[native-toolchain-versions.json](native-toolchain-versions.json) and
[clang-packages.json](clang-packages.json).

The first production web release attempt failed: the optional WASM dry run
returned 247 and the production JavaScript compiler exited -9, without a Dart
source diagnostic. The [complete failure log](web-release-first-attempt.log)
is retained; that signal alone does not establish its cause. A targeted second
invocation uses Flutter's documented `--no-wasm-dry-run` option to run the same
JavaScript release/O4 target without the separate optional WASM diagnostic.
Its result is recorded in `validation.json` when complete. Native Word pagination,
new external DOCX round-trip acceptance, and interactive desktop/mobile WebView
qualification are not inferred from these app tests. The separate completed
[Linux/Chromium receipt](../file-viewer-selected-documents-20261113/ci-ddfd695.json)
retains those checks at their exact source checkpoint.
