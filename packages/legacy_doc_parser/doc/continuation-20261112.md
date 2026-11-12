# Office fidelity continuation — 12 November 2026

The implementation and evidence are saved on
`feature/office-fidelity-continuation-20261112` in both
[`CrispStrobe/legacy-doc-parser`](https://github.com/CrispStrobe/legacy-doc-parser/tree/feature/office-fidelity-continuation-20261112)
and [`CrispStrobe/CrispCloud`](https://github.com/CrispStrobe/CrispCloud/tree/feature/office-fidelity-continuation-20261112).
These continuation branches incorporate the newer main-branch source and retain
the earlier evidence without relabeling historical executions.

## Exact integration boundary

| Component | Validated runtime source |
| --- | --- |
| Standalone parser | `730812534e8dc045d6d97f600218228f05c51b97` |
| Parser source tree | `c69a9b26fff0d8b6c22519321f34c2781f4943d6` |
| CrispCloud | `5e1adcdbcdc6763e3eeb86a4632821c2b53a8c37` |
| Quds source, unchanged | `74960237cea7c560f3db7ee96ca37641c4438567` |
| App mirror inventory | 823 managed Office files, including 402 exact upstream parser files |

Subsequent branch commits retain documentation and evidence. They do not change
the validated parser runtime. CrispCloud intentionally pins the exact validated
source above instead of rolling again for evidence-only additions. Its guarded
mirror contains no app-local parser patch.

The [CrispCloud evidence checkpoint](https://github.com/CrispStrobe/CrispCloud/blob/0320c96098f595b8906c22c465ad52220e9e7272/docs/evidence/word-continuation-7308125/README.md)
retains the complete app receipt and reproduction helpers. No merge or release
is represented by these development branch checkpoints.

## Completed changes

**Header/footer table import.** The parser now accepts the observed native
closed-table row marker before the story's existing guard CR only when the
parsed table ends exactly at the declared story boundary. It records
`recoveredTableStoryBoundary`, does not extend story ranges and continues to
reject malformed/unclosed tables and missing guards. Six story variants,
separation from subsequent stories, five malformed cases and four retained
native fixtures are covered. Both native paragraph-ended controls produce the
same DOCX bytes as before. All four story-relative marker comparisons agree;
the 0.35 pt absolute differences remain documented in the
[native receipt](evidence/header-table-boundary-20261112/README.md).

**Accurate app conversion warnings.** CrispCloud now requires a valid content
anchor for a header, footer, footnote, endnote, comment or embedded object before
clearing that category's loss warning. Unused package parts, unused definitions,
ambiguous duplicate IDs and historical property snapshots cannot manufacture
preservation. A comment reference inside comment content cannot attach a second
comment and its object. Direct valid anchors, Strict/transitional namespaces,
relocated parts and supported Office Math content retain their positive
controls. Presence still does not prove full content/count equivalence or
rendering fidelity.

**Bounded native evidence storage.** The runner's opt-in `--raster-storage gzip`
renders one RGB page at a time, checks PDF page count independently, verifies
lossless compressed/raw hashes and records the page before removing raw scratch
bytes. Default PPM behavior remains available. The wrapper seals and independently
verifies each complete case before removing only its raw run directory. The
complete native reports, original inputs, bridge documents, generated documents,
PDFs, text, geometry and raster pages are retained. Failed/incomplete cases are
preserved, and resume does not overwrite them automatically.

**Rejected hypothesis preserved.** Resetting table depth for textboxes initially
passed portable and schema controls, but moved a native table-cell-anchored
textbox's cell by 12 pt. The native DOC-to-DOCX exporter made the same mistake.
The reset was fully retracted before app integration; the baseline's source
geometry and the counterexample are retained. The
[retraction receipt](evidence/textbox-table-context-20261112/README.md) prevents
the rejected intermediate checkpoint from being mistaken for the shipped fix.

## Final validation

| Gate | Result and scope |
| --- | --- |
| Parser portable checks | 725 Dart tests; 130 Python controls; formatting and fatal-info analysis clean; original corpus hashes unchanged |
| Parser JavaScript | 51 media checks and real-DOC browser acceptance passed |
| Independent Open XML SDK 3.3.0 | 196 required DOCX outputs, zero schema errors; deterministic inventory, input hashes and positive/negative controls passed |
| Native corpus | 22 documents, 66 repeat imports, zero execution/import errors; all source and cycle inputs unchanged |
| Native exactness | All initial page counts match; 6/22 initial RGB/text/geometry comparisons exact; both reviewed source goldens reproduce; all strict structural comparisons differ |
| Repeat rendering stability | 47/66 exact versus preceding parser import; 37/66 exact versus first import; all repeat page counts match |
| App data-only Word cohort | 107 tests across eight suites, zero failures/skips; 1,170 captured input hashes unchanged |
| App actual installed Office check | 13 LibreOffice/Poppler checks passed on the authored formatting DOC |
| App portable browser smoke | DOC, RTF, PPT and MSG passed |
| Guarded source synchronization | 24 controls passed; 823 managed files verified |

The app cohort uses the existing assertions with only `flutter_test` changed to
`package:test` in copied suites. Its 13 fake-process installed-converter tests
are separate from the 13 actual native checks. Flutter widgets, the excluded
preview suite and a full app release build were not run. Release and fingerprint
policies were not changed.

The native corpus ran as 22 separate ordinary runner invocations against clean
parser source, with one consistent tool/source/font fingerprint. It used
LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, Poppler 26.05.0, 72 DPI and Dart
3.13.7. It does not establish Microsoft Word behavior. Schema validity, visual
exactness, structural snapshots and app category presence remain distinct checks.

The [portable/schema evidence](evidence/continuation-7308125/README.md) and
[complete native evidence](evidence/native-corpus-7308125/README.md) retain the
commands, environment/source hashes, raw results, compressed artifacts,
verification helpers and per-case differences. Earlier failures and the
pre-retraction schema pass keep their original source identities.

## Remaining priorities

1. Investigate repeated table/note layout drift using the retained binary bridge,
   native-exported DOCX and parser output separately. `table-borders` and
   `note-markers` accumulate 13.45 pt per cycle, reaching 40.35 pt from the first
   parser import. `table-borders` already differs by 74.427 pt initially.
2. Resolve native header textbox chains that reference one story from separate
   frames. The table-ending boundary recovery does not solve this chain problem.
3. Investigate the two list page-dimension mismatches, note/compatibility word
   sequence differences and remaining Word 14/16 positioning differences.
   Preserve the existing independently measured source geometry when considering
   changes; native-exported XML alone has already produced a counterexample.
4. Extend the supported contracts for complex GDI/metafile operations, nonempty
   ink rendering and association, and full move/table/object revision semantics
   with independently authored source fixtures. Existing bounded support does
   not imply complete Word fidelity.

For another code change, start from the saved continuation branches, keep the
app's source mirror guarded, save small remote checkpoints, and attribute every
new validation receipt to its exact clean runtime source. Do not replace old
goldens or rewrite earlier failures as successes.
