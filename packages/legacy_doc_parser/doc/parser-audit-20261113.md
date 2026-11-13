# Parser audit — 13 November 2026

This audit starts from `c1b3ec5b685bfebb9199684ceb35b4c9f231ef7a` and checks
binary input bounds, text extraction, compound-file identity/size handling,
field conversion, aggregate ink inspection, and the VM/JavaScript boundary.
The complete implementation was tested in a clean checkout of
[`92486f82dd746ab14b5ccf1310f629b74f7bfa5a`](https://github.com/CrispStrobe/legacy-doc-parser/commit/92486f82dd746ab14b5ccf1310f629b74f7bfa5a).
Subsequent workflow and evidence changes do not change those parser, test,
fixture or conversion-tool bytes.

Changes were saved incrementally to `fix/parser-audit-20261113`, with a
separate remote commit for each implementation group. This work does not roll
the parser pin in downstream applications or publish a package release.

## Findings and fixes

| Area | Reproduced gap | Correction and regression coverage | Checkpoint |
| --- | --- | --- | --- |
| Text-only extraction | It could read beyond a positive FIB `cbMac`, mask a reserved piece-offset bit, and join words across a column break. | Bound every consumed FIB/text range by the declared extent, reject reserved offset bits, and preserve column separation. Keep historical zero-extent compatibility, selected-table behavior, logical piece ordering and split surrogate pairs. | [`2b06850`](https://github.com/CrispStrobe/legacy-doc-parser/commit/2b06850f5f236433376a7d505fb80b2f1c9046f9) |
| Nested and private fields | Normalized cached text was sliced using original character positions, causing conversion errors. Descendant field events could be emitted outside their containing instruction or expose private descendant instructions. | Reconstruct nested cached results from retained source text, emit typed fields once at the correct position, and suppress the complete private result subtree. Verify exact marker order and independently project visible text. | [`03fc67f`](https://github.com/CrispStrobe/legacy-doc-parser/commit/03fc67f9bf18b7e6e348d998cc65f60b48c7d3d9) |
| Caller-built field models | A caller could label `DDEAUTO` or `INCLUDETEXT` as `PAGE` and pass the allowed-field check. | Corroborate the declared type against the actual leading instruction. Unsupported or mismatched instructions remain inert, with cached text and evidence retained. | [`bcc2a06`](https://github.com/CrispStrobe/legacy-doc-parser/commit/bcc2a06cbc5d47eeee488530f3c1fae28eb8392c) |
| Formula fields | Binary formula instructions beginning with `=` received an empty field type despite existing writer support. | Recognize formulas, preserve their instruction and stored result, lock the field, and keep automatic updating disabled. A deliberately stale `999` result for `1 + 1` stays `999`; no formula is evaluated. | [`6123f68`](https://github.com/CrispStrobe/legacy-doc-parser/commit/6123f68b18bb64f62b1a6206ccfa837086eeeba8) |
| CFB names | Whole-string uppercase could expand names on JavaScript or fold supplementary character pairs, merging distinct streams/storages or rejecting valid siblings. | Use length-preserving simple uppercase per UTF-16 unit, leave surrogate units unchanged, and handle the 27 Greek simple/full-uppercase exceptions. VM and actual compiled-JavaScript controls cover sharp-s, Greek, ASCII and supplementary names. | [`297ee09`](https://github.com/CrispStrobe/legacy-doc-parser/commit/297ee094f8d094024f605ed802b86321743265c0) |
| CFB stream sizes | Historical version-3 high DWORDs caused valid documents to reject. Raw version-4 size arithmetic lost high bits on JavaScript, and direct reads could allocate from unbounded declared sizes. | Ignore meaningless version-3 high words, preserve version-4 metadata through the portable exact-integer limit, reject larger meaningful values, and check physical bounds before mini-stream/FAT allocation, including the root mini-stream container. | [`92486f8`](https://github.com/CrispStrobe/legacy-doc-parser/commit/92486f82dd746ab14b5ccf1310f629b74f7bfa5a) |
| Aggregate ink resources | Conversion forced every payload's standalone lazy decode; per-stream limits did not bound total retained points across a small document containing many ink objects. | Share a 100,000-point/4,096-stroke allowance across conversion. Reserve work before packet allocation, charge failed partial decodes, reuse identical model references, and prevent predecoded caches from bypassing the allowance. Every limited payload remains byte-exact inert evidence with an explicit status. | [`4c9dd54`](https://github.com/CrispStrobe/legacy-doc-parser/commit/4c9dd5413acfe96d9e23a28e14425d06f2ce116a) |

The text-only changes intentionally retain that API's main-body-only scope;
they do not turn it into full structured validation of unused stories.
Ink preservation counters still count occurrences. The shared allowance counts
inspection work on distinct immutable model objects; those are separate units.

The current media/table summaries also contained stale statements that already
implemented textbox origins, qualified fills and bounded floating-table
placement were unsupported. Those summaries now link the applicable contracts
and keep their original failed measurements attributed to their earlier runs.
No historical measurement, source input or reviewed golden was rewritten.

## Acceptance at the exact implementation commit

| Gate | Observed result |
| --- | --- |
| Baseline Dart suite at `c1b3ec5` | 1,055 tests passed. |
| Final Dart suite at `92486f8` | **1,113 tests passed**, including 58 added tests. |
| Full-repository fatal-info analysis | No issues found. |
| Maintained-source formatting | All 216 Dart files under `lib`, `test`, `tool` and `example` pass. |
| Python oracle/control tests | All 162 pass. Deliberate negative-control error messages in the log are expected test observations. |
| Corpus integrity | All 24 retained source hashes and OOXML package graphs verify. |
| Actual compiled JavaScript | Real DOC/CFB conversion, the new names/sizes/text checks, 51 media checks, five field cases, aggregate ink controls, 24 base ISFs and 32 header ISFs pass. |
| Independent Open XML SDK | All **260 required DOCX outputs** have zero validation errors; validator self-tests and positive/negative controls pass. |
| Deterministic schema generation | Both complete generations match across **550 files**. Parser, generator, validator and input hashes remain unchanged. |
| Package publication dry run | Zero warnings; no package was published. |

The validation environment uses Dart 3.14.0 and a source-built Open XML SDK
3.3.0 validator with .NET SDK 8.0.428. The exact resolved Dart dependencies,
source hashes, commands and original logs are retained in the
[audit evidence](evidence/parser-audit-20261113/README.md).

The first full-tree formatter command failed solely because it included
`doc/evidence/file-viewer-compat-20261113/native_probe.dart`. Its original
SHA-256 is bound by the historical `nativeProbeSha256` receipt. The original
failure is retained. Commit
[`1b4d23a`](https://github.com/CrispStrobe/legacy-doc-parser/commit/1b4d23afd8afe9b652daf0cc51196303c3df539f)
changes CI to format all maintained executable roots and leaves full-repository
analysis intact. The six archived evidence probes keep their original bytes;
the new formatting result is recorded separately from the initial failure.

## Native field observations and remaining limits

The five new converted field DOCX files were also imported into
LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, and inspected with Poppler
`pdftotext` 25.03.0. All five produced PDFs. Three matched the expected visible
text; two remain measured native-rendering differences:

| Control | Expected visible text | Native visible text |
| --- | --- | --- |
| Formula with deliberately stale cache | `A999Z` | `A999Z` |
| Field nested in another field's cached result, inside an instruction | `AVisibleZ` | `A1VisibleZ` |
| Private cached result | `AZ` | `AError:ReferencesourcenotfoundZ` |
| Private result inside a containing instruction | `AVisibleZ` | `AVisibleZ` |
| Unsupported nested external field kept inert | `AVisibleZ` | `AVisibleZ` |

This comparison removes Unicode whitespace only; the original extracted text
and PDFs are retained. The native smoke report explicitly has `passed: false`.
Successful schema validation and correct source-position/field-tree projection
do not establish equivalent rendering by an Office application. The original
five measurements and their expected text were not changed to create a pass.

Ten additional minimal DOCX controls were authored independently of the parser.
All ten validate with zero Open XML SDK errors. The two corresponding field
trees exactly match the parser output and reproduce both native differences.
Replacing the innermost PAGE with QUOTE also exposes its value, while literal
text or a field directly inside the outer instruction does not. An ordinary
missing REF target produces the same native error with empty, explicitly empty
and nonempty cached results; an existing empty target bookmark does not.
These controls attribute the observations to this importer's handling of
nested-result fields and reference resolution despite locks. Removing or
flattening those source fields would change retained semantics, so no such
production workaround was applied. The original failures remain in the receipt.

The package still has the documented broader limits in
[fidelity status](fidelity-status.md): exact pagination across arbitrary fonts
and renderers, complete drawing/effect and revision-topology coverage,
Word-native ink placement/editing, encrypted DOC input, and binary DOC writing.
Those are not implemented or certified by this bounded audit.

## Reproduction

Check out the exact implementation commit, resolve its retained dependency
lockfile in a disposable checkout, and run:

```sh
dart format --output=none --set-exit-if-changed lib test tool example
dart analyze --fatal-infos
dart test
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
python3 tool/fidelity/oracle.py
python3 tool/verify_web.py
python3 tool/fidelity/schema.py --out build/new-schema-audit
dart pub publish --dry-run
```

The schema command requires a .NET 8 SDK. The recorded run uses the existing
`--cached-nuget` direct-compiler mode with the repository's hash-pinned NuGet
inputs; it does not substitute a prebuilt validator. The full generated corpus
can be reproduced from the committed generators. The evidence retains the six
new binary sources and DOCX outputs as well as the complete matrix receipts.
