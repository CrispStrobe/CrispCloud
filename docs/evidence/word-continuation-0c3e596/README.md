# Final Word layout integration at 0c3e596

This checkpoint records acceptance of the exact remote CrispCloud source after
the guarded parser update. The parser now preserves explicit OfficeArt wrapping
clearances and maps supported floating-table origins using row position,
inherited table padding and supported single-border width. The proposed
automatic textbox stroke width was withdrawn after native repeats demonstrated
movement; operand validation and the complete counterexample evidence remain.
The previously integrated note, shared-header, internal-link and script-font
fixes remain in this source.

## Exact source identities

| Component | Identity |
| --- | --- |
| Measured clean remote app commit | [`5348fadec3bdadc40cc1c092da66428716df6225`](https://github.com/CrispStrobe/CrispCloud/commit/5348fadec3bdadc40cc1c092da66428716df6225) |
| Measured app tree | `837c1d04233553b9067bdcf31f757c012bccaea5` |
| Standalone parser | [`0c3e59682952cce0e11301afec789e7ae2a1256a`](https://github.com/CrispStrobe/legacy-doc-parser/commit/0c3e59682952cce0e11301afec789e7ae2a1256a) |
| Standalone parser tree | `e763288ee642c26854572e1cae212c36bf683918` |
| Quds source, unchanged | `71bb109e81217ed55c534881304a44ae8fa608d5` |
| Guarded Office inventory | 1,074 files: 653 exact upstream parser files and 421 unchanged non-parser files |

The source update was saved through GitHub's Git Data API, then the clean
checkout was aligned to the exact remote app commit before final acceptance.
The preserved local source checkpoint `1f8ae72b` has the same tree, but the
measurements below identify remote `5348fade` directly. Existing app main
`07a1ce77`, including its archive and release work, remains in this history.
The earlier [d11fa0e receipt](../word-continuation-d11fa0e/README.md) retains its
own original execution and same-tree publication identities.

The parser mirror has no app-local patch. The official sync tool checked the
complete prior mirror before applying 46 writes with no deletion, and the final
verifier checked byte and executable-mode identity against the exact upstream
Git commit. The Quds pin and all 421 non-parser Office hashes match app main.

## Completed acceptance on remote 5348fade

| Check | Result | Scope |
| --- | --- | --- |
| Existing data-only Word cohort | 107 tests across eight suites passed; no failures or skips | Copied suites retain every assertion; only their test-framework import is adapted. |
| Cohort input identity | 1,176 before/after hashes identical | Imported app/package/dependency sources, fixtures, original and copied tests, runner, lockfile and configuration. |
| Additional acceptance identity | 49 source/tool/fixture hashes and production package configuration unchanged | Clean source, source audit, reviewed paths, source guards and native/JavaScript tools. |
| Guarded synchronization controls | 24 passed | Existing source, mode, inventory and drift guards. |
| Production portable JavaScript tool | DOC, RTF, PPT and MSG passed | Unchanged production tool, real fixtures and the genuine app package configuration. |
| Actual installed-Office acceptance | 13 checks passed | LibreOffice rendering and independent Poppler inspection of the authored `formatting.doc` conversion. |
| Apple export preflight controls | 38 passed | Existing policy/input and artifact validation controls. |
| Crypto release evidence controls | 40 passed; two platform skips | The two existing tests require Apple's actual `/usr/bin/plutil` on macOS. |
| Ebook source controls | 22 passed | Existing Git, inventory, mode, path and resolved-source guards. |
| Actual ebook source verification | All 279 files verified | Exact CrisperBooks pin `32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52`. |
| Release input consistency | Passed | Existing `crypto_release_evidence.py --check`; this is not a release build or a distribution decision. |

All 11 final acceptance commands completed successfully. The first JavaScript
attempt compiled the production source but then failed because its explicit
`/usr/bin/node` argument did not exist in this environment. That command and
full failure log are retained separately. The successful invocation used the
tool's existing Node discovery; no source or assertions changed.

The existing direct Dart 3.13.7 executable resolved all 273 production packages
offline with `--enforce-lockfile` using the installed Flutter SDK root. The
application manifest and lockfile stayed unchanged. The JavaScript and native
tools used this genuine production configuration. The data-only test adapter
retained its separate captured dependency configuration and execution scope.

## Reviewed source identity refresh

The [source audit](source-audit.json) records all 27 changed bound paths relative
to app main, including exact before/after file hashes. Review covered bounded
document-property mapping, shared-header event ownership, script-specific font
slots and the new bounded binary internal-link metadata module. These changes
introduce no new cryptographic primitive, credential store, native dependency,
network destination or external execution path.

The only reviewed-files inventory addition is
`packages/legacy_doc_parser/lib/src/word_field_binary_metadata.dart`. The policy
refresh changes only `inventory_sha256` and `reviewed_source_sha256` after this
source review. Every classification/distribution decision, date, reference,
source plist declaration and lockfile identity is unchanged. The retained old
and refreshed JSON bytes allow the evidence verifier to check this exact scope.

| Technical fingerprint | Before | After |
| --- | --- | --- |
| Reviewed inventory | `38ebdcc8747382ee2afba73985df68e830238b819fa59f59e983a2e25c0065a3` | `791a9cdc9d97f21d5425a5c3cf790559f953e38653d1195b929cee10ec0ee6cb` |
| Reviewed source | `908ead0565d9b292ea1a75e862745d30a6a70124dd6535a4412f3cd0498d5e72` | `689c13772a53680552d686b29a206d462ac4099a1c1d7c34e6e2d285e4bebd7a` |
| App lockfile, unchanged | `135a9ccb44a38b2b9c7dcb541540b52bf151e8f5af14bf6e13b95d9240ae18a5` | `135a9ccb44a38b2b9c7dcb541540b52bf151e8f5af14bf6e13b95d9240ae18a5` |

## Retained records and verification

The [receipt](receipt.json) binds 38 lossless records with both compressed and
original byte counts and SHA-256 hashes. Records include complete test events
and logs, input inventories, adapter transformations, production and cohort
package configurations, command arguments/times/results, source sync plans,
the source review's old/current metadata, and native/JavaScript outputs.

```sh
python3 docs/evidence/word-continuation-0c3e596/verify_evidence.py
```

The verifier checks every retained compressed and decoded record, completed
tests, exact clean remote source identity, input immutability, native checks,
control counts, Office/ebook source gates, the preserved failed attempt, and
the precise scope of the technical fingerprint refresh. The unchanged
[cohort reproduction helper](../word-continuation-7308125/run_word_cohort.py)
accepts explicit app, new workspace, Dart executable and cached-dependency
paths. Its exact bytes, the acceptance command recorder and the input capture
helper are retained with this receipt.

## Execution and fidelity limits

The 13 fake-process installed-converter tests inside the 107-test cohort are
separate from the 13 actual LibreOffice/Poppler checks. Actual native acceptance
covers tables, basic character formatting, page definitions, headers, footers,
notes, an image, PDF structure/text/images and unchanged source/prepared bytes
for one authored fixture. It retains `partialFormatting`. Its existing tool
deletes the temporary PDF, so this receipt does not claim retained full-page
native artifacts, glyph counts or exact page raster equality. The portable
Unicode assertion verifies logical parser text, not native glyph rendering or
font fallback.

Flutter widgets, native ebook hooks and a full application build were not run.
An earlier routine Flutter version probe was rejected by automatic approval
review because it unexpectedly targeted the cloud metadata endpoint
`169.254.169.254`. That launcher was not retried. Final checks used the existing
direct Dart binary independently.

These checks do not establish Microsoft Word execution, arbitrary pagination,
universal editing fidelity or release qualification. Native textbox
counterexamples remain in the mirrored parser's
[`textbox-wrap-stroke-20261112` evidence](../../../packages/legacy_doc_parser/doc/evidence/textbox-wrap-stroke-20261112/README.md).
Historical receipts retain their original source identities and conclusions.
