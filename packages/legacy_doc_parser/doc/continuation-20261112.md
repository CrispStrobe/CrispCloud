# Office fidelity continuation — 12 November 2026

This is a historical handoff. The [13 November continuation](continuation-20261113.md)
records the current branches, integration pins, completed validation and
remaining priorities. The identities and measurements below are retained as
recorded at this earlier checkpoint.

The current implementation and evidence are saved on
`feature/office-fidelity-continuation-20261112` in both
[`CrispStrobe/legacy-doc-parser`](https://github.com/CrispStrobe/legacy-doc-parser/tree/feature/office-fidelity-continuation-20261112)
and [`CrispStrobe/CrispCloud`](https://github.com/CrispStrobe/CrispCloud/tree/feature/office-fidelity-continuation-20261112).
Both branches incorporate their newer main-branch work. Runtime fixes and
validation evidence are separate checkpoints with their original identities.

## Exact current integration boundary

| Component | Validated source |
| --- | --- |
| Standalone parser | `0c3e59682952cce0e11301afec789e7ae2a1256a` |
| Parser source tree | `e763288ee642c26854572e1cae212c36bf683918` |
| CrispCloud | `5348fadec3bdadc40cc1c092da66428716df6225` |
| App source tree | `837c1d04233553b9067bdcf31f757c012bccaea5` |
| Quds source, unchanged from app main | `71bb109e81217ed55c534881304a44ae8fa608d5` |
| Guarded Office inventory | 1,074 files: 653 exact upstream parser files and 421 unchanged non-parser files |

CrispCloud pins the exact validated parser runtime and has no app-local parser
patch. Later evidence-only commits do not require another runtime roll. The
[app acceptance receipt](https://github.com/CrispStrobe/CrispCloud/blob/feature/office-fidelity-continuation-20261112/docs/evidence/word-continuation-0c3e596/README.md)
records tests run on the exact clean remote app commit above. No merge, release
or package publication is represented by these development checkpoints.

## Changes and measured effects

**Floating tables retain their source origin and padding.** The parser keeps
row-wide table defaults separate from cell overrides, resolves inherited table
styles, and emits later-row padding resets as `tblPrEx` exceptions. The writer
restores Word's plus-one coordinate encoding and accounts for shared row-grid
origin, the emitted table default and supported single-border outside extent.
Named positions remain named; out-of-range target coordinates fail explicitly.
Unsupported border-origin contributions produce partial-formatting evidence.

The Word16 source's historical 56.4-point maximum displacement is now 1.446
points, confined to its middle word. Repeated imports no longer move its table
origin. All nine existing inline/nested table-origin goldens still agree.
Seventeen independent signed-position, padding, border and RTL controls retain
exact 72-dpi page rasters and PDF border vectors; one retains a 0.05-point text
bounding-box rounding difference. The
[table evidence](evidence/floating-table-origin-20261112/README.md) preserves the
source bytes, discriminating controls and the rejected incomplete candidate.

**Explicit drawing wrap clearances survive conversion.** The parser preserves
OfficeArt's four explicit wrapping distances, including the distinction between
absence and zero, and emits them for textboxes, supported shapes and pictures.
Six Word14 textboxes retain their source 3.6-point top/bottom clearances. Their
initial word sequence and layout text now agree with the source; a 0.75-point
maximum displacement remains. Three cycles add 0.05 points each through the
native bridge, while every regenerated binary-to-parser render is exact.
The [wrap contract](officeart-wrap-distances.md) and
[native comparison](evidence/textbox-wrap-stroke-20261112/README.md) record that
scope. An automatic default textbox stroke improved one initial measurement
but worsened repeats; it was withdrawn, with its complete failure retained.

**Earlier corrections remain integrated.** Table-ended notes no longer receive
a synthetic trailing paragraph, and floating positions are retained. In the
complete final corpus, both `table-borders` and `note-markers` remain exact
relative to the first parser import through three cycles, removing the former
13.45-point-per-cycle movement. Initial rendering differences remain separate.
Shared normal/first-header textbox stories import through all cycles without
inventing a linked flow chain. Bounded binary HFD hyperlink metadata preserves
the bookmark target; script-specific fonts retain the source's separate slots.

The formatting source has one `東京` and one emoji. Both are present in the
final DOCX and visible render. The native binary reference omits visible
Japanese text and duplicates the emoji in extraction. The changed word sequence
therefore must not be described as parser text loss. The final native evidence
includes exact source font/run records, XML comparisons and visual crops.

**App integration remains guarded.** All managed parser bytes and executable
modes match the pinned upstream source. The source review covers all 27 changed
bound paths relative to app main. The reviewed-file inventory adds only the
new HFD metadata module, and its two technical fingerprints are refreshed after
review. Classification/distribution decisions, dates, references, source plist
declarations, the lockfile and Quds/non-parser files remain unchanged.

## Final validation

| Gate | Result and scope |
| --- | --- |
| Parser portable suite | 918 Dart tests; 162 Python controls; formatting and fatal-info analysis clean |
| Parser input identity | All 655 captured input hashes unchanged; clean before and after |
| Parser JavaScript | Actual binary-DOC acceptance and 51 media checks passed |
| Independent Open XML SDK 3.3.0 | 228 required DOCX outputs, zero errors; complete hashes and positive/negative controls |
| Schema determinism | All 484 files identical across two complete generations |
| Extra table schema controls | 21 actual final-runtime DOCX outputs, zero errors; all OPC parts match independently measured candidates |
| Native corpus | 24 documents and 72 repeats; zero execution/import errors; unchanged inputs and consistent runtime/tools/fonts |
| Native initial exactness | All page counts match; 6/24 exact RGB/text/geometry renders; both source goldens reproduce |
| Native repeat exactness | 52/72 exact versus preceding parser import; 42/72 versus first import; all repeat page counts/dimensions match |
| App data-only Word cohort | 107 tests across eight suites; no failures/skips; 1,176 input hashes unchanged |
| App actual installed Office checks | 13 LibreOffice/Poppler assertions passed on one authored formatting fixture |
| App production JavaScript | DOC, RTF, PPT and MSG passed using the genuine production configuration |
| App source controls | 24 sync, 38 Apple preflight, 40 crypto evidence and 22 ebook controls passed; two expected macOS-only skips |
| App actual source verification | 1,074 Office files and all 279 pinned CrisperBooks files verified |

The [portable/schema evidence](evidence/continuation-0c3e596/README.md) retains
1,065 files, including both complete generated corpora and the 21 extra inputs
and outputs. The [complete native evidence](evidence/native-corpus-0c3e596/README.md)
retains all 24 reports and 2,646 archived files: 312 DOC/DOCX files, 230 PDFs and
240 verified compressed RGB pages. Independent verification checks every byte,
source identity and raster binding. Earlier receipts and rejected candidates
remain intact; no reviewed source golden was updated.

The native renderer was LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, with Poppler 26.05.0 at 72 DPI and
Dart 3.13.7. Microsoft Word was not executed. Strict structural comparisons
still differ in all cases; package validity, source preservation, visual
exactness and app category presence are separate contracts.

The app cohort preserves the original assertions in copied data-only suites
with their test-framework import adapted. Its 13 fake-process converter tests
are separate from the 13 actual native assertions. Genuine production package
resolution succeeded offline without a lockfile change. Flutter widgets,
native ebook hooks and a full release build were not run. Automatic approval
review rejected an earlier Flutter launcher probe after it unexpectedly
attempted a cloud metadata endpoint; final checks used the existing direct
Dart binary without retrying that launcher.

## Remaining priorities

1. Investigate initial table/note and compatibility differences separately from
   repeat stability. `table-borders` still has 74.427-point initial word
   displacement, and note/compatibility source word sequences still differ.
2. Resolve the bounded remaining textbox geometry: Word14's 0.75-point initial
   difference and 0.05-point native-bridge movement, and header frames' existing
   0.35-point movement per cycle. The rejected stroke-default and table-depth
   hypotheses remain counterexamples, not accepted fixes.
3. Investigate the fixed 1.446-point Word16 middle-word difference and general
   border-origin combinations outside the supported single-border mapping.
4. Retain the source/default attribution for A4 versus Letter: the two list
   fixtures omit source page-size properties; the binary specification chooses
   Letter while LibreOffice chooses A4. Do not rewrite source defaults merely
   to force one renderer's dimensions.
5. Extend complex GDI/metafile behavior, nonempty ink rendering/association and
   full move/table/object revision semantics with independent source fixtures.
   Existing bounded support does not imply complete Word fidelity.

Start further work from the saved continuation branches, preserve the app's
exact parser pin and guarded mirror, checkpoint incremental changes remotely,
and bind each new measurement to its exact clean runtime. The historical
[7308125 portable/schema](evidence/continuation-7308125/README.md) and
[native corpus](evidence/native-corpus-7308125/README.md) remain available with
their original failures and counts. The older 24-case e90f38f receipt supplies
the two header controls omitted from the 22-case historical continuation.
