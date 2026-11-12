# Explicit clearance around Word drawings

The parser preserves explicit OfficeArt distances between a floating drawing
and surrounding document text. These are separate from the text margins inside
a textbox, its wrapping mode, and its anchor coordinates. The previous converter
dropped these properties, including the six Word 14 textboxes' top/bottom
clearances.

## Source contract

| Binary property | Side | Unit in Word | VML style | DrawingML attribute |
| --- | --- | --- | --- | --- |
| `0x0384` | Left | EMU | `mso-wrap-distance-left` | `distL` |
| `0x0385` | Top | EMU | `mso-wrap-distance-top` | `distT` |
| `0x0386` | Right | EMU | `mso-wrap-distance-right` | `distR` |
| `0x0387` | Bottom | EMU | `mso-wrap-distance-bottom` | `distB` |

[MS-ODRAW left](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/6cda98b1-00fe-403c-ad55-6fc205d57ff2),
[top](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/5e712bf4-af16-4dad-9af4-9c5395188eac),
[right](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/195ee865-5354-4aa4-b88d-d5b29a0bb62c),
and [bottom](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/ed07211a-12df-4f31-b841-6861222e8a48)
define signed scalar minimum distances. The bounded active mapping accepts
nonnegative signed-32-bit values. Negative and complex operands remain
unsupported-property evidence; no unsigned reinterpretation or arbitrary length
is emitted. An invalid BLIP-reference flag rejects the malformed property.
Caller-built models outside that supported range reject conversion.

Each explicitly stored side survives independently, including zero. Drawing
defaults supplied by an OfficeArt property record inherit normally, and a local
zero overrides its inherited value. Absent fields stay null in the model. VML
textboxes and editable shapes emit only present properties, in points using
12,700 EMU per point. Floating pictures use exact integer EMUs in their
DrawingML anchors. This change does not modify the pre-existing DrawingML
fallback of zero when a property is absent; reconciling that with the binary
format's horizontal default is separate work.

The unchanged Word 14 source `word14-margin-origin.doc` contains six explicit
top/bottom pairs in `1Table`, at offsets `5595`, `7602`, `12007`, `13991`,
`15976`, and `26158`. In each pair the second record starts six bytes after
the first. The literal byte sequences are `85 03 98 B2 00 00` and
`87 03 98 B2 00 00`: 45,720 EMU, or 3.6 points. Its left/right properties
are absent. The tests check those exact source bytes independently of the
OfficeArt decoder and the DOCX writer, then require both clearances on all
six converted textboxes.

## Scope and checks

Focused controls cover side/unit mapping, per-side inheritance, explicit zero,
absence, four complex operands, four signed-negative operands, unrelated
unsupported shape properties, unchanged signed anchor coordinates, independent
textbox inset/wrapping controls, and caller-model bounds. Floating pictures,
editable shapes and textboxes share the validated distance mapping.

The HTML preview keeps its existing linear content presentation. It does not
imitate page layout with CSS margins or claim wrapping fidelity. Native layout
must be measured separately. The shape rectangle, table depth, source fonts,
reviewed goldens and the previously measured 0.35-point border/placement
difference are not adjusted by this property-preservation change.

The [retained native comparison](evidence/textbox-wrap-stroke-20261112/README.md)
records the baseline, the wrap-only initial and three-cycle results, and the
withdrawn stroke-default candidate. Restoring the clearances repairs the Word
14 reading-order difference. Remaining coordinate and RGB differences stay
visible in the receipts; the fix is not a claim of exact visual fidelity.
