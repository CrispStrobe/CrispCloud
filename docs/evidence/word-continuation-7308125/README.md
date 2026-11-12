# Word continuation acceptance at parser 7308125

This directory retains the app validation performed on clean CrispCloud source
[`5e1adcdbcdc6763e3eeb86a4632821c2b53a8c37`](https://github.com/CrispStrobe/CrispCloud/tree/5e1adcdbcdc6763e3eeb86a4632821c2b53a8c37),
after the final parser mirror was installed. Adding this receipt changes
documentation only; the recorded execution remains attributed to that source
commit. The machine-readable [receipt](receipt.json) binds the source pins,
selected tool and fixture hashes, SDK identity, and every retained artifact.

## Exact source boundary

| Input | Recorded identity |
| --- | --- |
| CrispCloud source | `5e1adcdbcdc6763e3eeb86a4632821c2b53a8c37` |
| CrispCloud Git tree | `a32e479c9ef4a88e839c168c408ecace0cd1bb4f` |
| Standalone parser | `730812534e8dc045d6d97f600218228f05c51b97`, with no app-local patches |
| Quds source | `74960237cea7c560f3db7ee96ca37641c4438567`, unchanged |
| Guarded Office inventory | 823 managed files: 402 parser source files and 421 unchanged non-parser files |
| Dart | 3.13.7 stable, Linux x64 |
| Dart executable SHA-256 | `01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb` |

The parser mirror matches its standalone Git tree. The 421 non-parser Office
hashes match the preceding app source at
`3f9d2c16654366679ad71f132a60587bc46cecb4`; the Quds pin is unchanged. App-owned
`UPSTREAM.json` is metadata, separate from the 402 parser source files.
The authoritative declarations remain the app manifest, parser upstream record
and dependency pin at the recorded source commit. Their actual byte hashes are
included in the receipt.

## Completed checks

| Check | Recorded result | Scope |
| --- | --- | --- |
| Data-only app Word cohort | 107 tests across eight suites passed; no failures or skips | Existing assertions run under `package:test` with one test-framework import replacement per copied suite. |
| Portable JavaScript smoke | Four formats passed | DOC formatting/tables/sections, current PPT slides, RTF Unicode/formatting, and MSG RTF decompression/CRC. |
| Installed native Office check | 13 checks passed | Actual LibreOffice conversion plus independent Poppler checks on `formatting.doc`. |
| Source-sync controls | 24 tests passed | Existing guarded parser/Office synchronization tests. |

The eight-suite cohort ran from 20:26:36 to 20:26:44 UTC on 2026-11-12. Its
before/after inventories are byte-identical and bind 1,170 source, dependency,
fixture and configuration files. They include the original and adapted tests,
the transitive Dart import/export/part closure, runner configuration, parser
metadata and Office manifest. The SDK executable hash is recorded separately.
This is a scoped execution inventory, not an inventory of every installed SDK
file or system library.

| Suite | Passed tests |
| --- | ---: |
| `word_conversion_inspection_test.dart` | 43 |
| `legacy_word_structured_conversion_test.dart` | 9 |
| `legacy_word_structured_document_test.dart` | 16 |
| `legacy_word_structured_render_test.dart` | 7 |
| `legacy_word_structured_bounds_test.dart` | 4 |
| `legacy_word_sprm_regression_test.dart` | 6 |
| `legacy_word_document_test.dart` | 9 |
| `installed_office_converter_test.dart` | 13 |
| **Total** | **107** |

The 13 installed-converter tests in this cohort use fake local processes to
exercise policy and bounds. The separate `native.json.gz` records **13 actual
LibreOffice/Poppler checks**; those are a different result, not a second
description of the fake-process tests. The native and portable JavaScript
checks ran on the same clean app commit named above.

The actual native checks cover table/cell structure, bold, font size and color,
page dimensions, headers/footers, notes, an image, independent PDF information,
text and image extraction, and unchanged source/prepared-package bytes. The
native report retains the `partialFormatting` limitation. Its input SHA-256 is
`0ad636c6e3597152313055fd5428fb4b70ab483b3853b2666cac52498c953026`;
its prepared DOCX SHA-256 is
`cb93a3753a2f256c7bc09ecb08cb754278d18b21e4d7870bb1e28b194740d093`.
The original report does not inventory renderer executables, fonts or shared
libraries, and the temporary rendered PDF was not retained. The receipt binds
the actual verification tool bytes and source fixture without adding an
unrecorded renderer identity claim.

## Regression counterexamples

`before-anchor-fix.log.gz` retains nine failing negative controls against the
inspector from app `7d11559a8e086af829725c1c21180ff93051e5e2`, alongside 32
passing tests. That earlier 41-test run predates the Office Math positive case
and the nested-comment follow-up. The controls demonstrate that unused parts,
unused definitions or invalid anchor relationships previously cleared
conversion-loss warnings.

`before-nested-comment-fix.log.gz` retains the additional failing control
against app `b2cf42668102f9cda09e26de9420c319eef91e90`: a reference inside an
attached comment incorrectly attached a second comment and its embedded object.
The final 43-test inspector suite rejects that chain while accepting a direct
valid comment anchor to the object-bearing comment.

The resulting inspector establishes the presence of an anchored feature
category. It does not establish complete feature-count equivalence, full XML
schema validity, Markup Compatibility branch selection, semantic preservation,
or rendering fidelity. See the [conversion guide](../../legacy-word-conversion.md)
for the current behavior and bounds.

The parser's proposed textbox-depth runtime reset was disproved by native
geometry and **retracted before this parser pin was integrated**. This receipt
does not claim that reset as a runtime improvement. The retained upstream
counterexample and parser-specific validation belong to the parser's own
source-attributed evidence; this app receipt does not relabel those checks as
app executions.

## Retention and verification

All 15 captured records are retained in full as lossless gzip files. The
receipt records both compressed and original byte counts and SHA-256 hashes.
They include the complete cohort JSON event stream and expanded log, result
summary, exact adapter manifest, before/after input inventories, original
runner, dependency manifest/lock/configuration, both pre-fix failure logs, and
the native, portable-web and synchronization results. Compression does not
remove failed assertions, timestamps or historical paths.

Run the verification helper from the app checkout:

```sh
python3 docs/evidence/word-continuation-7308125/verify_evidence.py
```

To verify and losslessly extract the records into a new directory:

```sh
python3 docs/evidence/word-continuation-7308125/verify_evidence.py \
  --extract /path/to/new-evidence-directory
```

The helper checks every artifact's raw and compressed hash, both helper hashes,
the original summary's file hashes, identical before/after inventories,
captured runner/configuration identities, cohort completion, and the native
fixture identity. The helpers themselves are hash-bound in `receipt.json`.

## Reproducing the data-only cohort

Use a checkout of the recorded app source, an existing Dart 3.13.7 installation,
Python 3.10 or later, and a pub cache containing the locked dependencies. Keep
this evidence directory available separately if checking out the earlier
runtime commit, because the evidence was added afterward. Then run:

```sh
python3 /path/to/word-continuation-7308125/run_word_cohort.py \
  --app /path/to/CrispCloud \
  --workspace /path/to/new-word-cohort \
  --dart /path/to/dart \
  --pub-cache /path/to/existing-pub-cache
```

The workspace must not exist. The helper creates the copied tests, unchanged
source/support/fixture symlinks, its own temporary directory, and a new package
configuration. It resolves dependencies offline using the captured lockfile,
adapts only the `flutter_test` import, and writes new full records under
`results/`. No application source or dependency manifest is edited. Missing
cached dependencies cause offline resolution to fail; the helper does not fetch
them or invoke the app's native build hooks.

The original captured runner and package configuration retain the historical
absolute paths as evidence. The reproduction helper accepts explicit paths and
regenerates its configuration; those historical paths do not need to exist.
Its own runner/configuration hashes and timestamps will differ from the
original capture and are recorded afresh.

## Remaining scope

This data-only adapter does not run Flutter widgets or a complete application
build. `legacy_word_previous_regressions_test.dart` was excluded because its
preview imports require Flutter material/services and `video_player`; no
assertion was stubbed to include it. The JavaScript smoke is not a complete
Flutter browser build. The native check covers one authored DOC fixture and
does not establish Microsoft Word execution, universal layout equivalence or
editing fidelity.

These development checks do not requalify a frozen release. Release,
distribution and fingerprint policies are unchanged, and earlier receipts
retain their original source identities.
