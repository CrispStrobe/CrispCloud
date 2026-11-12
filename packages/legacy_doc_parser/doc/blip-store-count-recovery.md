# Bounded recovery of a constant BLIP-store count

The three-cycle native corpus run at parser checkpoint `8060ac1` found a
failure after converting the independent Word16 page-origin fixture to
DOCX and then exporting that DOCX back to DOC with LibreOffice. The original
Word-produced DOC imported successfully. Its regenerated DOC stopped with
`Invalid OfficeArt BLIP store` before conversion.

The cause is an incorrect record count, not a missing image. The original
OfficeArt BStore header declares two entries and contains two complete
FBSEs. The regenerated header declares one entry, but its 88-byte payload
contains two complete 44-byte FBSE records. Both entries refer to bounded
PNG BLIPs in the WordDocument stream.

## Source and independent implementation evidence

[MS-ODRAW section 2.2.20](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-odraw/561cb6d4-d38b-4666-b2b4-10abc1dce44c)
defines `recInstance` as the number of contained file-block records and
`recLen` as their combined byte length. A constant count of one is therefore
nonconforming when two entries follow.

The pinned LibreOffice exporter independently explains this pattern:
[`EscherGraphicProvider::WriteBlibStoreContainer`](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/filter/source/msfilter/escherex.cxx)
writes the low header word `0x001f` regardless of the number of entries.
The version occupies its low four bits and the declared count is therefore
always one. The same revision's
[`SvxMSDffManager::GetDrawingGroupContainerData`](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/filter/source/msfilter/msdffimp.cxx)
walks FBSEs by their bounded container extent.

## Recovery contract

The parser accepts this mismatch only when a single version-15 BStore has a
declared count of one and contains 2–4095 complete version-2 FBSE records.
Each must have the observed 36-byte, nameless, delayed-entry payload, a
nonzero reference count, a delay offset other than `0xffffffff`, and a BLIP
instance matching its platform type. Every recovered entry is then read
through the existing delayed-BLIP size, offset, record and image decoder,
including entries that no drawing references. This reuses the existing
record, image and retained-byte budgets; it does not scan for image signatures.

Other count mismatches, duplicate stores, embedded-entry mismatches, partial
records, empty slots, malformed delayed payloads and out-of-range image
indices still fail. Ordinary matching-count files keep their existing path.

The original OfficeArt bytes remain inert evidence. A
`recoveredBlipStoreCount` notice points to the original store record, and
DOCX conversion reports partial formatting. Prevalidation caches the actual
entries, so every used one-based image index resolves against the complete
bounded array without duplicate decoding.

## Retained native specimen

`test/fixtures/word_native/word16-page-origin-lo-blip-count.doc` is the exact
24,576-byte regenerated DOC that originally failed. It was produced by
LibreOfficeDev `26.8.0.0.alpha0` at revision
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, from the parser's converted DOCX.
The upstream Word source and MPL2.0 credit are recorded in
`test/fixtures/word_native/POSITION-SOURCES.md` and `COPYING.LibreOffice`.

| Artifact | SHA-256 |
| --- | --- |
| Original Word16 DOC | `3e105980f47af62c81c1c451b0339e34d3fdfe6972c1fe5c664e7b25d966f84d` |
| Parser DOCX used by the native exporter | `280ea69fcb49e005a751010c7df5e0eb9d68fc2bb097d9ef9568bdb6d8168547` |
| Retained failing regenerated DOC | `0afe11e2355151b75a66d41e0bd1ec64aea5326e0a53c5b757775596f2cc5a30` |

The regression tests exercise the native specimen and malformed neighboring
cases. `tool/fidelity/blip_store_probe.py` repeats three further
DOCX→native-DOC→parser cycles, requires both image assets and both drawing
references at every stage, checks image bytes and unchanged sources, and
records native PDF comparison results separately. Successful import is not
an assertion of exact pagination or complete visual fidelity.
