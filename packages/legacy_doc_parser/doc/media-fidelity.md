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
evidence, with an explicit unsupported-image notice. PICT, DIB and unrecognized
BLIPs still follow the earlier opaque-preservation path.

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

## Primary format references

- [MS-ODRAW OfficeArtBlip](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/c67b883b-8136-4e91-a1a3-2981d16e934f)
- [MS-ODRAW OfficeArtMetafileHeader](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/ffdcc2b8-98fd-46b2-921e-6bb6693d05e5)
- [MS-ODRAW OfficeArtBlipWMF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/ee892f04-f001-4531-a34b-67aab3426dcb)
- [MS-EMF header records](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/de081cd7-351f-4cc2-830b-d03fb55e89ab)
- [MS-EMF EOF](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/3f47fde0-0e6b-40c1-87f3-f4129af03aa1)
- [MS-WMF header](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wmf/d169108a-e3fe-436a-bb44-bea61a46ce56)
