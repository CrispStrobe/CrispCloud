# OfficeArt geometry and metafile fidelity

This document records the additional media subset separately from the original
[opaque-preservation contract](media-preservation.md). Parsing a record,
rendering it portably, and retaining it for a native Word renderer are distinct
capabilities. The input DOC is never modified and no GDI, Office, macro, script,
external resource, or embedded-object handler is invoked by this package.

## Referenced EMF and WMF

The parser follows the existing PICF or BStore references. For EMF/WMF BLIPs it
reads one or two UIDs and the 34-byte OfficeArt metafile header, then extracts
the raw file data. Both uncompressed data and RFC1950 zlib are supported.
The original OfficeArt record remains an exact opaque artifact; decompressed
file bytes are a separate representation with an explicit encoded source
extent. `LegacyWordImageAsset.metafile` exposes record counts, bounds, intended
EMU size, native-embedding eligibility, and the separate preview capability.

EMF validation checks the signature, header/description extents, file size,
record count, aligned record boundaries, handle capacity, and the final EOF
palette extent and size. WMF validation checks standard/placeable headers,
the placeable checksum, file size, object capacity, record word lengths,
maximum record size, and final EOF. These are structural checks, not a claim
that every class-specific record payload is understood.

Validated EMF/WMF image data can be emitted verbatim as `.emf` / `.wmf` image
parts in DOCX or DOCM, using the existing referenced inline/floating placement,
crop, hidden-content, and tracked-change paths. Actual native rendering remains
the responsibility of the consuming Office application. The original metafile
data is not rasterized or converted to an unrelated format.

WMF `META_ESCAPE` and EMF `EMR_DRAWESCAPE`, `EMR_EXTESCAPE`, or
`EMR_NAMEDESCAPE` disable native embedding. Their original records remain inert
evidence, with an explicit unsupported-image notice. PICT and unrecognized
BLIPs still follow the earlier opaque-preservation path. DIB support is limited
to the independently qualified monochrome textbox-pattern subset described in
[textbox paint](textbox-paint.md#embedded-picture-texture-and-monochrome-pattern-fills);
other DIB images remain opaque.

## Portable vector preview

`parseLegacyWordMetafile` exposes generated SVG for a deliberately bounded
subset of EMF and WMF. It supports solid/null pens and brushes, lines,
polygons, rectangles, rounded rectangles, ellipses, and EMF cubic Beziers,
including 16-bit point records. Elliptical arcs, chords and pie wedges retain
the projection of source radials onto the ellipse, separate fill and stroke,
and the EMF clockwise/counterclockwise direction. `EMR_ARCTO` alone connects
from and updates the current drawing point. Arc direction survives saved
device contexts. Identical arc/chord radials become a full ellipse using two
SVG arc segments; ordinary pie wedges close through the ellipse center.
Coincident pie radials, unequal collinear radials, center-point radials and
degenerate/reversed ellipse boxes remain unavailable previews because their
zero/full-sweep or outline behavior is not asserted by this subset. The exact
native metafile is still preserved. Independent binary tests and the native
arc probe described below cover these contracts.
It follows object handles, saved device
contexts, window/viewport transforms, and EMF affine world transforms.
Compound `EMR_POLYPOLYGON` / `EMR_POLYPOLYGON16`,
`EMR_POLYPOLYLINE` / `EMR_POLYPOLYLINE16`, and WMF `META_POLYPOLYGON`
use bounded count arrays and one compound SVG path. This preserves alternate
and winding fill across nested or overlapping figures. Separate figures do
not acquire connecting lines, and these records do not alter the current
drawing point. Declared EMF totals must equal their per-figure counts.
Compound records are capped at 16,384 figures and share the cumulative point
budget. The 32-bit EMF variants exceeding the documented largest 16K-point
device limit have no asserted complete preview. WMF selections use actual
object-table indices; the EMF high-bit stock-object convention is not applied
to WMF indices.
The result is a geometric preview, not a promise of pixel-identical GDI
rasterization or native font metrics.

Every record must belong to the supported subset, including state changes.
Unknown commands, clipping, text, palette colors, pattern brushes, non-copy
raster operations and unsupported mapping modes make the **entire SVG
unavailable**. The parser reports their record types; it never displays a
misleading partially drawn image. The independently validated original
metafile may still be eligible for native Office embedding.

The playback `bounds` use device coordinates and remain distinct from
`officeArtBounds`, the original producer-dependent presentation/clipping
rectangle. An OfficeArt physical-unit rectangle must not replace an EMF
header's device canvas. A standalone WMF can use explicit caller bounds or a
placeable header. Without either, a normalized canvas is accepted only when
an explicit initial anisotropic mapping mode and nonzero window extent precede
painting. Ambiguous viewport or saved-context setup prevents this inference;
window origins are replayed separately. These rules retain the raw OfficeArt
rectangle without guessing its units as SVG pixels.

SVG contains fixed generated tags, numeric coordinates and resolved RGB
colors. It never copies source markup, URLs, scripts, font files or external
resources. Preview limits add 100,000 cumulative points, 64 saved contexts,
8 MiB of generated text, and finite bounded transforms. Generated previews
also count toward the retained-media budget.

The compound-fill native probe checks both EMF coordinate widths and WMF
with independently authored nested rectangles. The native embedded metafile
and generated SVG must both leave the center white in alternate mode and
black in winding mode. Those interior-color assertions check actual drawing
semantics; they do not certify all edge pixels or absolute image placement.
The command requires installed LibreOffice, Poppler and PyMuPDF.

```
python3 tool/fidelity/metafile_render.py --office /path/to/soffice \
  --dart /path/to/dart --output build/metafile-render
```

`metafile_arcs_render.py` checks fifteen independently authored EMF/WMF arc,
chord, pie and ArcTo controls. Each metafile includes a distinct reference
rectangle: geometry is measured relative to that frame, not fitted to the
observed arc. Fixed interior and outline samples distinguish sweep direction,
the chord's secant from the pie's radial closure, and unfilled arcs from filled
regions. The two ArcTo cases additionally require the following line to begin
at the projected ellipse endpoint, rather than the original radial input.
All fifteen native and SVG controls pass on the recorded LibreOffice build;
the [complete receipt and retained artifacts](evidence/metafile-arcs-24580b0/README.md)
preserve the clean-checkpoint measurements.
The geometric tolerance is 2.1 source units on a 200 by 100 canvas, accounting
for native inclusive-edge/device quantization; these are not pixel goldens.
The probe retains exact input/output hashes, native PDF/text/raster evidence,
and checks all generated input bytes remain unchanged. Its portable adversarial
tests reject reversed sweeps, lost/invented fills, incorrect current points,
missing samples and geometry that uses the radial endpoint as the arc endpoint.
The VM/JavaScript acceptance path checks oblique radial projection, clockwise
ArcTo and WMF pie coordinates separately.

```
python3 tool/fidelity/metafile_arcs_render.py --office /path/to/soffice \
  --dart /path/to/dart --output build/metafile-arcs
```

## OfficeArt shape and text-box model

Referenced pictures and drawings now expose `shape`, a resolved typed subset
of their actual OfficeArt FSP/FOPT records. It includes the MSOSPT identifier,
signed fixed-point rotation and separate horizontal/vertical flips. FOPT
Boolean properties are merged per use bit, so a child value does not erase
unrelated inherited flags. Source complex properties remain bounds-checked
views of the exact retained OfficeArt artifact.

Supported geometry includes rectangle, rounded rectangle, ellipse and line
presets, plus explicit 32-bit and bounded packed signed 16-bit custom vertices
connected by straight segments, cubic Beziers, moves and closes. Nonempty segment records take precedence over
`shapePath`, as the binary specification requires. Vertex counts and segment
consumption are checked before constructing paths. The geometry subset does
not guess unsigned packed arc coordinates, unresolved guide formulas, adjusted
presets or geometric escape/client-escape segments. These remain retained evidence with
an unsupported-drawing diagnostic. The [packed vertex contract](packed-vertices.md)
records the exact array boundary, independent source implementations and native
full-width/packed DOC comparison.

The bounded zero-count `SymmetricCurve` editing hint is retained separately from
explicit rendered segments. Inactive solid-paint background colors and explicit
cell-layout flags no longer suppress otherwise supported shapes. Their strict
context checks, independent Boolean inheritance, native evidence and remaining
tangent-editor/pixel limitations are recorded in
[officeart-context.md](officeart-context.md).

The model also exposes direct RGB fill/line colors and opacity, line width,
dash/join/cap identifiers, and offset-shadow properties. Qualified textboxes
add scaled gradients, embedded picture/texture fills and bounded monochrome
patterns under the [textbox paint contract](textbox-paint.md). Palette/system
colors, other gradient/pattern forms, perspective/3-D settings and unmapped
appearance properties remain explicit `unsupportedProperties`, never
relabeled as a plain RGB style. Parsed data and native rendering support are
separate; the qualified textbox fill path does not enable arbitrary shape fills.

Ordinary image frames now have a separately verified DrawingML appearance
path for FSP flips, absolute floating quarter turns, direct solid outlines
and simple offset shadows. Its independent authored/native controls, exact
results and remaining vertical-flip raster difference are recorded in
[image-appearance.md](image-appearance.md). This does not relax the editable
shape gate below or claim arbitrary OfficeArt effects.

### Editable native shape output

Resolved rectangles, ellipses, lines, and custom move/line/cubic/close paths
can now become editable VML in the converted DOCX. Direct solid RGB paint,
fill/line opacity, line width, dash/join/cap styles, simple offset shadows,
rotation and flips are emitted from the source model. Source defaults are
explicit where VML differs: the default line is 0.75 pt with round joins and
flat caps. Negative geometry origins are retained independently of page
placement. Original OfficeArt remains available as evidence.

This path requires a completely resolved supported shape. Group/child/master
contexts, WordArt, unmapped shape/group properties, unknown effects, adjusted
presets, and rounded-rectangle presets without a resolved path are not
simplified into active drawings. The `editableShapes` counter measures native
shape emission, not raster equivalence or arbitrary OfficeArt coverage.

`tool/fidelity/shape_render.py` builds authored binary fixtures and examines
their converted DOCX's native PDF vectors. It checks rectangle corners, line
endpoints, cubic control points, fill color and line width against independent
source expectations. Matching outer bounds alone is insufficient: the probe
caught a host VML parsing difference that turned a rectangle into a trapezoid
when spaces followed command letters. The writer emits compact numeric paths.
The probe requires installed LibreOffice, Poppler and PyMuPDF; it does not
download a renderer or create expected coordinates from its own output.

Horizontal and vertical preset lines may have one zero FSPA extent. They use
native `v:line` endpoints in the parent coordinate space, with the source
flip flags, instead of scaling a shape through a zero-sized rectangle. Both
dimensions zero, reversed extents, out-of-bounds placement and zero-area
non-line shapes/images remain unrendered evidence. The native probe checks
all eight horizontal/vertical and none/x/y/xy flip combinations, including
ordered endpoints, so matching outer bounds cannot conceal lost direction.
This follows the documented [VML line element](https://learn.microsoft.com/en-us/windows/win32/vml/msdn-online-vml-line-element)
and [parent-space endpoint coordinates](https://learn.microsoft.com/en-us/windows/win32/vml/from-attribute--line--vml).

```
python3 tool/fidelity/shape_render.py --office /path/to/soffice \
  --dart /path/to/dart --output build/shape-render
```

`shape.text` records signed EMU insets, text anchor/wrap/flow/font-direction
enum values and explicitly used auto-margin/fit-shape-to-text flags. Absent
properties remain null, distinct from an explicit zero. MS-ODRAW marks the
adjacent text Boolean bit as unused, so it is not interpreted as shrink-to-fit.
Text-box text and chain ownership still come from the validated story and
shape references; geometry does not invent line breaks or CP reflow.

## Linked textbox native probe

`tool/fidelity/textbox_reflow.py` generates two versions of an authored
two-frame story. The second version changes only the first frame's height.
The independent PDF word-position check requires all eight unique markers
exactly once, in order, within both frames, and requires text to flow back
into the enlarged first frame. It runs the check on generated DOCX, its
native binary DOC bridge, and the parser's converted DOCX separately.
It does not infer correct flow from XML links or page count alone.

```
python3 tool/fidelity/textbox_reflow.py --office /path/to/soffice \
  --dart /path/to/dart --output build/textbox-reflow
```

The native DOC fixture exposed a contradictory declared chain count:
`FTXBXS.cTxbx=1` while OfficeArt indices and `hspNext` identify two frames.
Only this declared-one case can be recovered, with a complete, bounded,
unique, contiguous chain whose first shape and every next-shape link agree.
Other count disagreements, gaps, cycles, missing corroborating links and
conflicting ClientTextbox/lTxid identifiers remain errors. The original
count is retained as `declaredChainLength`; conversion evidence includes
both declared and resolved lengths. `recoveredTextboxChainLength` explicitly
marks this interoperability recovery.

A separate native representation reuses one singleton textbox story in
different header/footer variants. The [shared-header recovery](shared-header-textboxes.md)
requires distinct owning ranges, index zero on every instance, a matching
primary shape and no continuation links. Each output part receives its own
editable instance and inline field events; the source text is still parsed
once. `recoveredSharedHeaderTextbox` and placement evidence disclose the
recovery. The original recovery measurements retain their 0.35 pt placement
offset. The later [textbox frame-border correction](textbox-frame-borders.md)
closes that offset for the two retained alias cases on initial import and all
three repeat cycles; the earlier observations remain unchanged.

Actual positioning is checked independently: the first run also exposed a
page-origin discrepancy in the parser conversion. A successful chain recovery
does not by itself claim correct positions or an exact raster match.
The report separates resize reflow from absolute authored placement. For
the reflow metric only, it may subtract one disclosed common translation
anchored to the first marker in the authored DOCX; it cannot reposition
frames or variants independently. Absolute placement and the overall probe
still fail when that translation places markers outside the authored frames.

The initial LibreOfficeDev `26.8.0.0.alpha0` run at commit
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5` put two markers in the small first
frame and four in the enlarged frame for both direct DOCX and binary DOC.
The earlier parser preserved reflow but shifted the text 72 pt right/down.
That failure remains historical evidence. The
[Word-specific positioning contract](officeart-positioning.md) resolves explicit
FOPT origins using the independently corroborated zero-based Word mapping:
`posrelh=1` and `posrelv=1` are page-relative. Generic MS-ODRAW's one-based
table is not applied to these Word properties. Each axis retains its SPA
fallback when the explicit property is absent or unsupported.

The corrected positioning receipt measures zero marker drift without a fitted
translation. Its compact source initially retained a five-pixel raster
difference; the later [74420eb2 native corpus](evidence/native-corpus-74420eb2/README.md)
records exact initial compact and extended renders after the qualified paint
changes. Repeat-import differences and arbitrary anchor/layout combinations
remain separate from those bounded initial-render results.

Primary references:

- [MS-DOC OfficeArtClientTextbox](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/3ea806f3-8ff6-4ce4-8cb2-3ba732af4ec4)
- [MS-DOC FTXBXNonReusable](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/5aaa54b6-f38c-440a-82b1-8d61beb95b31)
- [Word VML textbox behavior](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/da04f6ea-a025-4e81-92c4-adfa5ab603fb)
- [MS-ODRAW horizontal relative position](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/e6d6737b-189d-4ce9-ada1-3fff4c4e7512)
- [MS-ODRAW vertical relative position](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/e8351af1-c736-4e34-8bf1-1a7497b6cd41)

## Bounds and verification

Each decoded metafile is limited to 16 MiB, 50,000 records and 4,096 declared
graphics objects. The existing aggregate 64 MiB retained-media budget also
applies before inflation. Zlib headers, completion, exact decoded size,
Adler-32, and trailing input are checked. Every output literal, block copy and
back-reference is bounded before writing. A generic decoder followed by a size
check would not provide that allocation guarantee.

The `archive` minimum is 4.6.0 because this path uses its strict raw inflater
completion/error contract. It directly supplies a bounded memory stream;
the high-level web zlib decoder's complete intermediate buffer is not used.
The same Dart implementation is used on the VM and JavaScript targets.

Authored binary tests cover both formats, compression modes and UID layouts,
native DOCX image bytes/content types, immutable assets, malformed headers,
forged lengths/counts, checksum/truncation/trailing input, output exhaustion,
and inert escape handling. Existing real-DOC PNG extraction and media
preservation tests remain part of the regression gate.
Vector fixtures additionally check geometry, fill/stroke selection, coordinate
signs, handle deletion/reuse, all four world-transform operations, state-stack
limits, invalid point counts, and the all-or-unavailable fallback policy.
OfficeArt fixtures check inherited use-bit overrides, all text insets,
signed transforms, explicit fill/line/shadow colors, custom-path precedence,
immutable coordinates, unsupported guides/encodings, duplicate properties,
malformed complex extents and out-of-range path references. Per-shape arrays
are capped at 16,384 elements, with 100,000 aggregate geometry points.

## Primary format references

- [MS-ODRAW OfficeArtBlip](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/c67b883b-8136-4e91-a1a3-2981d16e934f)
- [MS-ODRAW OfficeArtMetafileHeader](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/ffdcc2b8-98fd-46b2-921e-6bb6693d05e5)
- [MS-ODRAW OfficeArtBlipWMF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/ee892f04-f001-4531-a34b-67aab3426dcb)
- [MS-EMF header records](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/de081cd7-351f-4cc2-830b-d03fb55e89ab)
- [MS-EMF EOF](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/3f47fde0-0e6b-40c1-87f3-f4129af03aa1)
- [MS-WMF header](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/d169108a-e3fe-436a-bb44-bea61a46ce56)
- [MS-EMF world transforms](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/c70b85e5-8c31-418f-a7b8-349e417e0f76)
- [MS-EMF transform matrix](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/e84107e9-bc2b-4a14-9234-5d173adc1b59)
- [MS-EMF PolyBezier](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/4e53793a-95af-49d4-ae1f-4c407eda9440)
- [MS-WMF drawing records](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/cb1d4bfe-bfeb-4348-9e51-ba7f06096808)
- [MS-ODRAW shapePath precedence](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/34decfc7-1f3e-4c74-8078-79bb0cb75fdd)
- [MS-ODRAW path commands](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/54c00b9c-2225-4ed4-93e4-691e4aafeec8)
- [MS-ODRAW complex arrays](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/f68b7770-f7fb-4b1a-bafa-d46054ee0435)
- [MS-ODRAW text Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/ab9e4283-a47f-429c-8c2b-683a3a7f16d1)
- [MS-ODRAW text anchors](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/fabbbc36-61b4-45da-9cb6-5aa695f411c9)
- [MS-ODRAW fill Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/baf2613d-c676-43c8-8077-828bdcc70dca)
- [MS-ODRAW line Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/b359a9d1-941b-49ad-8462-7c0bb894d125)
- [MS-ODRAW shadow Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/802363c2-7656-486d-84d3-9eab26fb36cc)
- [VML path syntax](https://learn.microsoft.com/en-us/windows/win32/vml/msdn-online-vml-path-attribute)
- [MS-ODRAW line-width default](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/fb88b56e-2c2d-41c2-a0c8-98129e913b89)
- [MS-ODRAW line-join default](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/bd76cb1d-aac3-4913-a053-f3bf4a9ee52b)
- [MS-ODRAW line-cap default](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/7bc33ac1-15bf-4bbc-8348-34371449faf1)
- [MS-ODRAW horizontal shadow offset](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/364ecedd-9a50-4f78-bc9c-20718d2e621b)
- [MS-EMF PolyPolygon](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/c60ff127-2711-42d3-85d4-502ca2e4caef)
- [MS-EMF PolyPolyline](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/e23f75fd-3af6-49f3-8c86-ef121ff61701)
- [MS-WMF PolyPolygon object](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/cf1ac7c0-749d-4678-b32c-6f68d2a5f268)
- [GDI polygon fill modes](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-setpolyfillmode)
- [MS-WMF object selection](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/59b4b6f3-40db-4685-8eda-3be3e4196fb2)
- [MS-EMF Arc](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/3e148f19-7e75-43aa-9259-fda562f60315)
- [MS-EMF Chord](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/b442d2fb-f92b-4103-aa7d-44f864f719d5)
- [MS-EMF Pie](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/c326f6b2-ae7e-447f-b8dc-02c703f054c3)
- [MS-EMF arc direction](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/83a955e6-13b8-4720-a521-542e3dd91cba)
- [GDI ArcTo current-position behavior](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-arcto)
- [MS-WMF Arc parameter order](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/742097b4-5879-4c36-b57e-77e7cc152253)
- [MS-WMF Pie parameter order](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/b3f3e55f-6f69-4678-87ea-e6feb6af6eeb)
