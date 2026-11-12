# Packed OfficeArt vertices

The parser resolves the `pVertices` `IMsoArray` form whose `cbElem` is `0xFFF0`
as two signed 16-bit coordinates per point. The resulting points use the same
validated straight-line, cubic, move and close rules as full-width coordinates.
They can become editable native paths only after the existing complete-shape
checks pass. Original OfficeArt bytes remain unchanged and available as evidence.

## Interpretation and bounds

[MS-ODRAW IMsoArray](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/f68b7770-f7fb-4b1a-bafa-d46054ee0435)
defines the four stored bytes and array allocation rules. Its generic truncation
description does not, by itself, explain the packed POINT interpretation. Two
independent implementations provide more specific evidence:

- [Apache POI 5.4.1 HSSFPolygon](https://github.com/apache/poi/blob/REL_5_4_1/poi/src/main/java/org/apache/poi/hssf/usermodel/HSSFPolygon.java)
  writes `0xFFF0` vertices as a signed short at offsets zero and two and reads
  them using the same two signed coordinates.
- [The pinned LibreOffice reader](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/filter/source/msfilter/msdffimp.cxx)
  uses two signed 16-bit coordinates for non-arc packed vertices. Its arc
  exception uses unsigned coordinates. That exception is outside this increment:
  packed arc type 19 remains unsupported rather than acquiring signed geometry.

The native DOC comparison below independently verifies the signed interpretation,
including negative coordinates. This does not apply the POINT convention to
other truncated `IMsoArray` element types. A bare size of four remains unknown;
only the documented `0xFFF0` marker enables packed points. Counts, allocations,
exact byte extents, the 16,384-point limit, cumulative geometry budgets and exact
segment consumption remain mandatory. Partial coordinates and unused points
are rejected. Unresolved guides and unsupported escape segments remain inert.

The separate bounded recovery for a `pVertices.op` length excluding its six-byte
array header still requires an exact element-count/width match. It reports
`recoveredVertexArrayLength` with the original FOPT location; standard complete
lengths do not receive that recovery notice.

## Independent native check

`tool/fidelity/packed_shape_probe.dart` authors equivalent full-width, packed,
and packed/header-excluded DOCs, both unreflected and reflected in both axes.
The path has negative geometry origins, a straight edge, an asymmetric cubic,
and a closing edge. Its source coordinates are defined before conversion.

`tool/fidelity/packed_shape_render.py` checks three distinct facts:

1. Every packed DOC's native PDF paths are identical to its full-width DOC
   control, including all endpoints, cubic control points, paint and reflection.
2. Each converted DOCX matches the independently authored page coordinates,
   color and two-point stroke. Source placement is measured separately.
3. Source DOC and converted DOCX hashes remain unchanged during rendering.

The retained [native receipt](evidence/packed-vertices-native.json) contains six
passing cases with LibreOffice revision
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5` and PyMuPDF 1.26.6. Converted controls
have zero measured coordinate drift. Native binary playback differs from ideal
frame coordinates by at most 0.0508 points, consistent with one-twip edge rounding;
the full-width and packed source paths still match each other exactly. The
receipt explicitly records that the implementation worktree was dirty.

The fixtures place Word position properties in tertiary FOPT as recommended by
[MS-ODRAW OfficeArtTertiaryFOPT](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/a687e90c-1748-4f57-8758-be31cfb36185).
An earlier draft put those properties in ordinary FOPT; native DOC playback
ignored their page origins. Correcting the authored record placement fixed that
probe without changing production anchor semantics.

```sh
python3 tool/fidelity/packed_shape_render.py --office /path/to/soffice \
  --dart /path/to/dart --output build/packed-shapes
```

The unit suite also checks signed extrema, both standard and recovered property
lengths, open/closed paths, cubic ordering, strict array boundaries, malformed
segment references, source immutability and the unsupported arc exception.
This is evidence for the stated path subset, not arbitrary OfficeArt effects,
curve tessellation equality across applications, or universal pagination.
