# Inline picture scale quantization

The retained `emf-vectors` case has a concrete frame-size discrepancy independent
of metafile preview coverage. Its binary PICMID stores an initial size of
9001 × 5401 twips and horizontal/vertical scales of 960 tenths of a percent.
Nearest-integer rounding gives 8641 × 5185 twips. The installed native importer
uses integer division and produces 8640 × 5184 twips, matching the authored
432 × 259.2 pt frame. The WMF control starts at 9000 × 5400 twips, so its same
scale is integral and does not expose the difference.

Both cases already have complete portable vector previews. EMF bytes are
identical in the authored source, native DOCX and parser DOCX; the native WMF
bridge removes its placeable header, but the subsequent native and parser
metafile payloads are identical. This discrepancy is in picture framing,
not a missing vector record.

## Independent control

`tool/fidelity/picture_sizing_render.py` patches only the eight PICMID
goal/scale bytes in a hash-pinned native PNG source. Its independent CFB reader
records every physical byte changed. Seven authored controls distinguish
integral, below-half, exact-half, above-half, one-thousandth and both retained
metafile ratios. The expected dimensions are explicit constants, independent
of both the Dart parser and the native output. Each control records raw
header bytes, native and parser XML extents, source hashes, preserved image
hashes and independently rendered PDF image bounds.

On LibreOfficeDev `26.8.0.0.alpha0`, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, all seven native frame sizes match
integer division. The baseline parser's nearest rounding disagrees on four
controls. Microsoft specifies the PICMID scale ratio and bounds but does not
define a rounding algorithm; the integer-twip behavior is therefore a bounded
interoperability contract, supported by these measurements and the pinned
native importer's integer arithmetic. It is not a Microsoft Word rendering
claim.

The parser now truncates positive fractional twips at this boundary. It checks
the exact scaled numerator against 15–31680 twips before division, so neither
nearest rounding nor truncation can admit a dimension outside the documented
range. Raster and metafile pictures share this rule. Explicit OfficeArt crop
fractions remain separate and do not scale the final PICMID frame a second
time. The [baseline receipt](evidence/picture-scaling-20261113/baseline-report.json)
retains all four pre-fix disagreements.

## Crop remains source-controlled

The native importer also insets the PNG image by 0.05 pt on each side in the
unmodified integral control, and its DOCX export adds tiny negative crop
percentages. That separate difference is retained in the measurements. The
binary PICMID reserved fields and OfficeArt crop values are zero. The parser
must not invent source cropping to imitate this export adjustment. Exact frame
dimensions and exact image pixels remain separate measurements.

Run the bounded control with an installed renderer and direct Dart executable:

```sh
python3 tool/fidelity/picture_sizing_render.py \
  --dart /path/to/dart --office /path/to/soffice --output NEW_DIRECTORY
```

Primary references:

- [MS-DOC PICMID scale ratio and bounds](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/388c0671-fd3b-4597-813a-1c67fea7dc46)
- [MS-DOC PICFAndOfficeArtData](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/dedb7505-8cc4-4053-aa2d-431b18d4bd97)
- [Pinned native PICMID arithmetic](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/ww8graf2.cxx)
