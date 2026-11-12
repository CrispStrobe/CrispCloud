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
`bounds` describes the device-coordinate playback canvas; `officeArtBounds`
retains the original OfficeArt rectangle separately. The latter is not assumed
to use pixels: native producers also store preferred physical-unit extents.

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
evidence, with an explicit unsupported-image notice. PICT, DIB and unrecognized
BLIPs still follow the earlier opaque-preservation path.

## Portable vector preview

`parseLegacyWordMetafile` exposes generated SVG for a deliberately bounded
subset of EMF and WMF. It supports solid/null pens and brushes, lines,
polygons, rectangles, rounded rectangles, ellipses, and EMF cubic Beziers,
including 16-bit point records. It follows object handles, saved device
contexts, window/viewport transforms, and EMF affine world transforms.
The result is a geometric preview, not a promise of pixel-identical GDI
rasterization or native font metrics.

Every record must belong to the supported subset, including state changes.
Unknown commands, clipping, text, palette colors, pattern brushes, non-copy
raster operations and unsupported mapping modes make the **entire SVG
unavailable**. The parser reports their record types; it never displays a
misleading partially drawn image. The independently validated original
metafile may still be eligible for native Office embedding. A standalone
WMF needs caller-supplied device bounds, placeable-header bounds, or explicit
initial anisotropic window setup for a portable preview. A nonplaceable WMF
whose initial playback context is ambiguous remains eligible for native
embedding but receives no fabricated SVG canvas. EMF uses its self-contained
header coordinate system. OfficeArt clipping/presentation metadata remains
separate and is not substituted for intrinsic metafile coordinates.

SVG contains fixed generated tags, numeric coordinates and resolved RGB
colors. It never copies source markup, URLs, scripts, font files or external
resources. Preview limits add 100,000 cumulative points, 64 saved contexts,
8 MiB of generated text, and finite bounded transforms. Generated previews
also count toward the retained-media budget.

## OfficeArt shape and text-box model

Referenced pictures and drawings now expose `shape`, a resolved typed subset
of their actual OfficeArt FSP/FOPT records. It includes the MSOSPT identifier,
signed fixed-point rotation and separate horizontal/vertical flips. FOPT
Boolean properties are merged per use bit, so a child value does not erase
unrelated inherited flags. Source complex properties remain bounds-checked
views of the exact retained OfficeArt artifact.

Supported geometry includes rectangle, rounded rectangle, ellipse and line
presets, plus explicit 32-bit or packed 16-bit custom vertices connected by
straight segments, cubic Beziers, moves and closes. Nonempty segment records
take precedence over `shapePath`, as the binary specification requires. Vertex
counts and segment consumption are checked before constructing paths. The
packed `0xfff0` array layout and LibreOffice's vertex-length convention
(excluding the six-byte array header) are recognized only when the declared
count, element width and enclosing FOPT extent agree. Arc coordinates use the
native unsigned packed representation. Other shapes use signed coordinates.
`NoFill` and `NoLine` path escapes are retained. Editing-preference escapes do
not change resolved coordinates and remain disclosed as unsupported editing
metadata. Unresolved guides, adjusted presets, arc/quadratic escape commands
and client escapes remain opaque evidence rather than guessed geometry.

The model also exposes direct RGB fill/line colors and opacity, line width,
dash/join/cap identifiers, and offset-shadow properties. Palette/system colors,
gradients, pattern fills, perspective/3-D settings and unmapped appearance
properties remain explicit `unsupportedProperties`, never relabeled as a
plain RGB style. Parsed data and native rendering support are separate.

`shape.text` records signed EMU insets, text anchor/wrap/flow/font-direction
enum values and explicitly used auto-margin/fit-shape-to-text flags. Absent
properties remain null, distinct from an explicit zero. MS-ODRAW marks the
adjacent text Boolean bit as unused, so it is not interpreted as shrink-to-fit.
Text-box text and chain ownership still come from the validated story and
shape references; geometry does not invent line breaks or CP reflow.

## Native editable shape output

Referenced supported presets and custom line/cubic paths are written as
editable native VML in the Word package. Coordinate origin/size, rotation,
horizontal/vertical flips, direct solid fill and line colors, opacity,
stroke width/dash/join/cap, and simple offset shadows are carried forward.
Referenced pictures retain their image bytes and receive equivalent
DrawingML transforms, line properties and simple shadows. Unsupported effects
stay in the original OfficeArt evidence and keep the partial-formatting
limitation. No raster approximation is silently substituted for a shape.

`shape.position` retains explicit OfficeArt alignment and relative-position
properties separately from the original FSPA fields. Native Word DOC
interoperability uses the zero-based relative mapping implemented by
LibreOffice's `ProcessEscherAlign`: margin, page, text, character/line. The
explicit properties take precedence; FSPA is used when they are absent. This
is an intentional compatibility choice: the published MS-ODRAW `posrelh` and
`posrelv` tables number these values from one, while the independently
authored DOCX → installed LibreOffice DOC → native DOCX fixture uses value one
for page-relative positioning. Raw values are preserved so this discrepancy
is inspectable. This evidence does not establish Microsoft Word pixel parity.

Hidden and tracked inserted/deleted shape state follows the existing media
presentation model. FSP records marked deleted are never activated. Unknown
shape presets, unresolved paths and shapes without a validated anchor remain
inert evidence. Wrap contours, gradient/pattern fills, arbitrary guide
programs, grouped transforms, perspective and 3-D effects are still partial.

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
are capped at 16,384 elements, with 100,000 aggregate geometry points and
commands, including repeated inherited properties. Native-output tests check
editable presets/custom paths, picture-byte preservation, transform/effect
attributes, explicit positioning precedence and hidden/deleted content.

The independently authored three-shape DOCX control is bridged through
installed LibreOffice into actual binary DOC. The parser recovers its three
anchored shapes: rotated rectangle, ellipse and packed custom cubic path.
This complements the synthetic binary tests; it does not make the originating
DOCX, native DOC bridge and package output interchangeable fidelity oracles.

Two additional independent controls live in
`test/fixtures/fidelity/media/{emf,wmf}-vectors.docx`, with their raw metafiles
alongside them. `tool/fidelity/metafile_cases.dart` authors GDI records and
minimal OPC XML directly, without invoking this parser or converter. Both
controls were accepted by installed LibreOffice, exported as binary DOC,
parsed by this package and converted back to DOCX with native vector image
parts. The EMF retained its 540 bytes through the native bridge. LibreOffice
removed the WMF's 22-byte placeable header; this package retained the resulting
208-byte native DOC payload. Both recovered images produced complete portable
SVG previews. Native source changes and converter changes remain separate.
The native metafiles and generated SVGs were also embedded into otherwise
identical control packages and rendered in RGB by the installed application.
The expected shape geometry and colors were checked side by side. Their
rasters are not identical; this remains a bounded geometric preview rather
than pixel-exact GDI emulation. Native DOCX payloads remain byte-identical to
the extracted metafiles.

`tool/media_web_acceptance.dart` runs unchanged on the VM and after
`dart compile js -O1 -o build/media-web-acceptance.js
tool/media_web_acceptance.dart`. Running the result under Node (with
`globalThis.self=globalThis`) passes 40 assertions covering both authored
formats, exact native image output, strict compressed-input/output failures,
inert escapes, physical-versus-device bounds, missing WMF context, packed
geometry, signed values and explicit positioning. This
checks the actual raw inflater and parser on JavaScript, not a separate web
implementation.

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
- [MS-EMF header coordinate and physical units](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/e4a35c41-e8e3-43f9-bc07-a18e99bb866d)
- [MS-WMF device-independent window setup](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/b67679cd-b777-492a-b3bd-903dde5de6fa)
- [MS-WMF player/viewport responsibilities](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/2678f2fe-df2e-489d-83db-713a9f6397de)
- [MS-ODRAW shapePath precedence](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/34decfc7-1f3e-4c74-8078-79bb0cb75fdd)
- [MS-ODRAW path commands](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/54c00b9c-2225-4ed4-93e4-691e4aafeec8)
- [MS-ODRAW complex arrays](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/f68b7770-f7fb-4b1a-bafa-d46054ee0435)
- [MS-ODRAW path escapes](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/37269b23-7e5f-4812-ba8d-f08f745bf505)
- [MS-ODRAW horizontal relative positioning](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/e6d6737b-189d-4ce9-ada1-3fff4c4e7512)
- [MS-ODRAW vertical relative positioning](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/e8351af1-c736-4e34-8bf1-1a7497b6cd41)
- [LibreOffice native Word position mapping](https://github.com/LibreOffice/core/blob/master/sw/source/filter/ww8/ww8graf.cxx)
- [LibreOffice packed OfficeArt coordinates](https://github.com/LibreOffice/core/blob/master/filter/source/msfilter/msdffimp.cxx)
- [LibreOffice OfficeArt array-length producer](https://github.com/LibreOffice/core/blob/master/filter/source/msfilter/escherex.cxx)
- [MS-ODRAW text Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/ab9e4283-a47f-429c-8c2b-683a3a7f16d1)
- [MS-ODRAW text anchors](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/fabbbc36-61b4-45da-9cb6-5aa695f411c9)
- [MS-ODRAW fill Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/baf2613d-c676-43c8-8077-828bdcc70dca)
- [MS-ODRAW line Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/b359a9d1-941b-49ad-8462-7c0bb894d125)
- [MS-ODRAW shadow Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/802363c2-7656-486d-84d3-9eab26fb36cc)
