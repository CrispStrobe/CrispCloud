# Solid shape context and editing hints

The retained `officeart-shapes.doc` control now produces three editable native
shapes: a rotated rectangle, an ellipse, and an explicit line/cubic custom path.
The previous complete-shape gate rejected them because it did not distinguish
inactive background colors, the explicit table-cell layout flag, and an editing
hint from unresolved drawing effects. This increment maps only those bounded
cases. All original OfficeArt records remain unchanged in the conversion's
evidence parts.

## Property interpretation

| Source property | Bounded interpretation | Cases still unsupported |
| --- | --- | --- |
| `fillBackColor` (`0x0183`) | Inactive when the resolved fill is scalar/default solid. The [MS-ODRAW fill-color table](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/1c43c247-d23b-450c-b729-b0b4a54aa617) explicitly marks this color unused for solid fill. | Complex operands, unresolved fill type, pattern and gradient contexts. An inactive system color is never decoded as foreground RGB. |
| `lineBackColor` (`0x01C2`) | Inactive for scalar/default solid line when no used opaque-background flag enables an additional stroke. [MS-ODRAW line Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/b359a9d1-941b-49ad-8462-7c0bb894d125) define the extra background-colored line and its independent use bit. | Complex operands, non-solid or unresolved line types, and active opaque-background strokes. |
| `fNoLineDrawDash` in `0x01FF` | Value bit 0 is effective only when use bit 16 is set. An absent, unused, or explicitly false value does not request an extra stroke. The fallback is dormant when `fLine` is true, including its source default. | Explicit true combined with resolved `fLine=false` requests a dashed indication. This fallback stroke has no validated mapping, so `0x01FF` remains unsupported and the original OfficeArt is retained. |
| `fLayoutInCell` in `0x03BF` | Value bit 15 is used only when bit 31 is set. Absent/unused means the source default, true. Explicit values map to VML `o:allowincell` for shapes/textboxes and DrawingML `wp:anchor/@layoutInCell` for pictures. | Every other explicitly used group Boolean remains unsupported for editable shape emission; complex group words remain unsupported. |

[MS-ODRAW Group Shape Boolean Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/a0ae6aa5-16e4-4550-87a2-b8ca180c7fd7)
defines independent value/use pairs. The parser therefore merges this property
per use bit across defaults and subsequent property records. A child containing
only explicit `layoutInCell=false` cannot erase an inherited hidden, printing,
wrapping or overlap flag. The resolved word is exposed on the model; the actual
source property words remain in the retained OfficeArt artifact. The high use
bit is checked in both the Dart VM and compiled JavaScript, including the
inherited-hidden adversarial case.

The same per-use-bit merge applies to line Boolean properties. A local
`fLine=false` cannot clear an inherited `fNoLineDrawDash=true`; a local explicitly
false dash flag can clear it. An active dash request prevents the normal editable
shape path from presenting a plain invisible line as a complete interpretation.
Overriding the ordinary line to true makes an inherited fallback flag dormant
and retains supported editable output.
It also keeps such textbox borders outside the resolved frame-geometry subset.
The converter retains source evidence and reports `partialFormatting`; it does
not claim to render that fallback dash.

## Zero-count SymmetricCurve editing hint

The exact segment word `0xB300` encodes an escape with subtype `0x13` and zero
point count. [MS-ODRAW MSOPATHESCAPE](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/37269b23-7e5f-4812-ba8d-f08f745bf505)
defines subtype 19 as `msopathEscapeSymmetricCurve`, a Bezier editing instruction
about vertex joints and tangent visibility. It is distinct from arc, additional
point, color-change, no-fill and no-line escapes. The
[pinned independent LibreOffice reader](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/filter/source/msfilter/msdffimp.cxx)
retains this code as an unknown editing segment; the explicit path commands
provide its rendered geometry.

The parser accepts only this zero-count word after a current point and before
the path's end. It consumes no additional vertex and retains the source vertex
index and escape code as an immutable editing hint. Move, line, cubic, close,
and end commands still have to consume the entire validated point array. Other
escapes, client escapes, nonzero counts, misplaced hints and malformed point
references do not gain active rendering. Hints count toward both per-shape and
cumulative complexity budgets.

The emitted path remains editable, but native tangent-editor behavior is **not
mapped**. The conversion reports `partialFormatting`, counts
`shapePathEditingHints`, and writes explicit hint records to its evidence
manifest. This distinction is required even when the rendered curve matches.

## Native evidence and remaining differences

The [fixture provenance](../test/fixtures/fidelity/officeart-shapes.provenance.json)
records the independently authored DOCX, its generator, the exact native DOC
bridge, hashes and pinned Office version. The native DOC is retained as an input;
portable parser and schema checks do not have to regenerate it.

`tool/fidelity/shape_context_probe.dart NEW_DIRECTORY` writes exactly one DOCX,
`officeart-shapes.docx`, plus its structural manifest. The separate native probe
renders the authored DOCX, retained native DOC and converted DOCX independently:

```sh
python3 tool/fidelity/shape_context_render.py --dart /path/to/dart \
  --office /path/to/soffice --output build/shape-context
```

The retained [native receipt](evidence/officeart-context-native.json) records:

- All three shapes are emitted with explicit `layoutInCell=false`; all five
  editing hints are retained as evidence. Native page dimensions and text match.
- Native-DOC versus converted fill/stroke colors and stroke widths match.
  Shape bounds differ by at most `0.0499878` pt. The custom path keeps its
  ordered line/cubic commands and every endpoint/control-point coordinate
  differs by at most `0.0500031` pt, within the declared `0.1` pt tolerance.
- The rectangle uses separate fill and stroke PDF operators after conversion.
  The receipt retains raw operator counts of three versus four. For shape-level
  comparison it joins only adjacent fill/stroke operators with identical
  rectangles **and exact geometric line edges**; the raw paths are not removed.
- RGB comparison at 144 DPI remains false: authored-to-native-DOC changes
  3,637 pixels, authored-to-converted changes 4,550, and native-DOC-to-converted
  changes 6,163. The rectangle's dash arrays differ in all three routes and are
  recorded verbatim. No pixel-exactness claim follows from the geometry gate.

The authored OOXML also contains a shadow whose enabled state is already lost
in the native DOC bridge. The parser preserves the actual DOC's disabled state.
Neither missing source semantics nor dash spacing is reconstructed by tuning
to the rendered golden. This increment does not add arbitrary fills/effects,
native tangent editing, or general table-relative layout equivalence.
