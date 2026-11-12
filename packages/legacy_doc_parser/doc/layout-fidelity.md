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

Automatic footnote/endnote labels now retain the basic Roman, alphabetic,
decimal, zero-padded decimal and Chicago formats, starting values, restart
rules, footnote placement and document-wide endnote placement. Word 97/2000
DOP defaults are read only for versions to which those fields apply. Later
files use section SPRMs; their note offsets are active only for continuous
numbering. Inactive source offsets remain available in the model. Unknown
formats retain their numeric source code and report a formatting limitation.
Per-section endnote suppression remains a native `w:noEndnote` instruction.

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
- [Word line-number start semantics](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/c4252e13-48d2-4ac9-9fb5-3b276d02be30)
