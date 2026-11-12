# Layout and pagination controls

The portable parser now retains additional layout instructions in
`LegacyWordParagraphStyle.layout` and `LegacyWordSection.layout`. Conversion
emits editable WordprocessingML. It does not freeze a particular printer's
pagination into artificial paragraph breaks.

Supported paragraph controls include widow/orphan prevention, line-number
suppression, automatic-hyphenation suppression, right-to-left layout,
contextual spacing, mirrored indents, automatic before/after spacing and
explicit supported East Asian wrapping/spacing flags. Manual column breaks
remain `\u000e` in a run and become `w:br type="column"`; preview uses a column
break marker instead of dropping it. Existing manual page/line breaks and
keep-with-next/keep-lines controls remain distinct.

Sections retain equal or unequal column widths and inter-column spaces,
separator lines, vertical justification, line-number interval/start/restart,
page-number restart and the five basic counting formats, and document-grid
line pitch and signed character spacing. A stored page-number start alone
does not enable restarting. Unequal columns require complete bounded widths;
invalid values and enabled grids without a line pitch are rejected.

Automatic footnote/endnote labels retain the fixed MS-OSHARED MSONFC counting
formats, including East Asian, Hebrew, Arabic, Hindi, Thai, Vietnamese and
Russian numbering, alongside Roman, alphabetic, decimal, Chicago and explicit
`0xFF` no-label numbering (`none`). The same native `w:numFmt` instructions
are kept in current section properties and historical `w:sectPrChange`
snapshots. This preserves the requested numbering system; it does not prove
identical glyph selection or pagination in every Office renderer.

Starting values, restart rules, footnote placement and document-wide endnote
placement remain independent of the number format. Word 97/2000
DOP defaults are read only for versions to which those fields apply. Later
files use section SPRMs; their note offsets are active only for continuous
numbering. Inactive source offsets remain available in the model. The existing
complete DOP size and version gates are unchanged; a FIB layout alone does not
identify a producer or enable reserved legacy note defaults.

Bullet (`0x17`) uses Word's documented decimal fallback. Legacy
application-defined format `0x28` uses the decimal mapping published in
MS-OSHARED. Both retain their numeric source codes, set `usesDecimalFallback`,
and report `unsupportedNoteNumberFormat` and a notes/comments conversion
limitation. Unknown 16-bit codes retain a null resolved format, emit no invented
`w:numFmt`, and report the same limitation. Fallback and unknown source codes
are also retained as inert `noteNumberFormat` evidence in the DOCX, with the
section CP range and a flag distinguishing current from historical properties.
Per-section endnote suppression remains a native `w:noEndnote` instruction.

`legacy_word_note_formats_test.dart` independently authors DOP and SEPX inputs
for every supported fixed code and checks both model values and native XML,
including preserved footnote/endnote references. It separately checks unknown
codes, fallback diagnostics, version gates, truncated records, and accept/reject
section-property projections. `tool/fidelity/note_format_fixture.dart` generates
nine deterministic DOC/DOCX pairs for the independent Open XML SDK schema gate.

The public line-number start is the displayed number. Native `w:lnNumType`
uses the source skip count (`displayed start - 1`), matching Word's documented
interpretation. A default start of one therefore emits zero. Valid unsigned
DOC starts outside Word's documented native range are retained with an
interoperability limitation. Regression tests independently construct DOP and
SEPX bytes, exercise version gates and ignored offsets, and reject invalid
position/restart operands without reading beyond declared DOP boundaries.

The PRM0 lookup is corrected against the current Microsoft table: widow
control, no-hyphenation, mirrored indents and East Asian flags no longer use
shifted historical lookup entries. The same flags work through direct PAPX,
styles, and piece-level properties. Synthetic fixtures assert binary values
and independent OOXML attributes, including zero/false overrides.

## Native interoperability recovery

One Quds table-border fixture exported by LibreOffice has a final footnote
whose declared range ends with a closed table-row mark instead of the CR
required by MS-DOC. The parser can recover this exact case if the final range
is followed by its own guard CR, the parsed final block is a closed table,
and its endpoint exactly matches the declared range. It neither extends the
note into another story nor invents table structure. The document reports
`recoveredTableStoryBoundary`; ordinary malformed or unterminated ranges still
fail. This is an explicit compatibility recovery, not a relaxed format rule.

The same bounded recovery now covers native header/footer content ending at a
closed table-row mark immediately before its own guard CR. The complete parsed
table must end at that exact content boundary; stray cell marks, unclosed rows,
missing/wrong guards and unterminated text still fail. Adjacent header/footer
stories remain disjoint and no paragraph is borrowed from another range.
[MS-DOC Headers](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/8465bee7-6c79-45a9-812e-58b0c5fd6cdc)
requires separate content and guard paragraph marks, so the document still
reports `recoveredTableStoryBoundary` for this native interoperability case.

The [four retained native controls](evidence/header-table-boundary-20261112/README.md)
cover headers and footers, each ending with a table or a following paragraph.
Both table-ended sources previously failed import; all four now retain their
text and table, with unchanged paragraph-ended output. The table-ended footer
has a measured 0.35-point common vertical offset and the table-ended header has
a 0.35-point body-text offset. Relative table geometry is unchanged; these
measurements do not assert whole-page equality.

A native DOCX-to-DOC round trip also exposed an empty initial section with two
leading zero CPs. The parser retains that initial section's identity and layout
with `recoveredEmptySection`. Conversion carries it as an empty OOXML section,
records the change in evidence, and does not claim identical reflow. Arbitrary
duplicate or decreasing section ranges remain invalid. Field instructions with
binary object controls stay inactive evidence with their visible stored results;
they do not cause a whole-document XML serialization failure.

## What exact pagination still requires

Native rendering depends on font metrics and substitution, character shaping,
compatibility flags, wrap geometry, table and note layout, field results, and
the selected Office version. The corpus runner records those available
environment details and compares actual page words, positions and raster
pixels. An equal page count, retained page settings, or an XML round trip
alone does not establish exact pagination. See [fidelity-oracles.md](fidelity-oracles.md)
for the repeatable native measurement path.

Primary format references:

- [MS-DOC paragraph properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/484822ee-a9d9-4af4-8423-29fda67a6a58)
- [MS-DOC section properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/46c3ec54-53ff-4c0a-b0d6-07ad15d2546e)
- [MS-DOC PRM0 mapping](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/35226a0b-9038-4427-83c2-3830a8554267)
- [Column width operands](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/25ac9549-1b44-49d2-a179-e066fabe6251)
- [Column spacing operands](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/d11123e4-00fe-433d-af28-605823dbe236)
- [Footnote text ranges](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b30472e7-569e-4c9c-a8ca-07fd5432f365)
- [DopBase document note settings](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f885b87a-15b3-460e-aecc-213bd17f960e)
- [Dop97 note numbering formats](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/2feeb178-f901-4151-bf5c-8496d5a0700b)
- [MS-OSHARED MSONFC numbering formats](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-oshared/57c8f7d4-1426-44e0-b58d-6fa1a5a81659)
- [Word bullet note-format fallback](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/8863768d-49d8-4d6f-bacc-7a63e162d336)
- [Word line-number start semantics](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/c4252e13-48d2-4ac9-9fb5-3b276d02be30)

## Isolated compatibility spacing discrepancy

The clean 8060ac1 native corpus retains a 3.05-point offset before `Beta` in
the bookmark fixture. A controlled 61-option isolation identifies
`balanceSingleByteDoubleByteWidth=1` as the only individual option that
reproduces that offset. Copying native fonts, removing kerning, or assigning
compatibility mode 11 does not resolve it. The
[measurement receipt](evidence/compatibility-spacing-native.json) retains the
source bytes, all isolated results and output hashes.

All recorded source compatibility copies have `fDntBlnSbDbWid=0`. Microsoft's
[Copts60 definition](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/8b8c7ac1-c424-40c2-8645-ba719af38bf9)
requires the opposite meaning for the native OOXML flag. The
[OOXML contract](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.balancesinglebytedoublebytewidth)
defines the half/full-width adjustment. The parser therefore retains the
enabled instruction. Removing source semantics to obtain a LibreOffice-only
pixel match is not an accepted correction. The DOC and DOCX routes disagree
on the recorded renderer; Microsoft Word was not run to arbitrate its layout.
