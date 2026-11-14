# Fidelity contracts and remaining gaps

The parser preserves supported source instructions and emits editable DOCX.
Native rendering, package validity, review semantics, and source-byte retention
are checked separately. None of the following rows claims complete support for
every Word document or every renderer.

| Area | Implemented contracts | Independent checks | Remaining scope |
| --- | --- | --- | --- |
| Pagination | Paragraph keep/widow/wrapping flags; section/page breaks; unequal columns; line/page numbering; 59 fixed note-label formats and placement; source compatibility settings; table origins, row heights and splitting; exact source note blocks after final tables | Pinned original/binary/native-DOCX/parser-DOCX comparisons with three requested cycles; page text, word boxes and raster hashes; nine authored table-origin cases, including nesting and custom margins | Exact pagination across arbitrary fonts, shaping, field evaluation, wrapping, notes, tables and Office versions. Equal page counts alone are insufficient. |
| OfficeArt | Editable rectangles, ellipses, lines and bounded move/line/cubic/close paths, including full and packed POINT encodings; supported explicit paint, opacity, line and shadow properties; qualified editable textbox scaled gradients, embedded picture/texture fills and bounded monochrome DIB patterns; bounded picture-frame flips and absolute quarter turns; explicit four-sided wrapping clearances with absence/zero preserved; source evidence for unsupported geometry/effects | PDF-vector endpoints, curves, colors and widths compared with authored expectations; six packed/full variants; independent Word position records; nine image-appearance controls, eight RGB exact | Arbitrary presets, adjustment formulas, complex groups/transforms, 3D, warp, and unimplemented effects. Unsupported effects are not silently replaced with a plain shape. |
| Metafiles | Bounded EMF/WMF payload validation and native image preservation; supported vector SVG previews, including compound polygons, alternate/winding fills, elliptical arcs, chords, pies and bounded ArcTo state | Real native PDF versus SVG interior-color assertions for EMF32, EMF16 and WMF; fifteen independent native arc/paint/endpoint controls; malformed record, object-table and aggregate-point tests | Complete GDI text, bitmap, clipping, brush, transform and raster-operation behavior. An unknown preview record invalidates the whole preview rather than disappearing. |
| Table styles | Table-style inheritance, all twelve conditional regions, supported cell borders/shading/margins, table mutations, indirect property streams, preferred-width units and context-sensitive no-wrap, row alignment/autofit exceptions; separate row-wide padding defaults, inherited resets and bounded absolute floating origins; contextual paragraph/run properties applied before run coalescing; false/default resets | Independently assembled binary styles and PCnf/CCnf records; native style XML; source and nested-table render probes; external schema checks | Every table property and interacting conditional rule. Relative toggles may require resolved direct formatting plus an explicit native-style limitation. Properties not valid in style XML remain diagnosed. |
| Linked textboxes | Validated story chains, one owner for shared text, source margins/flow/wrap/alignment, narrowly corroborated native chain-length recovery; range separators excluded while intentional blank paragraphs remain; corroborated normal/first-header aliases retain real source identities and a one-frame chain | Resize probe verifies that markers actually move between boxes, appear once, and remain in order; fourteen main/header boundary controls plus seven native alias controls and first-page activation variants cover empty content and leading/interior/trailing blanks; placement measured separately | General grouped/overlapping textbox layout, all wrapping interactions and paint effects. Shared header text containing identity-bearing content, review histories or ambiguous frame contexts is excluded from alias recovery. The former 72-point translation is corrected: measured marker drift is 0.0pt; the compact and extended sources are RGB-exact at the 74420eb2 checkpoint; the earlier compact five-pixel difference remains in its historical evidence. |
| Comments and ink | Native parent/reply relationships; bounded IMsoInkData extraction; complete supported nonempty ISF packet/paint decoding; original and transformed coordinates, selected source transforms and zero-based unitless pressure metrics; immutable raw occurrence evidence | Actual Windows WPF: 24 initial/round-trip ISFs plus 32 independently controlled transform/metric inputs; VM and compiled JavaScript comparisons; bounds/mutation tests; original native pressure-metric discrepancy retained | Resolved/done state is not reconstructed from fields that do not encode it. Word-native ink placement/rendering/editing, general tablet metrics, remaining transform forms, arbitrary properties and full ink/comment association remain open. Complete decoding never creates a guessed active ink object. |
| Lists | Shared counters, source start overrides, multilevel ancestor resets, never-restart and legal/hidden markers; separate restarts; explicit numbering history; marker-font inheritance | Independent instance graph; continuation/restart fixtures; native marker font/bounds; positive/negative ilfo tests | All counter-reset and override interactions, especially after edits in consuming applications. A native list indentation disagreement with the binary specification is retained in the evidence, not hidden by reversing precedence. |
| Revisions | Supported inserted/deleted text and paragraph marks; run/paragraph/section formatting history; numbering NumRM history; LISTNUM display revisions; bounded row height/split/header property history; independent insertion/deletion provenance for media and note/comment anchors; author/time and source evidence | Independent accepted/rejected text projections, previous-property checks, native section probe and six exact row accept/reject layouts; 24 object/reference schema controls with independent accept/reject projections; malformed/hidden/private history tests | Complete move, table and object formatting histories, arbitrary cross-story and overlapping topology, every prior-property payload, and editor-level accept/reject behavior. Header revisions that can change conditional formatting remain diagnosed evidence. Reserved binary fields are not interpreted as move identities. |

## Evidence is versioned

The [14 November follow-up](parser-audit-20261114-followup.md) validates clean
source **a25e4ea824886327b97bde2873e6ef175a5ab971**, separately from subsequent
documentation commits. Its six repairs preserve direct public cell shading,
enforce the embedded-object Bool8 operand, retain fixed built-in heading
levels, apply indirect paragraph-property replacement correctly, validate
bookmark metadata and story boundaries before visibility fallback, and check
textbox identities, owners and source chains before placement fallback.
Valid header/footer and six Hdd separator/continuation owners remain supported.

The combined gate passes 3,903 Dart tests, 197 Python controls, 38 compiled
JavaScript groups and 1,533 independent SDK package validations: 1,114
DOC-derived outputs and 419 public-model outputs in nine groups. All 24
retained oracle inputs validate; 353 Dart files need no formatting changes,
and the publish dry run reports zero warnings. The
[follow-up receipt and logs](evidence/parser-audit-20261114-followup/README.md)
retain the exact source and acceptance evidence. No new native rendering or
editor accept/reject measurement is claimed by this pass.

The [14 November audit continuation](parser-audit-20261114.md) validates clean
runtime **2f8a307** with 3,688 Dart tests, 195 Python controls, 34 compiled
JavaScript acceptance groups and 1,426 schema-valid packages (1,057 DOC-derived
and 369 public-model outputs). It fixes current/historical section scalar
domains, missing public section coverage, hidden comment-reference validation,
and compound byte-sink reuse. All seven public export corpora now run inside
the SDK gate with independent inventories, hashes and repeated generation.
The [saved receipt and logs](evidence/parser-audit-20261114/README.md) are new
portable/schema evidence; they do not replace missing historical native
artifacts or certify physical layout and editor review behavior.


The [fifth parser audit](parser-audit-20261113-fifth-pass.md) is implemented
through runtime `6b57d17` and merged in `83acdf1`. It adds source-aware
literal-percent list labels, complete supported marker inheritance and resets,
bounded compound metadata and shared directory ownership, note ownership,
formatting-domain validation, field visibility validation and complete typed
display-field revision evidence. Callers can opt into
`LegacyWordFieldMode.cachedResults`; default active fields can still be
recalculated by consuming applications.

The [fifth-pass recovery index](evidence/parser-audit-20261113-fifth-pass/README.md)
retains successful portable and SDK receipts for that historical runtime.
**The original evidence upload is incomplete:** 3,124 of 14,103 manifest files
are present, with every retained member hash verified. Archives 005–017 and
the principal native rerun artifacts are missing. Transcript native totals
must not be treated as newly verified rendering acceptance. Later validation
needs its own source identities and complete saved artifacts.

The [fourth parser audit](parser-audit-20261113-fourth-pass.md) validates runtime
**e84f413** with 1,361 Dart tests, 162 Python controls, actual compiled-JavaScript
acceptance and 320 schema-valid packages (279 DOC-derived DOCX, 24 public-image
DOCX and 17 public-compound DOCM). All 297 preceding DOCX outputs remain
byte-identical. The [evidence bundle](evidence/parser-audit-20261113-fourth-pass/README.md)
retains exact source identities, original failures and the passing receipts.
That historical pass added list-text, text-only Unicode and public OLE/VBA
activation checks. Literal `%1`–`%9` labels and the two measured LibreOffice
field-import differences were still open at that checkpoint; the fifth pass
subsequently changed list and field handling as described above. Full CFB
conformance and native Word rendering fidelity remain broader open scope.

The earlier integrated runtime **c5ff75e7** has
[portable/schema evidence](evidence/continuation-c5ff75e7/README.md) records
1,028 Dart tests, 162 Python controls, actual DOC/51-media JavaScript checks,
56 native WPF ISFs, and 254 schema-valid DOCX outputs. The two complete
538-file generations are byte-identical and all source inputs stay unchanged.
The [native corpus](evidence/native-corpus-c5ff75e7/README.md) completes all
24 documents and 72 repeat imports, with nine exact initial renders. The
[follow-up handoff](continuation-20261113-followup.md) gives exact integration
identities and remaining source/native boundaries.
Word14's three repeated binary-to-DOCX tiled-fill comparisons lose raster
exactness, changing that aggregate from 39/72 to 36/72; the initial image error
improves and all page/text/geometry metrics stay unchanged. The native bundle
retains the complete pixel/source triage and the unsupported original alternate
DrawingML scope. Source-faithful image retention is not reported as universal
native parity.

The follow-up adds Line Number character-style inheritance, visible generated
OLE placeholders, corrected fractional PICMID scaling, qualified textbox paint,
and bounded nonempty ink decoding. The [updated handoff](continuation-20261113-followup.md)
links their exact runtime/evidence checkpoints and source/native distinctions.
The accepted [74420eb2 portable/schema gate](evidence/continuation-74420eb2/README.md)
and [native corpus](evidence/native-corpus-74420eb2/README.md) record 954 Dart
tests, 230 schema outputs and nine exact initial renders out of 24. Later
features have their own independent controls and must use their own gate
receipts; those counts are never retroactively attached to earlier commits.

The retained [combined continuation at 48bf3a](evidence/continuation-48bf3a/README.md)
passes 934 Dart tests, 162 Python controls, actual-DOC JavaScript acceptance and
51 media checks. The independent Open XML SDK accepts all 229 required DOCX
outputs with zero errors. Both complete 486-file schema generations match byte
for byte; all logs, controls and unchanged-input receipts are retained.
At that checkpoint CrispCloud pinned that runtime; its clean remote source `0233ed8e` passed
107 data tests, production DOC/RTF/PPT/MSG JavaScript smoke and 13 actual native
assertions. Its guarded mirror now verifies the exact Git-index inventory as
well as the working bytes, including all six previously omitted diagnostic
logs. The [historical handoff](continuation-20261113.md) records those integration
identities, source-retention controls and execution limits.

The [48bf3a 24-case native corpus](evidence/native-corpus-48bf3a/README.md)
completes all 72 repeat imports without execution/import errors. Eight initial
renders are exact; 58 cycles are exact versus the preceding import and 48 versus
the first. Both header fixtures are exact initially and through all three
cycles. Word16's initial word boxes now agree exactly; its native bridge rewrites
the source compatibility bit, so the 1.446-point repeat difference remains.
Both source-render goldens reproduce. Every archive and all 240 lossless raster
pages are independently verified, and the prior corpus uses the same source
bytes, renderer, fonts and tool identities. All strict structural comparisons
still report differences.

The [note-source audit](evidence/note-source-attribution-20261113/README.md)
attributes the native question-mark substitution and obsolete note-numbering
field independently of the parser. The existing
[footnote-table attribution](evidence/table-note-oracle-20261113/README.md)
preserves the real source table and its exact authored rendering. These
differences do not justify changing source text or flattening tables.
Table/note renders remain exactly stable versus their first parser import
through three cycles.

Word14's 0.75-point initial difference and the native bridge's 0.05-point movement
per cycle remain measured. The earlier
[absent-width probes](evidence/textbox-default-probe-20261113/README.md)
reduced one measurement without establishing exact raster equality or a
repeat-safe source mapping, so that attempt was rejected. The later
[qualified default/frame contract](textbox-stroke-defaults.md) accepts the
documented default only for fully resolved, explicitly enabled lines and
couples it to the seven-twip outer-frame conversion. True absent plain/dashed
controls and a paired explicit control are exact through nine native repeats;
disabled, zero-width and unresolved cases retain distinct behavior. This does
not bypass Word14's remaining grouped/relative-size property guards. Active
disabled-line fallback dashes now remain explicit unsupported OfficeArt
evidence. Dormant fallback flags on an enabled line do not narrow supported
ordinary shape behavior.

The historical [0c3e596 portable/schema](evidence/continuation-0c3e596/README.md)
and [native corpus](evidence/native-corpus-0c3e596/README.md) retain their original
918-test, 228-output and 6/24 initial-render measurements, plus the separate
21-output table gate. Their original app pin and execution limits remain in
the [12 November handoff](continuation-20261112.md); those are not the current
integration boundary.

The [floating-table evidence](evidence/floating-table-origin-20261112/README.md)
separates table defaults from cell overrides, retains later-row resets and
supports bounded row-origin/padding/single-border coordinate mapping. Seventeen
independent context controls preserve page rasters and border vectors; one
has a 0.05-point word-box rounding difference. The
[wrap/stroke evidence](evidence/textbox-wrap-stroke-20261112/README.md) retains
the accepted clearances and rejected automatic stroke default. Earlier
checkpoints below remain historical measurements of their recorded source.

The [integrated acceptance receipt](evidence/combined-47b9c95/README.md)
retains the clean main-source gate: 809 Dart tests, 162 Python tests, 51
JavaScript media checks and all 218 required SDK outputs. All 194 earlier schema
cases survive alongside the 24 textbox-table controls. A test-only follow-up
also checks the generated fixture manifests against the emitted package XML
in 13 focused tests; the producer and runtime are unchanged.

The [completed 24-input checkpoint](evidence/e90f38f/README.md), reproducible
from pushed `c3fa95e`, imports every original input and completes all 72 repeat
imports without execution errors. All 24 initial page counts agree; six initial
RGB/text/geometry comparisons are exact and both reviewed source goldens match.
The earlier first-header failure is closed for these retained source bytes.
The complete corrected-oracle report, all 288 emitted DOC/DOCX files, portable
checks and 194-output SDK gate are sealed with hashes. Strict structural
comparisons still report differences; this is not a full-fidelity certificate.
The runtime in integrated `47b9c95` is byte-identical to this measured runtime.
The [native-backed textbox-table rollback](evidence/textbox-table-context-20261112/README.md)
remains in place: a candidate that matched native DOCX export moved source
content by 12 points, so that change was retracted rather than accepted as a fix.

The shared-shape extension in the [header recovery contract](header-textbox-aliases.md)
handles the first-header failure recorded below. Two occurrences retain the same
source shape ID and separate anchor CPs, rectangles and wrapping flags; only a
corroborated plain single-frame normal/first-header pair can use this recovery.
Seven retained controls pass 28 initial/cycle imports and 28 native projections,
with 29 schema-valid outputs. Native changes to frame geometry remain visible.

The [text-context oracle correction](evidence/oracle-text-context/README.md)
separates run content from property subtrees, fixes revision/comment offsets and
retains genuine boundary tabs, breaks and spaces. Snapshot version 4 identifies
the corrected measurements. The sealed earlier reports retain their original
bytes and oracle versions; their false tab differences are not parser data loss.

The [clean 24-input checkpoint](evidence/8367ce0/README.md), reproducible from
pushed `d28be0a`, passes all 24 initial imports and page-count comparisons, with
six exact initial renders and both reviewed source goldens. Twenty-three cases
complete all three cycles. The first-page-enabled header case fails its first
regenerated DOC import with an ambiguous shape anchor; all 281 emitted documents
and the complete error report are retained. Portable checks pass 761 Dart and
129 Python tests, 51 JavaScript media checks and all 193 required SDK outputs.
The measured text oracle also counts tab-stop properties as text tabs, so those
structural differences require corrected replay before loss attribution.

The [header-alias correction](header-textbox-aliases.md) recovers the retained
native failure without inventing a flow chain or activating the first header.
Seven independently authored controls preserve each header occurrence and
its intentional blank paragraphs. The [note-table correction](note-table-boundaries.md)
preserves source block sequences in all 64 initial/cycle imports; the real
final-table footnote is exact to its authored original in RGB, text and word
geometry through three cycles. Native-added paragraphs, endnote bridge
offsets and native projection schema errors remain recorded separately.

The [continuation branch 7308125 checkpoint](evidence/continuation-7308125/README.md)
passes 725 Dart tests, 130 Python controls, 51 JavaScript media checks plus
document browser acceptance, and 196 required DOCX schema outputs with zero
errors. Its [complete native corpus](evidence/native-corpus-7308125/README.md)
retains all 22 cases and 66 repeat imports without execution/import errors,
including 2,438 archived files and 222 verified compressed raster pages. All
initial and repeat page counts match. Six initial renders are exact; 47/66
cycles are exact relative to the preceding parser import and 37/66 relative to
the first. All strict structural comparisons still differ. Both source goldens
reproduce, while only one of the two parser outputs matches its source golden.

The current runtime recovers a closed native header/footer table only at its
exact declared story boundary with the existing guard present. The
[four native controls](evidence/header-table-boundary-20261112/README.md)
retain exact relative table geometry and the remaining 0.35 pt absolute
placement differences. A proposed textbox table-depth reset passed schema
validation but caused a 12 pt native-source regression; it was
[retracted with its counterexample retained](evidence/textbox-table-context-20261112/README.md).
The [current continuation handoff](continuation-20261113-followup.md) records the exact
app/parser pins, integration results and remaining priorities; the
[first-pass handoff](continuation-20261113.md) retains its historical measurements.

The [solid-shape context control](officeart-context.md) now retains all three
editable shapes in its native DOC. Ordered geometry agrees within 0.1 pt, while
dash spacing and RGB differences remain visible in the receipt. Explicit path
editing hints are retained as evidence; native tangent editing is not mapped.
The textbox range correction independently removes the extra paragraph from
all six Word 14 boxes. It does not establish exact small-frame height or general
header-chain layout.

The [textbox boundary evidence](textbox-boundaries.md) retains all fourteen
schema controls, seven passing native main-story controls and the separate
native header-alias failures. The combined source at pushed `713973f` passes
647 Dart tests, 109 Python tests and all 144 required SDK output checks. Its
[interrupted native run](evidence/fe4d668-interrupted/README.md) completed eighteen
three-cycle cases before the environment ran out of disk space; the complete
partial report, errors and all 228 emitted documents are preserved. This run
does not replace the complete corpus result below.

The [clean 6b2b611 checkpoint](evidence/6b2b611/README.md), identical in source
tree to pushed `34e1484`, retains all 22 original inputs and all 66 requested
repeat imports without execution/import errors. Every initial page count
matches, six initial RGB/text/geometry comparisons are exact, and both reviewed
source goldens reproduce. Every strict structural comparison still reports
differences. All source and cycle-input bytes remain unchanged. The independent
schema gate accepts all 129 required outputs with zero errors; portable checks
pass 616 Dart and 104 Python tests, plus JavaScript acceptance. The complete
161 MB native JSON is retained losslessly as XZ, alongside the schema report and
portable log. These measurements do not establish universal fidelity.

The [clean 8060ac1 checkpoint](evidence/8060ac1/README.md) retains all 22
native cases, three requested round trips, the complete compressed reports and
portable-check log. All initial imports retained page count; six initial page
renders were exact, and both reviewed source goldens reproduced. Twenty-one
cases completed all three cycles. A regenerated Word 16 DOC failed at its first
round-trip import with an inconsistent OfficeArt BLIP-store count. Every strict
structural comparison still reported differences. The independent schema gate
accepted all 92 required DOCX outputs with zero errors; this is a separate
validity result, not a rendering or semantic equivalence certificate.

[Checkpoint f24e5b2](evidence/f24e5b2/README.md) retains the complete compressed
native report, its source/output hashes and its initial schema failures. At
that checkpoint all eleven imports succeeded and page counts matched, but one
document matched pixels, text and geometry exactly. Every strict structural
comparison reported differences; those include representation differences and
must be inspected before classifying them as semantic loss. Later fixes do not
rewrite this earlier result into a pass.

The [table-origin golden](../test/fixtures/word_native/table-origin-golden.json)
was reviewed against nine native source cases. It measures text relative to an
independent body/outer-cell anchor and records exact native indentation. It
does not assert whole-page equivalence. The
[list-marker receipt](evidence/list-marker-font-native.json) records the font
correction and the remaining indentation discrepancy separately.

No nonempty ISF fixture was found in the inspected Quds DOCX corpus. An empty,
independently authored ISF stream tests the documented byte envelope and bounds.
That empty control establishes neither stroke decoding nor full ink-comment
fidelity. The later [Windows WPF oracle](evidence/wpf-isf-oracle-20261113/README.md)
and [transform/metric controls](evidence/wpf-isf-metrics-20261113/README.md)
independently qualify the [bounded semantic decoder](ink-decoding.md). They
still do not establish Word placement or editing.

LibreOffice discards the section revision history in the dedicated native
probe. Matching that discarded native history is not accepted as correctness:
the probe separately requires the authored previous section values, authors,
dates and unique revision identities in the parser output.
The [raw-byte review audit](review-loss-attribution.md) separately attributes
the sealed corpus's missing reply and section history to the native bridge,
using retained exact inputs rather than structural counts alone.

## Repeatable checks

Run `dart test`, `dart analyze --fatal-infos`, and the Python tests under
`tool/fidelity`. The native corpus command accepts `--roundtrip-cycles 3` and
compares every import both with the preceding import and the first import.
It retains native-bridge changes separately from parser changes, snapshots each
completed stage before later work, and records code/compiler/executable hashes.

`--require-exact` fails on remaining rendering or structural differences. The
ordinary measurement command can succeed while reporting those differences;
its successful exit means the measurements completed, not universal fidelity.
No command automatically updates a reviewed golden.

See [the oracle guide](fidelity-oracles.md), [layout contracts](layout-fidelity.md),
[table/list contracts](table-and-list-fidelity.md), [drawing/metafile contracts](media-fidelity.md),
and [revision/comment contracts](revisions-comments.md) for the precise source
format definitions, current tests and remaining limits.
