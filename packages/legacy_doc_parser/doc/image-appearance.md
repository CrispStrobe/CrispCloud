# Bounded native image appearance

The DOCX image writer now carries resolved picture-frame flips, a restricted
floating quarter-turn mapping, direct solid outlines and simple offset
shadows. These are separate from the stricter editable OfficeArt path writer:
that writer's geometry and unsupported-property gates remain unchanged.

## Supported mapping

| Source property | Output and boundary |
| --- | --- |
| FSP horizontal/vertical flips | Independent `a:xfrm` flags for ordinary picture frames. Group/child/master, ink, discussion-anchor and unresolved transform contexts remain unsupported. |
| Floating absolute 90°, 180° and 270° rotations | Restore pre-rotation extents from the FSPA rectangle while retaining its center, then write the DrawingML rotation. Negative quarter turns normalize to the corresponding positive DrawingML angle. |
| Direct solid line | Native line color, alpha, width, preset dash, cap and join. Source defaults are explicit: 0.75pt width, flat cap and round join. An explicit disabled line becomes `a:noFill`. |
| Enabled type-0 offset shadow | Direct RGB/alpha, zero blur, signed offsets converted to distance/direction, and `rotWithShape="0"`. Obscured, patterned, perspective, multiple or unresolved shadows are not simplified into this effect. |

The raw OfficeArt source and FSPA coordinates remain unchanged in the model
and evidence. Unknown appearance properties continue to report partial
formatting. Newly identified low-numbered transform properties and complex
rotation operands are explicitly unsupported, so they cannot silently be
replaced by the FSP transform. Image bytes, crop values and relationships
continue through the existing bounded media path.

The quarter-turn mapping applies only to ungrouped picture frames with
absolute positions on both axes and supported origins. Inline rotations,
arbitrary angles, aligned-anchor rotation, unknown origin/override semantics
and other shape contexts remain explicit limitations. An omitted rotation
also produces an `unrenderedImageRotation` evidence record. Adjusted position
offsets must fit DrawingML's signed offset range. No page-margin constant is
added or subtracted; the receiving layout engine resolves the preserved
origin.

## Why the rectangle adjustment matters

The recovered parallel implementation wrote an image's rotation directly
onto its FSPA-sized rectangle. That is insufficient for a quarter turn:
the independently authored 72×36pt control becomes a 36×72pt FSPA box after
native DOC export. Applying another quarter turn to those extents changes
the aspect and location again.

The bounded mapping interchanges those axes around the same center before
emission. This is also the pre-rotation rectangle adjustment performed by
the pinned LibreOffice OfficeArt importer before constructing an object.
The native controls verify page-relative positions and negative offsets
relative to page margins independently of the parser's writer.

## Independent native evidence

`tool/fidelity/image_appearance_cases.py` authors minimal OOXML controls
directly with Python's ZIP/XML primitives and a generated four-color PNG.
It does not call the Dart parser or converter. The source OOXML, native DOC
export and converted DOCX are each rendered independently by LibreOfficeDev
`26.8.0.0.alpha0`, revision
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.

The exact authored and native input files are retained under
`test/fixtures/fidelity/image-appearance/`, with hashes in its manifest.
`doc/evidence/image-appearance-native.json` records the raw source models,
file/PDF/RGB hashes, bounds, color centroids, native paths and three separate
comparisons. The measured outputs are not used as their own reference.

| Control | Converted DOCX versus authored OOXML at 144 DPI |
| --- | --- |
| Inline horizontal flip | RGB exact |
| Floating untransformed control | RGB exact |
| Floating horizontal flip | RGB exact |
| Floating both-axis flip, represented as 180° in DOC | RGB exact |
| Floating clockwise quarter turn | RGB exact |
| Floating counterclockwise quarter turn | RGB exact |
| Floating quarter turn with negative margin-relative offsets | RGB exact |
| Direct dashed magenta outline and half-opacity offset shadow | RGB exact |
| Floating vertical flip | Bounds and orientation retained; RGB differs at 8,664 pixels |

All nine controls have zero measured quadrant-bound drift. The vertical
case's maximum normalized color-centroid drift is approximately 0.0232;
its native DOC representation contains a rewritten horizontally mirrored
image plus 180° rotation. The converted representation retains the intended
orientation but is not raster-exact. Its pixel difference remains in the
receipt rather than being classified as exact fidelity.

The native DOC rendering already loses stored rotation for several of these
controls and changes the outline/shadow representation. The probe therefore
records authored→DOC, authored→converted and DOC→converted results
separately. Eight exact authored comparisons do not assert that the original
DOC renderer was correct, that repeated DOC export preserves these effects,
or that other Office renderers produce identical pages.

### Vertical-flip export diagnosis

[The retained diagnosis](evidence/image-vertical-flip-diagnosis.json) records
input, output, image and raster hashes for the remaining vertical-flip
difference. The native DOC stores an exact horizontal reflection of the
authored 80×40 PNG plus a 180° rotation. All 3,200 source pixels match that
reflection, and the converter preserves the native PNG bytes. Authored and
converted DOCX anchors, extents and precise PDF image rectangles are equal.

The default native PDF export embeds the authored vertical flip as a
four-color PNG without a mask, while the converted half turn becomes a
135-color JPEG with a soft mask. A separately recorded export using
`UseLosslessCompression=true` produces identical decoded image pixels and
full-page RGB rasters. The original default-filter comparison still has
8,664 changed pixels and remains byte-exact in its original receipt.

A disposable-copy experiment also replaced the half turn with both flip
flags: `R(180°) = H × V` about the same center. It changed no other XML
semantics or archive-member bytes. Both the vertical-flip case and the
independent both-flip control rendered exactly as before, including the
same JPEG image hashes. This equivalent representation therefore offers
no improvement. The evidence supports retaining the current transform;
the default export encoding difference does not justify a converter
change or a change to the fidelity gate.

## Reproduction and remaining scope

Run `tool/fidelity/image_appearance_render.py` with an installed Dart SDK,
an installed LibreOffice executable and a new output directory. It authors
controls, performs native DOC export, invokes
`tool/fidelity/image_appearance_probe.dart`, renders all three stages and
checks the declared bounds/orientation/paint tolerances. The Dart producer
also accepts just an output directory to convert the retained binary inputs
for independent schema validation without requiring Office.

The focused tests cover all four FSP flip combinations, positive/negative
quarter turns, both margin/page origins, source defaults, disabled effects,
unsupported neighboring values and signed-offset overflow. The JavaScript
acceptance covers signed rotation, center-preserving extents and offset
shadow math through dart2js/Node.

Arbitrary angles and geometry, grouped transforms, palette/system paints,
recoloring, blur/multiple/perspective shadows, transparent-image effect
interaction, effect extents and exact text wrapping remain outside this
verified subset. HTML preview image appearance is still an approximation.

## Primary references

- [MS-ODRAW OfficeArtFSP flip and context flags](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/8a7e7be3-0582-4461-9400-29d7eda8497d)
- [MS-DOC Spa anchor rectangle](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/26fcafc0-554b-46bc-aebf-c755276c77a4)
- [MS-ODRAW transform Boolean properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/e45989e9-fb81-4424-9ff4-8c3167f5fb21)
- [MS-ODRAW shape flip overrides](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/aff4b132-455c-40bf-9639-e48a13e1cd5c)
- [MS-ODRAW line defaults](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/fb88b56e-2c2d-41c2-a0c8-98129e913b89)
- [MS-ODRAW line-dash values](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/6ca23258-0518-4ded-8976-dc94fefb3795)
- [MS-ODRAW shadow enabled flags](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/802363c2-7656-486d-84d3-9eab26fb36cc)
- [Pinned native OfficeArt pre-rotation rectangle implementation](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/filter/source/msfilter/msdffimp.cxx)
- [LibreOffice PDF export compression parameters](https://help.libreoffice.org/latest/en-US/text/shared/guide/pdf_params.html)
