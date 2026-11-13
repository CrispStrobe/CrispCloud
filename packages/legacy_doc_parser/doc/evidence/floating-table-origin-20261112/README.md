# Floating table origin and padding evidence — 2026-11-12

The final table implementation is local source commit
`76fa966d9b2b68cce69ebeba013705c5577ef8ba`, following the rejected incomplete
candidate `f70c4bef610353ec81e208f51552df35569eecb5`. The combined continuation
runtime is remotely saved as `0c3e59682952cce0e11301afec789e7ae2a1256a`.
This evidence preserves both the improvement and the counterexample that
prevented the incomplete candidate from being shipped.

## Measured failure and source cause

On clean baseline `d11fa0e297f8058c8048c71537f2392457baa624`, Word16's initial
converted table moved left by 5.45 points and up by 0.05 points. A repeat import
added another identical displacement. Its earlier 56.4-point vertical error
had already been removed by retaining floating-table properties.

Two source omissions explain the remaining drift. The DOC stores absolute
coordinates in `XAS_plusOne` / `YAS_plusOne` operands. The model correctly
retains the physical distances, but the target writer had not restored Word's
OOXML plus-one encoding. Separately, the source table has zero left/right
row-wide padding defaults. Its bottom padding of 113 twips belongs to the
cells, while the table style supplies zero top/bottom defaults. Writing cell
padding alone left the target table default at 108 twips. The retained
output-only variants isolate the one-twip and 108-twip effects independently.

The first candidate retained row-wide defaults and restored plus-one encoding.
It fixed Word16's repeated displacement, but an independent 240-twip padding
and one-point border control disproved its generality: horizontal drift
worsened from -5.95 points on the baseline to -12.50 points. That failed
candidate is preserved separately, including its native report. Its exact
source tree was also saved remotely at `ed3b6b7734ec9aad2b09b0480ea3d7c2005f5586`
on `checkpoint/office-table-origin-investigation-20261112`.

## Bounded final mapping

For an absolute horizontal position, the final writer encodes:

```
tblpX = source physical offset + shared row-grid origin
        + emitted table-default left padding
        + supported single-border outside extent + 1
```

The unadorned single-border extent is `floor(widthEighthPoints * 5 / 4)` twips.
It is computed from the first source cell's resolved left border, including
row/style inheritance. An asymmetric two-cell control verifies this edge in
both LTR and RTL: using the last cell's right border instead adds 0.65 points.
The .75-point, one-point, and 1.25-point controls independently verify the
integer rounding. Signed row origins of -108 and +480 twips verify the
separate row-grid term.

The padding term is the table default, not a per-cell override. Controls with
zero cell padding over a 240-twip table default, and 240-twip cell padding over
a zero table default, verify this distinction. Inherited base-table-style
padding is resolved before direct row defaults. Later rows retain their
independent defaults through `tblPrEx/tblCellMar`, including absent, nil,
explicit, and inherited-style resets.

Named horizontal placements retain their original `tblpXSpec`; they do not
receive this absolute-position adjustment. The target stored coordinate must
fit the signed 16-bit range, otherwise conversion fails explicitly. Source
absolute-offset bounds remain unchanged. Vertical absolute positioning only
restores plus-one encoding.

Compound, spaced, shadowed, or framed borders are preserved as source border
properties but their contribution to the floating origin is not guessed.
These cases produce `partialFormatting` and a `floatingTableBorderOrigin`
evidence record. This is a stated boundary of the mapping.

The source/target distinction is supported by
[MS-DOC 2.6.3 Table Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469):
`sprmTDxaAbs` references the physical table origin, while margins, spacing, and
border width contribute to the actual edge. The target plus-one rule is
[MS-OI29500 2.1.162(e)](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/4175e818-958f-4b4f-b6f7-17003f1721b5).
The retained DOC inputs, native exports, negative controls, text measurements,
PDF border vectors, and rasters support the bounded geometry conversion.

## Verification and remaining differences

- 73 focused table tests pass, including signed offsets, every named sentinel,
  row/style padding resets, asymmetric RTL borders, overflow, and explicit
  diagnostics outside the supported border mapping. Scoped analysis is clean.
- All nine existing inline/nested table-origin controls still match their
  frozen native goldens exactly. The final compiled converter reproduces all
  OPC parts of those tested outputs byte for byte.
- Thirteen explicit-page/font context controls and four signed-origin or
  asymmetric-cell controls preserve the full-page 72-dpi RGB raster and every
  PDF border vector rectangle/width exactly. The independent PDF measurement
  uses PyMuPDF **1.26.6**. One symmetric RTL control retains a 0.05-point text
  bounding-box rounding difference despite identical raster and border vectors.
- The final compiled converter's actual DOCX outputs match all OPC parts of
  the independently rendered context hypotheses. The files retain distinct
  names and provenance; hypothesis XML is not relabeled as parser output.
  The two signed row-origin controls additionally have fresh PDF renders of
  the actual final runtime output.
- On the retained Word16 three-cycle run, the initial table origin and every
  repeated origin are exact, with zero accumulating displacement. Each
  regenerated binary render matches the original source word boxes. A fixed
  +1.446-point placement difference remains for the middle word `für`; the
  first and third words match exactly. Pages, word sequence, and layout text
  remain stable. RGB is still different for this real document.
- The final Word16 output is byte-identical in every OPC part to the corrected
  candidate output used in that three-cycle run. The full combined runtime's
  native/schema gates are recorded separately by the continuation checkpoint.

The renderer for both retained Word16 runs is
`LibreOfficeDev 26.8.0.0.alpha0 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.
Reports retain exact compiler, executable, source, fonts, inputs and stage
identities. Neither input DOC nor a reviewed golden was modified.

## Retained files

`baseline-d11fa0e/` and `candidate-f70c4be/` contain independently verified,
compressed native reports, all measured document/PDF/text/raster artifacts,
and hash inventories. The existing native sealer excludes only Office
profiles, temporary files, and the compiled executable whose hash remains in
the report.

`diagnostics.tar.xz` contains literal fixture/probe scripts, the incomplete
candidate and all discriminating variants, initial and refined context
matrices, actual final runtime DOCX outputs, vector/raster measurements,
portable logs, source property observations, and all-part equivalence
receipts. `diagnostics.manifest.json` pins every retained byte and the archive;
`seal_diagnostics.py` verifies the archive without extracting it. Original
measurement files are immutable; the archive preserves their initial names.
Four additional actual-runtime row-padding reset outputs are retained for the
separately receipted extra schema gate. Their presence makes no native-render
claim for those four controls.

Verify the durable diagnostics with Python's standard library, without the
original workspace, Office, or any extraction:

```sh
python3 doc/evidence/floating-table-origin-20261112/seal_diagnostics.py \
  --verify doc/evidence/floating-table-origin-20261112
```

This checks the archive size/hash, exact manifest coverage, unique safe regular
member paths, and every member's size/hash. It rejects duplicates, links,
traversal paths, unexpected or missing members, and byte changes.
