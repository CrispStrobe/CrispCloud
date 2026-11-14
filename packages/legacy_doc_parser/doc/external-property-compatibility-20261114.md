# External property compatibility, 14 November 2026

This focused audit investigated three Apache POI regression documents in the
[pinned external corpus](../test/fixtures/external/poi-20261114/README.md).
The files are external issue samples, not claims of unchanged production
documents. The fixes preserve the source bytes and distinguish ignored
properties, unsupported active features, and malformed records.

| Source | Original structured result | Disposition |
| --- | --- | --- |
| `Bug51834.doc` | Invalid paragraph border type | Fixed: ignore `BrcType=0xFF` while retaining the prior border. |
| `57603-seven_columns.doc` | Invalid list level during inherited style resolution | Fixed: resolve list context before validating the level, and allow a documented legacy numbering ancestor to be replaced by a modern child. |
| `56880.doc` | Unexpected revision-author data | Retained rejection: the entire declared 22-byte author table is zero. |

## Ignored borders retain their previous value

[MS-DOC BrcType](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/6d25d117-9fa4-42ed-af5b-672771a9d1be)
defines `0xFF` as ignored. `Bug51834.doc` contains the eight-byte operand
`ffffffffffffe0ff` in its `Data` stream at offset 2842. Its last four bytes are
`ffffe0ff`, so this is not the separate
[BrcMayBeNil](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/4e2ba2c9-8763-4b29-b81c-ce0123df689e)
nil encoding. Treating an ignored descriptor as an explicit absent border
would incorrectly erase preceding or inherited formatting.

The border reader now represents ignored descriptors separately from ordinary
border values. Paragraph, row, cell-range, TC80, table-style, and conditional
table-style application preserve prior borders when the descriptor is ignored.
Genuine modern/old nil descriptors still clear the border. Operand lengths,
range bounds, and undefined border-type rejection remain enforced.

## List properties require their final context

[MS-DOC paragraph properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/484822ee-a9d9-4af4-8423-29fda67a6a58)
require `sprmPIlvl` to be ignored when a paragraph is not in a list. Its active
modern list values remain 0–8 or 12. Validation now uses the final list identity
for both the current paragraph and retained paragraph-format history, rather
than rejecting an inapplicable byte while composing properties.

The seven-column sample revealed an additional compatibility distinction.
Styles 40 and 41 carry level 10, list identity 2047, and 84-byte `PAnld80`
operands; style 42 inherits the identity and level. Style 43 replaces them
with modern list identity 6 and level 0. Style 53 similarly replaces style
40's properties with modern identity 7 and level 0.

The older Microsoft
[Word 97–2007 binary format specification, page 73](https://download.microsoft.com/download/0/b/e/0be8bdd7-e5e8-422a-abfd-4342ed7ad886/word97-2007binaryfileformat%28doc%29specification.pdf)
documents identity 2047 as the compatibility marker for pre-Word-97 ANLD
numbering. It is not a modern list-table index. That marker can now survive
intermediate inheritance and be replaced by a supported descendant. An active
current or historical marker still raises `Unsupported pre-Word 97 numbering.`
No ANLD numbering definition is fabricated, and no active legacy numbering is
silently discarded. Neighboring undefined identities still reject. Retaining
level 10 after selecting a modern list also still rejects.

The sample's main document is an empty seven-cell table. Acceptance establishes
that the inherited compatibility records no longer prevent reconstruction of
that table; it does not establish full ANLD rendering support.

## The zeroed author table is not padding

[SttbfRMark](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/fca5d9de-3eaa-4587-a482-c454e340c070)
requires the extended string-table header and an initial `Unknown` entry.
`56880.doc` declares 22 bytes at `1Table` offset 1351, all zero. The missing
header and entries cannot be explained as harmless trailing padding. Both this
actual sample and a minimized zero-table control retain explicit rejection.
LibreOffice and Apache POI opening the file does not establish conformity of
that author record.

## Validation and limits

The final focused suite contains 82 tests. It covers five inapplicable list
levels through direct, inherited, piece, list-removal, and no-list-sentinel
paths; active invalid levels in either property order; current/history
resolution; legacy numbering ancestors and rejection boundaries; old/modern
borders in nine contexts; genuine nil; undefined border types; and the three
actual inputs. The final real-file assertions also check visible text length,
table grids, and cell counts against independent LibreOffice import evidence.

The corrected 73-case suite on unchanged baseline `6b0d7e8` had 27 passes and
46 failures. After adding the ANLD controls, the expanded baseline suite had
28 passes and 54 failures. Some failures in that expanded count concern a
more precise rejection message, so 54 is not a count of valid documents newly
accepted. The repaired focused suite passes all 82 cases. The 22 adjacent
test files, including the focused suite, pass 1,142 tests. Strict Dart analysis
finds no issues. An independent code review found no actionable issue in the
narrow runtime diff; it did not rerun those test suites.

Both repaired files export deterministically in both field modes. Direct
LibreOffice DOC import independently agrees with the converted `w:t` text,
every table's row/cell counts, and table-grid counts:

| Source | Visible text characters | Tables | Grid columns | Agreement |
| --- | ---: | ---: | --- | --- |
| `Bug51834.doc` | 4,897 | 2 | 4, 1 | Exact visible text and row/cell sequences |
| `57603-seven_columns.doc` | 0 | 1 | 7 | Empty one-row, seven-cell table |

These comparisons do not establish pixel or pagination equality. The parser's
existing unsupported-formatting disclosures remain present. The broader
40-file corpus and SDK checks are maintained separately from this focused
property audit.

The [evidence directory](evidence/external-property-compatibility-20261114/README.md)
retains independent byte inspection, exact hashes, test logs, and the native
comparison receipt. The source binaries and upstream license notices remain
in the pinned external corpus.
