# Referenced media and opaque preservation

`LegacyWordDocument.media` follows Word's recorded references. It does not scan
unallocated bytes or unrelated streams for image signatures. Its byte buffers
and collections are defensive, immutable snapshots. The parser and converter
do not execute objects, evaluate fields, run VBA, or fetch linked resources.

## Supported paths and limits of interpretation

| Source feature | Parsed or reusable representation | Preservation boundary |
| --- | --- | --- |
| Inline picture | U+0001 with resolved `CFSpec` and `CPicLocation` → `Data` PICF → inline OfficeArt shape and BLIP. Global CP, intended dimensions and crop are retained. | One unambiguous picture BLIP is mapped. Multiple inline BLIPs remain in the original PICF artifact, with a notice. |
| PNG, JPEG, TIFF | Referenced raster payload bytes, format, content type and precise source extent. | Header identification is not full image-decoder validation. No decompression or pixel allocation occurs here. |
| EMF, WMF | Bounded decoded file data and structural metadata, plus the original BLIP evidence. | Native image parts are permitted for structurally validated, escape-free files; see [metafile fidelity](media-fidelity.md) for the exact boundary. |
| DIB, PICT, unknown BLIP | Whole referenced OfficeArt BLIP record. | Opaque evidence; no execution, rasterization or guessed file extraction. |
| Floating image or drawing | `PlcfSpaMom` / `PlcfSpaHdr` → matching OfficeArt shape → referenced BStore entry. Anchor CP, rectangle, origins, wrapping, crop and shape identity are retained. | Both the original anchor table and OfficeArt graph remain evidence. Arbitrary geometry, rotation, flips, effects and tight-wrap polygons are not fully reconstructed. |
| Delayed BLIP | Reads the declared size at the FBSE `foDelay` location in `WordDocument`. | No fallback search when the reference is invalid; unreferenced BStore images are not materialized. |
| Textbox links | Full `OfficeArtClientTextbox` identifier and `hspNext` shape identity; the story parser validates linked text-story and chain indices. | Retaining chain identifiers does not establish identical text reflow or pagination. |
| Hidden or revised media | Each occurrence carries resolved hidden, insertion, deletion, author and time metadata independently of shared image bytes. | Private field results and field instructions stay hidden. OfficeArt's deleted-shape bit is separate from tracked deletion; deleted shapes stay inert. |
| Picture filename / path | Saved PICF name retained as descriptive metadata. | A name never triggers a file or network read. An independently stored image can still be used. |
| Referenced embedded OLE | Field separator + `CFOle2` + `CPicLocation` → named `ObjectPool` storage. Exact streams and directory metadata are retained in a reconstructed CFB container. | Active embedding requires a non-zombie, non-private field and a structurally recognized embedded `\x01Ole` record. Class-specific object contents and previews are not interpreted. |
| Linked or uncertain OLE | Original storage retained. | Inert evidence; no external relationship, link resolution or execution. ProgIDs are not guessed from reserved `CompObj` fields. |
| Unreferenced ObjectPool storage | Explicitly labeled opaque storage evidence. | Not promoted into an active object reference. Stale zombie-field locations do not establish an object reference. |
| VBA project storage | Known top-level `Macros`, `_VBA_PROJECT_CUR` and `VBA` storages retained with their hierarchy. | `hasRequiredStreams` checks only `PROJECT`, `VBA/dir` and `VBA/_VBA_PROJECT` presence. It does not validate, compile or run VBA. Only an explicitly requested DOCM can carry a single structurally complete project as active package content. |
| Whole-document signatures | Named `_signatures` stream and `_xmlsignatures` storage retained separately. | Evidence only. Original signature validity is neither verified nor transferred to a converted document. |
| VBA signatures | Named `StwUser` values `Sign`, `SigAgile`, `SigV3`, including the original count prefix. | Opaque signature evidence with its original stream extent. No signature decoding, verification or active signature relationship is produced. |
| Other field binary data | Referenced `NilPICFAndBinData` extent retained. | Opaque bytes; no field-type evaluation. |

The formatted HTML preview displays bounded referenced PNG/JPEG assets and
complete generated EMF/WMF previews through fixed data-image markup. Floating
images are labeled as anchor approximations; cropped, unsupported, or oversized
assets receive placeholders. Image budgets are shared across stories without
consuming space reserved for text. See the [HTML contract](html-preview.md).
The separate DOCX/DOCM writer retains native placement and immutable assets;
arbitrary original markup and external picture paths never enter HTML.

## Exact bytes versus reconstructed containers

Raster file data and opaque record artifacts retain their original bytes.
Extracted OLE/VBA/signature storages are **new CFB containers**: their child
stream contents, relative paths, CLSIDs, state bits and raw eight-byte FILETIME
values are preserved, but allocation tables, sector placement and directory
layout change. The original input document remains unchanged.

Source references identify the original compound stream, byte offset, length,
structure and optional global UTF-16 CP. A reconstructed storage reference uses
an explicit reconstructed-storage structure label; it does not claim that its
new container bytes occupy an original source extent.

## Resource bounds

The shared CFB reader accepts at most 64 MiB of input, 32 MiB per stream and
64 MiB of cumulative stream reads. The media layer additionally bounds retained
payload copies to 64 MiB, all catalog/storage/notice items to 4,096, OfficeArt
records to 50,000, nested records and storages to 32 levels, and examined text
positions to 8 Mi UTF-16 code units. Retained-byte accounting includes duplicate
representations such as an original OfficeArt record plus its reusable raster
payload and a storage's streams plus its reconstructed CFB.

Malformed extents, cyclic/shared CFB ownership, ambiguous active references and
exceeded resource limits fail with `FormatException`; no partial artifact is
returned as a successful complete parse. Recognized but unsupported media
formats remain explicit opaque artifacts and notices within these bounds.

## Format references and validation

The implementation follows Microsoft's
[picture references](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/85d6d318-0afc-4e6f-83f9-54d8444e3c35),
[PICFAndOfficeArtData](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/dedb7505-8cc4-4053-aa2d-431b18d4bd97),
[Spa](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/26fcafc0-554b-46bc-aebf-c755276c77a4),
[OfficeArtFBSE](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/2f2d7f5e-d5c4-4cb7-b230-59b3fe8f10d6),
[OfficeArtFSP](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/8a7e7be3-0582-4461-9400-29d7eda8497d),
[OfficeArtClientTextbox](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/3ea806f3-8ff6-4ce4-8cb2-3ba732af4ec4),
[OLEStream](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-oleds/e0dc105e-77f1-4072-a938-9aa516dc43e9)
and [StwUser](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/41981ee7-6f8d-4004-93de-0e897046a000)
structures. No JSDoc image-carving routine is incorporated in this module.

Independent fixtures exercise inline, floating and delayed images, source
visibility/revision state, OLE field eligibility, exact storage metadata,
signature scopes, dangling references, depth/extent limits and immutable output.
The authored `test/fixtures/word_native/formatting.doc` also verifies extraction
of its real referenced PNG. These checks establish the documented subset; they
are not evidence of universal layout, object, macro or signature fidelity.
