# Explicit textbox borders and frame coordinates

The binary Word textbox anchor is retained verbatim in the parser model. For a
resolved, simple textbox border with an explicit width, the DOCX writer converts
that inner shape rectangle to the outer VML text-frame rectangle. This closes
the repeated 0.35-point movement of the retained 0.75-point header textboxes
without changing source coordinates or inserting an unconditional offset.

## Source and target contract

[MS-DOC Spa](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/26fcafc0-554b-46bc-aebf-c755276c77a4)
stores the shape rectangle in twips with separate page, margin or text origins.
[MS-ODRAW lineWidth](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/fb88b56e-2c2d-41c2-a0c8-98129e913b89)
stores the line width in EMUs.
[lineStyle](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/5356921f-316e-489e-b624-9a7fbd9705f3)
is a noncomplex, non-BLIP property, defaults to a simple line and uses the five
values in
[MSOLINESTYLE](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/989ff6ab-a605-40dd-b6ce-5b679a856cb7).
An explicit simple style is now resolved; compound and malformed styles remain
unsupported evidence.

The pinned LibreOffice
[binary importer](https://github.com/LibreOffice/core/blob/9a3be2502bf7762400fd0b655b6e42714cf2bb36/sw/source/filter/ww8/ww8graf.cxx)
implements the border convention in `GetEscherLineMatch` and
`MatchSdrItemsIntoFlySet`: for a simple textbox border, half the width is outside
the source rectangle; the receiving text frame moves its origin outward and
adds both outside halves to its extent. The integer division occurs in source
twips. The corresponding
[VML importer](https://github.com/LibreOffice/core/blob/9a3be2502bf7762400fd0b655b6e42714cf2bb36/oox/source/vml/vmlshape.cxx)
creates a text frame directly from the VML rectangle and maps stroke weight and
text insets to frame-border properties. It does not repeat the binary outside
border conversion. These are separate import paths, rather than a native DOCX
export used as a source golden.

For explicit widths representable in whole source twips, the writer uses:

```
outside = (widthEmu div 635) div 2
targetLeft = sourceLeft - outside
targetTop = sourceTop - outside
targetWidth = sourceWidth + 2 * outside
targetHeight = sourceHeight + 2 * outside
```

For example, 9,525 EMUs is 15 twips. Its outside extent is seven twips, so the
retained header anchor at 1,447 twips becomes a VML frame at 1,440 twips, or
72 points. A 3-point border instead uses 30 twips outside; a 0.05-point hairline
uses zero. Text insets and anchor reference frames keep their source values.
The conversion evidence records `outsideBorderTwips` next to the unmodified
source metadata.

## Deliberately bounded output

The conversion applies only to type-202 textboxes with a resolved simple
border, explicit integral-twip width, absolute position, no rotation, reflection,
group/child/OLE flags, automatic text margins or negative insets.
Unknown properties and compound borders prevent this conversion. Disabled and
zero-width borders retain their original rectangle. Fractional-twip widths
remain unchanged until their source/target rounding contract is independently
covered. Bounds checks reject an expanded rectangle outside signed 32-bit
coordinates.

Resolved dash patterns and simple offset shadows use the same outside border
thickness. The binary importer's `MatchSdrBoxIntoFlyBoxItem` computes the
outside thickness before mapping the dash style, and shadow properties are
applied separately. [Textbox paint controls](textbox-paint.md) verify the
corresponding layout and repeat behavior. Unresolved shadow properties and
other shadow types still prevent the transform.

An absent source width is still absent in the model. A fully resolved textbox
with an explicitly enabled source line can now use the documented 15-twip
default together with this same seven-twip outer-frame transform. Source and
emitted widths are recorded separately. Unspecified line-enabled flags and
unresolved frames remain unforced; see the [paired source-default controls](textbox-stroke-defaults.md#qualified-enabled-line-with-an-absent-width).
The failed standalone default-width
experiment and its repeat-import counterexample remain documented in
[textbox-stroke-defaults.md](textbox-stroke-defaults.md). In particular, this
change does not materialize the default on Word 14's six textboxes or apply a
global 0.35-point correction.

The focused tests use literal widths, source rectangles, reference frames and
negative contexts. Native validation additionally compares independently
authored OOXML, its binary bridge, parser output and repeated imports as
separate stages; native DOCX exports are retained as observations only.

## Measured checkpoint

The 11 independent native controls cover 0.5, 0.75, 1, 2.35 and 3-point borders;
zero and disabled borders; explicit insets; page, margin and text origins; and
a table nested in a header textbox. Every resulting parser document matches
its binary source in word coordinates, layout text and RGB raster. The old
writer's corresponding border-dependent drifts ranged from 0.25 to 1.5 points.
The disabled control's original OOXML-to-DOC bridge moves by 0.05 points; the
parser matches that binary source exactly, so this separate bridge change is
retained rather than attributed to the parser.

Both retained header alias cases now match their source exactly on initial
import and through all three native repeat cycles. The previous 0.35-point
per-cycle movement is zero in all six repetitions, including comparisons with
each cycle's binary input, previous parser import and first parser import.
These are measurements on the pinned LibreOffice/Poppler environment, not a
claim about every VML consumer. Focused Dart checks pass and static analysis
reports no issues.
