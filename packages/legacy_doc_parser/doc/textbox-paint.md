# Resolved paint on editable textboxes

Textboxes now retain the solid-fill opacity, simple-line opacity, dash, join
and cap, and simple offset-shadow properties already represented by the
OfficeArt model. The previous textbox writer emitted only fill/stroke colors
and explicit border width. The shape writer's existing paint serialization is
shared, with independent guards for fill, stroke and shadow: an unresolved
fill does not discard a resolved line, and an unresolved shadow is not emitted
as an apparently complete simple shadow.

Explicit zero opacity, disabled line/shadow flags, zero offsets and absent
properties remain distinct. Paint parsing retains an absent line width; the
[qualified frame path](textbox-stroke-defaults.md#qualified-enabled-line-with-an-absent-width)
separately couples a documented default to its frame conversion. Paint changes
do not relax the general unsupported-property guard or flatten pattern,
texture, picture or gradient fills. Editable text and original binary
artifacts remain retained with the existing partial-formatting limitation.

## Frame relationship

Dash patterns and simple offset shadows do not change a simple border's
outside thickness. The source-to-target frame calculation therefore applies
to these resolved cases as well as solid borders, retaining the original
source coordinates in the model and evidence. Unsupported shadow properties,
other shadow types, compound borders and the other guards documented in
[textbox-frame-borders.md](textbox-frame-borders.md) remain excluded.

This follows the pinned native importer's
[`GetEscherLineMatch` and `MatchSdrBoxIntoFlyBoxItem`](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/ww8graf.cxx):
the outside half-width is calculated before dash mapping, while shadow
properties are assigned separately. The
[VML text-frame importer](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/oox/source/vml/vmlshape.cxx)
uses the emitted frame rectangle directly and maps fill opacity to the frame's
background transparency. Source flags keep the independent use-bit semantics
specified for [fill](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/baf2613d-c676-43c8-8077-828bdcc70dca)
and [line](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/b359a9d1-941b-49ad-8462-7c0bb894d125).

## Independent controls

`tool/fidelity/textbox_paint_probe.py` authors small OOXML inputs independently
of the DOC converter, then retains original, native binary, baseline-parser
and candidate-parser renders separately. Cases run sequentially with fresh
native profiles. The reports record source/compiler/tool/font identities and
lossless 72-DPI RGB rasters, and refuse changing source inputs. An initial
probe correctly stopped before native measurement when Dart created the
baseline's previously absent package configuration during compilation; that
failure is retained separately from completed runs.

The completed controls establish exact binary-to-parser renders for 50% and
0% solid fill opacity, the 2-point dashed border, and an opaque simple offset
shadow. The first two previously had raster differences; the latter two also
had 1-point word displacement. Each corrected control matches its regenerated
binary exactly through three repeat imports. The opacity and dash controls
also remain exact to the first parser import. The opaque shadow has a native
bridge raster change in the first repeat, which remains separately recorded.
Plain, disabled-shadow and line-opacity controls retain their previous exact
output. The line-opacity control does not prove that the
native bridge stores transparency on text-frame borders; the separate model
tests protect its serialization.

The translucent-shadow source is a retained counterexample. The native bridge
stores color `0x7F665544`, whose high byte is not a resolved OfficeArt RGB color
operand, and changes unequal x/y offsets to their mean. Its color remains
unsupported rather than interpreting unknown flags as RGB or claiming complete
shadow preservation. The opaque-shadow result is qualified against its exact
binary input; the native export's literal offset normalization remains in the
retained source properties even where the original render matches.

The Word14 source remains a separate follow-up. Its six textboxes use solid,
pattern, texture, picture and scaled-gradient fills plus absent border widths and
other properties. Its complete layout is not certified by these small paint
controls, and the original failures and reviewed goldens are unchanged.

## Scaled gradients

The additive gradient path retains MS-ODRAW fill type 7 (`msofillShadeScale`),
both direct RGB colors and opacities, signed fixed-point angle, signed focus,
and the independently used rotate-with-shape bit. Type 8 is `msofillShadeTitle`;
it is a different, host-defined effect and remains unsupported. The source
[fill enumeration](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/e96eecf8-0d2f-48a8-a5ee-dc9ffb6c82ab)
and [gradient angle](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/d49b1931-da11-452f-a78b-5b5e40e1d0b3)
map to VML `type="gradient"`, `color2`, `angle`, `focus`, and `rotate`.
The secondary opacity uses the schema's
[`o:opacity2`](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.vml.fill.opacity2).
Absent operands and explicit zero/false remain distinct. Unknown color
operands, alternate fill rectangles, multistop gradients, other gradient
types, and unresolved modifiers continue to block the active gradient element.
Empty inherited BLIPs do not describe an active pattern in the solid/gradient
subset or in a solid line.

The [sealed gradient controls](evidence/textbox-fill-controls-20261113/README.md)
retain an independent OOXML source and its original native DOC export. That
exporter flattens a textbox gradient to a solid midpoint color, so a separate
bounded source authoring helper restores the explicitly declared gradient FOPT
operands in a new DOC copy. It updates record lengths and relocates OfficeArt
to appended table bytes; the source FSPA coordinates, other table contents,
and original binary export remain unchanged. This avoids mistaking an already
flattened binary for gradient coverage.

Opaque 0% and 100% focus, a 45-degree gradient, and a negative-angle negative
axial focus render exactly against both the authored OOXML and the controlled
DOC. The prior parser lost paint and shifted the text by 1 point. Each of the
three repeats matches its own regenerated binary, while the first native DOC
export flattens the gradient; repeat stability is therefore reported separately
from preservation of the initial appearance.

The unequal-opacity control remains a native-consumer discrepancy. The emitted
source operands match the independently authored OOXML exactly, but the pinned
native VML reader reads unqualified `XML_opacity2` in
[`vmlshapecontext.cxx`](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/oox/source/vml/vmlshapecontext.cxx)
instead of the schema's Office-qualified attribute. It ignores the secondary
alpha on both independently authored and parser-produced VML. The parser keeps
the schema-correct attribute, the explicit source value, and the existing
partial-formatting limitation; it does not replace the gradient with a bitmap,
change colors to mimic this renderer, or emit an invalid unqualified attribute.

## Embedded picture, texture and monochrome pattern fills

Anchored textbox fills now resolve the scalar, one-based `fillBlip` reference
when its `fBid` flag is set and the fill is active. Drawing defaults and later
property layers preserve or replace that flag with the operand. A local
unflagged or complex override does not inherit a stale BLIP flag. Explicitly
disabled fills, unanchored shapes, and inline PIC fill operands do not fetch
unrelated global images. This follows the source
[`fillBlip` contract](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/df4c1209-6ed5-4cd5-b3de-f0a86618b018).
The fill model retains the resolved image identity and original stored comment.
Comment names remain inert; nonzero file/URL/link flags remain guarded under
the source [BLIP flags definition](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/3192b5fc-67ab-4255-93e6-c23dae102056).

Qualified fill types 3, 2 and 1 emit VML `frame`, `tile` and `pattern`
respectively, using an internal image relationship. Picture/texture assets
reuse the existing validated image path. The pattern subset accepts exactly
an 80-byte, 8-by-8, one-bit, uncompressed BITMAPINFOHEADER DIB with a two-entry
black/white palette. Both row orientations and palette orders are retained.
The source [DIB record](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/1393bf5e-6fa0-4665-b3ec-68199b555656)
may have one or two UIDs. Its raw bytes and source reference remain unchanged;
the package image adds only the 14-byte BMP file header required for the
[bitmap file format](https://learn.microsoft.com/en-us/windows/win32/wic/bmp-format-overview).
The parser charges the complete additional buffer to its media budget, and
the package writer counts all embedded bytes. Other dimensions, bit depths,
compression, header variants, palette values or malformed records stay inert.

Pattern foreground/background colors, both opacity operands, and the used
rotation bit remain source-valued. The recolor selector is harmless only when
both selectable modifiers have their documented default `0x20000000` values;
active unresolved modifiers retain their guard. The relevant operands are
[`pictureFillCrMod`](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/684009ac-5b1f-4e2b-abd7-c5139afb8409)
and [`fillCrMod`](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/2f24ad18-bf89-42f9-909f-3510194aa195).
Alternate fill rectangles, explicit unmodeled tile sizes/origins and other
active unknown properties continue to suppress the active fill element.

The independent picture control matches both its authored OOXML and native
DOC exactly. Texture and controlled DIB patterns at 96 and 75 DPI match the
authored OOXML exactly, with zero word displacement against native DOC; their
native DOC rasters differ in tiling. The original native pattern export is
retained as a separate observation because it becomes a recolored type-2
texture. It cannot qualify type-1 support. The bounded source helper instead
replaces one global BLIP slot, appends a separately authored DIB record, and
sets the literal type-1 operands without changing FSPA coordinates.

The pinned native import paths differ: the binary
[`ApplyFillAttributes`](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/filter/source/msfilter/msdffimp.cxx)
and [`MatchSdrBoxIntoFlyBoxItem`](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/ww8graf.cxx)
convert bitmap text-frame fills into a legacy tiled brush; the
[VML fill importer](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/oox/source/vml/vmlformatting.cxx)
uses a bitmap fill and reconstructs pattern colors. The remaining raster
difference is retained as a consumer-path discrepancy, not a reason to add an
unproven tile offset or to recolor the retained source image. The whole Word14
layout and absent-width frame semantics remain separate from this fill scope.

The [sealed bitmap observations](evidence/textbox-bitmap-controls-20261113/README.md)
retain the pre-fix picture control, native pattern export counterexample,
independent DIB controls and twelve repeated imports with their original
source/build identities. Picture and texture imports remain stable through all
three cycles; native pattern export becomes a colored texture on its first
repeat. All twelve cycles retain zero word displacement.

Eight required `textbox-fills/` schema cases exercise gradients, image fills,
and the unknown gradient/DIB guards from independently declared FOPT operands.
They include the correctly qualified secondary opacity attribute. Unit tests
also cover BLIP flag inheritance, disabled/unanchored/PIC controls, inert names,
malformed DIB variants, exact wrapper bytes and immutable source data.
