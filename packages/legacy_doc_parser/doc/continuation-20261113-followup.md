# Office fidelity follow-up — 13 November 2026

Continue from `feature/office-fidelity-gaps-20261113` in
[legacy-doc-parser](https://github.com/CrispStrobe/legacy-doc-parser/tree/feature/office-fidelity-gaps-20261113)
and [CrispCloud](https://github.com/CrispStrobe/CrispCloud/tree/feature/office-fidelity-gaps-20261113).
This follow-up supersedes integration guidance in the
[first-pass handoff](continuation-20261113.md); its original measurements and
rejected controls remain unchanged. Implementation, independent evidence and
app integration are saved in separate remote checkpoints.

## Accepted implementation and independent evidence

| Change | Result and qualification | Evidence |
| --- | --- | --- |
| Line Number style | Resolves the explicitly stored built-in character style, including source inheritance. The authored red/bold Courier New 14-point control is exact initially and through three native cycles. Source note labels and compatibility bits retain their independent meanings. | [Style contract](line-number-style.md) |
| OLE without a preview | Uses a reviewed visible generated label instead of an invisible empty textbox. Raw object bytes, distinct identities and story-local relationships survive. The label is explicitly generated and never described as a recovered source preview. | [Placeholder evidence](evidence/ole-visible-placeholder-20261113/README.md) |
| Fractional PICMID scale | Truncates positive fractional twips after exact bounds checks. Seven source controls now agree; the EMF corpus's word drift becomes zero. Its remaining raster difference is recorded separately. | [Scaling contract](picture-scaling.md) |
| Textbox paint | Preserves resolved opacity, dashes and simple offset shadows and applies the qualified border/frame relationship. Compact linked textboxes become exact in the 74420eb2 corpus. | [Paint controls](evidence/textbox-next-20261113/README.md) |
| Absent textbox width | Uses the documented 9525-EMU width only with a fully qualified enabled line and its seven-twip frame conversion. Raw source width remains absent. True absent plain/dashed and paired explicit controls are exact through nine repeats; disabled/zero/unresolved cases retain separate behavior. | [Default-width contract](textbox-stroke-defaults.md) |
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
calls. The eventual combined gate must bind its own exact source identity;
these earlier counts are never relabeled as a later runtime's results.

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

The verified intermediate CrispCloud checkpoint is
`6f2e3245b7971d620410a65e75bf54b04132319a`, pinning parser `74420eb2`.
Its guarded inventory contains 948 exact parser files and 421 unchanged other
Office files. It retains the existing Quds pin
`6d6e77d14ead33de90c57ec5feb2ab3cc44f6501`, app version `1.2.9+22`, root
lockfile, production package configuration and unrelated app work. Hosted
provider conformance and Office host/schema jobs at that exact commit succeed.
Later parser changes require a separately verified app roll and source index.

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
