# Office fidelity follow-up — 13 November 2026

Continue from `feature/office-fidelity-gaps-20261113` in
[legacy-doc-parser](https://github.com/CrispStrobe/legacy-doc-parser/tree/feature/office-fidelity-gaps-20261113)
and [CrispCloud](https://github.com/CrispStrobe/CrispCloud/tree/feature/office-fidelity-gaps-20261113).
This follow-up supersedes integration guidance in the
[first-pass handoff](continuation-20261113.md); its original measurements and
rejected controls remain unchanged. Implementation, independent evidence and
app integration are saved in separate remote checkpoints.

## Combined runtime and acceptance

The integrated parser runtime is
[`c5ff75e76163d9abbdd44a9f2a7c5ad210929289`](https://github.com/CrispStrobe/legacy-doc-parser/commit/c5ff75e76163d9abbdd44a9f2a7c5ad210929289),
Git tree `25bd05c12fa2272a32ec2aaba2cc0117be5bed96`. The isolated acceptance
checkout remains clean at this exact runtime. Later feature-branch checkpoints
add documentation and evidence without changing the measured runtime bytes.
No source or reviewed golden changed during acceptance.

| Gate at the combined runtime | Result |
| --- | --- |
| Portable | 1,028 Dart tests and 162 Python controls pass; formatting, fatal-info analysis, corpus integrity and package dry-run pass. |
| Compiled JavaScript | Actual DOC acceptance, 51 media checks, 24 base WPF ISFs and 32 header ISFs pass. The single specified/native pressure-metric discrepancy is required explicitly. |
| Independent Open XML SDK | All 254 required DOCX outputs have zero validation errors. Both complete 538-file generations match byte for byte; positive/negative validator controls pass. |
| Native corpus | All 24 documents and 72 repeat imports complete without execution/import errors; nine initial renders are exact. The same source, renderer and font identities are used for the historical comparison. |
| Hosted CI | [Dart package run 43387392944](https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/43387392944) succeeds at this exact runtime. |

The [complete portable/schema evidence](evidence/continuation-c5ff75e7/README.md)
and [native corpus evidence](evidence/native-corpus-c5ff75e7/README.md) retain
original outputs, source identities, commands, tools, logs and independent
verification. Prior failed setup or authoring attempts remain separately
identified. Initial render equality and repeat equality are different claims;
source/native differences are not converted into synthetic passes.

The final native comparison includes a real tradeoff: exact repeats against
regenerated binary DOC decrease from **39/72 to 36/72**. All three changes are
Word14's newly retained tiled fills; the other 23 documents keep every recorded
render fingerprint, and all page/text/geometry comparisons remain unchanged.
Exact repeats against the previous and first parser imports remain 58/72 and
48/72. Word14's initial mismatch decreases from 35,146 to 30,704 pixels, with
summed RGB error decreasing from 10,774,592 to 6,725,615.

The [native review and source triage](evidence/native-corpus-c5ff75e7/README.md)
bind those measurements to exact images, FOPT operands and 14 retained packages.
They found no discarded explicit tile-coordinate operand, incorrect image
binding or geometry change. They retain the native tiled-fill disagreement and
unsupported original alternate DrawingML; they do not justify guessed offsets,
recoloring or dropping the restored fills to recover the old parity count.

## Accepted implementation and independent evidence

| Change | Result and qualification | Evidence |
| --- | --- | --- |
| Line Number style | Resolves the explicitly stored built-in character style, including source inheritance. The authored red/bold Courier New 14-point control is exact initially and through three native cycles. Source note labels and compatibility bits retain their independent meanings. | [Style contract](line-number-style.md) |
| OLE without a preview | Uses a reviewed visible generated label instead of an invisible empty textbox. Raw object bytes, distinct identities and story-local relationships survive. The label is explicitly generated and never described as a recovered source preview. | [Placeholder evidence](evidence/ole-visible-placeholder-20261113/README.md) |
| Fractional PICMID scale | Truncates positive fractional twips after exact bounds checks. Seven source controls now agree; the EMF corpus's word drift becomes zero. Its remaining raster difference is recorded separately. | [Scaling contract](picture-scaling.md) |
| Textbox paint | Preserves resolved opacity, dashes and simple offset shadows and applies the qualified border/frame relationship. Compact linked textboxes become exact in the 74420eb2 corpus. | [Paint controls](evidence/textbox-next-20261113/README.md) |
| Absent textbox width | Uses the documented 9525-EMU width only with a fully qualified enabled line and its seven-twip frame conversion. Raw source width remains absent. True absent plain/dashed and paired explicit controls are exact through nine repeats; disabled/zero/unresolved cases retain separate behavior. | [Default-width contract](textbox-stroke-defaults.md), [paired native controls](evidence/textbox-default-width-20261113/README.md) |
| Scaled gradients | Retains type 7 colors, both opacity operands, angle, focus and rotation. Opaque qualified controls match authored OOXML and controlled binary inputs. Native DOC export flattens gradients on repeat; the native VML reader ignores schema-qualified secondary alpha. | [Gradient evidence](evidence/textbox-fill-controls-20261113/README.md) |
| Bitmap fills | Resolves source BLIP references, retains embedded picture/texture fills and bounded monochrome patterns. The BMP wrapper adds only a file header to exact DIB bytes and is charged to the media budget. Pictures are exact through three cycles. Pattern/texture tiling differences between native import paths remain measured. | [Bitmap evidence](evidence/textbox-bitmap-controls-20261113/README.md) |
| Nonempty ink | Exposes complete bounded stroke/point/pen semantics, original packet coordinates and selected transforms and pressure metrics. Any unsupported or malformed stream exposes no partial strokes. Word-native ink emission remains inactive. | [Decoder contract](ink-decoding.md), [actual Windows base oracle](evidence/wpf-isf-oracle-20261113/README.md), [header oracle](evidence/wpf-isf-metrics-20261113/README.md) |

The first combined follow-up runtime is `74420eb2e0ec14401a0db5bcbb30ab6d202a2340`.
Its [portable/schema evidence](evidence/continuation-74420eb2/README.md) retains
954 passing Dart tests, 162 Python controls, actual DOC and 51 media JavaScript
checks, and 230 schema-valid DOCX outputs. Both complete 488-file generations
are deterministic, with unchanged source inputs.

Its [24-case native run](evidence/native-corpus-74420eb2/README.md) completes all
72 repeat imports. Nine initial renders are exact, compared with eight at
48bf3a. The compact linked-textbox raster becomes exact; the EMF case has zero
word drift. Existing source, renderer, font and tool identities match the
prior corpus. Other source/native attribution differences remain explicit.

## Ink checkpoints and source semantics

The initial full decoder checkpoint `bb7d98fe25cc6e3e69fdad3a2483a6fe08e83dfc`
has [retained acceptance](evidence/ink-decoder-bb7d98fe/README.md): 992 Dart
tests, 162 Python controls, 24 actual WPF ISFs in compiled JavaScript and
242 schema-valid DOCX outputs, including twelve nonempty OfficeArt envelopes.
An independent mutation/truncation review made 23,998 bounded calls without
exceptions or input changes.

The transform/pressure extension is separately saved as
`61d7e43c28dbaa2cde73d272ab62d009a34a8c66`. Its focused gate passes 72 tests,
the actual JavaScript gate checks all 24 base and 32 header ISFs, and all sixteen
ink schema controls validate. A second independent bounded review made 26,543
calls. The combined gate above binds its own exact source identity; these earlier
counts are never relabeled as a later runtime's results.

Two potentially misleading source/native comparisons have explicit treatment:

- ISF tag 20 defines a zero linear matrix, so its points collapse to the stored
  offset. Ordinary translation is represented by full affine tag 16. Both the
  original conventional-translation hypothesis and the actual Windows result
  remain retained; the specification, rather than the tag's informal name,
  determines decoding.
- A compact metric explicitly storing pressure maximum 2047 keeps that value.
  WPF writes that record but reloads it with maximum 1023. The decoder follows
  the specified prefix inheritance, retains raw packets, and records the
  unchanged native JSON as a native discrepancy. The verifier binds exact raw
  pressure values and both loads' metrics as well as normalized factors.

These controls establish bounded ISF inspection. They do not provide an
original ink-bearing Word document, OfficeArt placement, pressure-sensitive
outline rendering, comment association, or native Word editing coverage.

## App integration and remaining boundaries

The final measured CrispCloud runtime is
[`86d5a218853d8441afe8bc28f19cfe0adf4cd71e`](https://github.com/CrispStrobe/CrispCloud/commit/86d5a218853d8441afe8bc28f19cfe0adf4cd71e),
Git tree `765bf752b0095233192d38e678941e7ca92a76b8`, pinning parser `c5ff75e7`.
The [app acceptance and source receipt](https://github.com/CrispStrobe/CrispCloud/blob/fb81b2ace557964459189afd7c0c7d76b2c9557d/docs/evidence/word-final-c5ff75e7-20261113/README.md)
is saved at documentation/evidence checkpoint `fb81b2ace557964459189afd7c0c7d76b2c9557d`.
Its runtime bytes are unchanged from the measured commit.

The guarded inventory contains **1,258 exact parser files and 421 unchanged
other Office files**, or 1,679 entries. The reviewed projection makes 338
writes and no deletions. All 107 required Word tests across eight suites, 13
actual LibreOffice/Poppler assertions and production DOC/RTF/PPT/MSG JavaScript
checks pass. All 7,573 tracked runtime file hashes, 1,182 captured cohort hashes
and the production package configuration remain unchanged during acceptance.
Sync, Apple, crypto and ebook protection checks pass, with the two explicitly
expected macOS-only crypto skips retained.

The app retains Quds `6d6e77d14ead33de90c57ec5feb2ab3cc44f6501`, version
`1.2.9+22`, root lockfile, other dependency pins, policy decisions and unrelated
work. A fresh fetched checkout passes the exact working-byte/mode/Git-index
verification. The 87-record evidence bundle passes independent review and
22 resealed semantic corruption controls. Those controls now bind the inner
Dart command, all eight suite paths and exact event-to-suite relationships.
The existing app native cohort retains `partialFormatting`; its 13 assertions
do not certify every document or preserve a complete set of page rasters.

Hosted provider [run 43388810612](https://github.com/CrispStrobe/CrispCloud/actions/runs/43388810612)
succeeds at exact runtime `86d5a218`. The separate provider
[run 43390627091](https://github.com/CrispStrobe/CrispCloud/actions/runs/43390627091)
also succeeds at official-branch source `fb81b2ac`. Its
[complete output and queue receipt](https://github.com/CrispStrobe/CrispCloud/blob/9f924ff12321019c0f03a8483727af61fb3aef70/docs/evidence/provider-fb81b2ac-20261113/README.md)
is saved on `checkpoint/app-final-next-20261113`; all 25 retained result/lock
files agree with the downloaded artifact. The report checks 131 cases and
34 mocks in each of four engines, plus 363 cross-decryptions. It records
`passed: true` together with ten known gaps and `promotion_ready: false`.
This Office integration does not change provider behavior or claim complete
provider equivalence.

The same receipt retains a timestamped observation of
[Office run 43390627156](https://github.com/CrispStrobe/CrispCloud/actions/runs/43390627156)
at `fb81b2ac`: at 08:20:09 UTC its first job was queued with no assigned runner
and no executed steps. Read-only diagnosis found no same-branch active/pending
run or same-group blocker; no workflow was restarted or cancelled. That dated
observation remains unchanged. The same run subsequently completed successfully
at the exact `fb81b2ac` head: both `host-roundtrip` and `external-schema`, including
every required step, succeeded.

The [complete hosted Office proof](https://github.com/CrispStrobe/CrispCloud/blob/12087dc89fa7f2d417e32042626c27a0656865cc/docs/evidence/office-hosted-fb81b2ac-20261113/README.md)
retains all 122 required app exports, 468 schema-valid
Office outputs, 122 rendered PDFs and 158 decoded RGB pages. All 122 native
conversions succeed on their first attempt. The repeated-save gate renders the
app/engine's save-one, save-two and save-three exports and verifies 66 comparisons
across 33 groups, comparing save one with saves two and three. Eighteen exports
have authored picture checks; 23 other files are render-only. The result has no
sibling-baseline substitutions or excluded inputs. Its LibreOffice 24.2.7.2
renderer is distinct from the local parser corpus's LibreOfficeDev 26.8 toolchain.

Committed-source verification runs before the existing temporary system-SQLite
hook. The hosted coverage inputs correctly fingerprint the hooked test-time
`pubspec.yaml`; its deliberate change is not described as unchanged Git source.
The root lockfile remains unchanged. The 2,624/4,138 instrumented-line result
applies to 12 scoped Office source files. Earlier successful
Office CI remains attributed to its earlier checkpoint; later evidence-only
commits do not change the runtime or hosted head these measurements describe.
Both original artifact ZIPs, complete decoded logs and source receipts are
retained. Independent review verifies the complete bundle and all 33 semantic
corruption controls under normal and optimized Python. Those controls now
reject contradictory SDK exception records and substituted CI step names.

General Word14 grouped/relative-size metadata, unsupported OfficeArt effects,
arbitrary GDI behavior, broader review topology and native Word ink are not
certified by these bounded controls. Source note labels/tables, absent page-size
defaults and explicit compatibility bits are not rewritten to imitate native
loss. No reviewed golden, original failed observation or binary source is
replaced to create an apparent pass.

Keep exact runtime pins and complete evidence archives. Record future native
or schema results against the actual clean source commit, including failed
attempts separately. A documentation-only or evidence-only addition does not
change the measured runtime or require another app parser roll.
