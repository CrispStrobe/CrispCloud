# Disabled character-width balancing

Runtime `17ee78702a4dd06d499b7fd63b0b08e05c10d24d` removes the initial
**1.446-point** Word16 interword discrepancy. All three source words now have
exactly the binary source's measured word boxes. Page size and layout text also
match; other image/raster differences remain outside this correction.

## Source setting and equivalent XML

The original Word16 file sets `fDntBlnSbDbWid=1` in all three compatibility
copies. Its meaning is the inverse of OOXML
`balanceSingleByteDoubleByteWidth`: the source disables width balancing.
The parser model and original evidence bytes continue to retain this explicit
false value. Only the target spelling changes: the disabled option is omitted,
which has the same meaning under ISO 29500-1 section 17.15.3.3. Explicit true
remains `w:val="1"`; other flags are unchanged. No compatibility mode is added.

The measured LibreOffice build is
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. Its DOCX settings importer assigns
`m_bBalanceSingleByteDoubleByteWidth = true` when it sees the element, ignoring
its value. Four output-only probes confirm that `0`, `false`, `off`, and `1`
all give the same wider space. Omitting only that element gives the correct
normal-space width. Language, kerning, paragraph/run formatting, complex-script
size, and compatibility-mode probes independently failed to change the gap.

| Measurement | Space origin | Following `für` origin |
| --- | ---: | ---: |
| Original binary PDF | 163.400 pt | 165.146 pt |
| Prior parser output, explicit false | 163.400 pt | 166.592 pt |
| Corrected parser output, omitted false | 163.400 pt | 165.146 pt |

The exact source is the unchanged checked fixture
`test/fixtures/word_native/word16-page-origin.doc`. Its DOP starts at `1Table`
byte 30364, length 694. The compatibility copies at bytes 30372, 30448, and
30872 start with `00 f0`, so bit 15 is set in every copy. `summary.json` records
the full bytes and the measured native comparisons.

## Repeat result and remaining native bridge limitation

The three-cycle rerun does **not** prove complete native roundtrip fidelity.
The first native DOC export changes the source bit to zero in every copy.
Its DOP starts at byte 2318, length 610; copies at 2326, 2402, and 2826 start
with `00 00`. The regenerated binary therefore explicitly requests balancing.
The parser correctly emits true for this changed source, and the 1.446-point
interword difference returns in cycle one. Cycles two and three add no further
word-position drift.

The pinned native DOC importer unconditionally disables this option
(`ww8par.cxx`, line 1993, `tdf#167552`). The DOC export function first copies its
saved compatibility word and does not map the current balancing setting back
to `fDntBlnSbDbWid`. This explains why its PDF ignores the regenerated binary's
enabled bit. Suppressing explicit true would discard the changed source's
instruction, so the converter does not do that.

The independent `word-compatibility` fixture was measured through the same
three cycles. Its initial page geometry, words, layout text, and RGB raster are
exactly unchanged from `0c3e596`. Its existing section and note differences
remain separately attributed. Full comparisons for all repeat stages are in
`summary.json`.

## Retained evidence and validation

`diagnostics.tar.xz` contains both complete native runs, six repeat cycles,
original inputs, converter build/source receipts, lossless RGB artifacts,
counterfactual DOCX/PDF probes, raw source stream dumps, the independent
CLX/PAPX decoder, and pinned native-source excerpts. Rebuildable executables
and temporary native profiles are excluded; their required build provenance
is retained. `manifest.json` names and hashes every regular archive member.
Run `python3 doc/evidence/compatibility-width-balance-20261113/verify.py` to
verify exact member coverage, sizes, and hashes without extraction.

The runtime source was clean throughout compilation and native measurement.
All 33 focused compatibility/table-position tests pass, including explicit
true, explicit false, absence, raw evidence, and all three Word16 source copies.
No historical fixture or golden was rewritten.

Primary references:

- [ISO 29500-1 section 17.15.3.3, Microsoft Open XML documentation](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.balancesinglebytedoublebytewidth?view=openxml-3.0.1).
- [MS-DOC Copts60, inverse bit meaning](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/8b8c7ac1-c424-40c2-8645-ba719af38bf9).
- [Pinned DOCX settings importer](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/writerfilter/dmapper/SettingsTable.cxx).
- [Pinned DOC importer](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/ww8par.cxx).
- [Pinned DOC exporter](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/filter/ww8/wrtww8.cxx).
