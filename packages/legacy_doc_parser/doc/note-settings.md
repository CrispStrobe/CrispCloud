# Footnote and endnote settings

The parser keeps document defaults in `LegacyWordDocument.footnotes` and
`.endnotes`. A section has optional resolved overrides of those settings and
the source `suppressEndnotes` flag. Number formats, restart modes, and positions
are fixed enums. Starts are bounded to 0–16383. Note text, source CPs, and
reference IDs keep their existing representation.

## Sources and version rules

- [MS-DOC: determining nFib](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/fe661052-9c88-4ae1-aec4-44799b2b4777): the FIB extension, when present, selects the effective format version.
- [DopBase](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/f885b87a-15b3-460e-aecc-213bd17f960e) and [Dop97](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/2feeb178-f901-4151-bf5c-8496d5a0700b): old document-wide footnote placement and note numbering apply through Word 2000. The endnote destination remains a document setting in later versions.
- [Section properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/46c3ec54-53ff-4c0a-b0d6-07ad15d2546e), [Rnc](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b48b13f9-dec8-4f81-aa15-c50696ff48dd), and [SFpcOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/681463bb-4e5e-4fbf-92b6-b366c527ea89): section placement, restart, formats, continuous-numbering offsets, and endnote deferral are decoded independently.

Modern sections default to decimal footnotes and lower-Roman endnotes, starting
at 1 with continuous numbering. Footnotes default to the page bottom. An absent
DOP uses document-end endnotes. A present DOP supplies its explicit endnote
destination. Section starts are continuous-numbering offsets; the parser ignores
them when the section restarts numbering, as required by MS-DOC. Legacy DOP
starts apply at restart points too.

Reserved positions/restarts, invalid formats, oversized starts, malformed FIB
extensions, and incomplete operands fail. Old fields in a normal modern file
are ignored, including stale invalid values. Bullet/application-defined note
formats use decimal with `unsupportedFormatting`, rather than emitting an
unsupported format or guessing a definition.

## Bounded interoperability recovery

The native `word-compatibility` bridge advertises base nFib `0x101`, 136 FIB
pairs, no FIB extension, and a 610-byte DOP. Its sections specify lower-Roman
footnotes with per-section restart but do not specify a start. The starting
value 4 remains only in the old DOP. The installed LibreOffice importer uses it.

Only that exact four-part layout activates the legacy defaults in a newer
file. Explicit section values still override them. The parser adds
`recoveredLegacyNoteSettings`; this is a reported interoperability recovery,
not a revision of the normative version rule. Tests change each relevant
version/layout predicate and ensure that unrelated modern files do not activate
obsolete defaults.

## WordprocessingML output

The writer emits document-wide `footnotePr`/`endnotePr` in settings and section
overrides before `type` in `sectPr`. It writes fixed `pos`, `numFmt`, `numStart`,
and `numRestart` values. Matching special-note IDs are emitted only when active
note parts exist; hidden/private source notes cannot be activated by settings.

The source deferral flag becomes `noEndnote` only for end-of-section endnotes,
consistent with the [Word section API](https://learn.microsoft.com/en-us/office/vba/api/Word.PageSetup.SuppressEndnotes)
and [WordprocessingML section reference](https://learn.microsoft.com/en-us/previous-versions/office/developer/office-2003/aa173692%28v%3Doffice.11%29).
This preserves editable note settings. It does not calculate pagination, invent
literal reference marks, or guarantee identical layout in every renderer.

Header/footer distances are separate. Explicit zero is preserved through
parsing and DOCX emission. An absent source operand keeps its existing default;
a native importer emitting zero for an unused header is not evidence that the
binary contained zero.

## Verification

`test/legacy_word_note_settings_test.dart` independently assembles DOP bytes,
SEPX operands, FIB versions, and note references. It checks modern/legacy rules,
the narrow exporter recovery, section isolation, ignored offsets, malformed
bounds, public-model bounds, zero distances, XML order, unchanged source bytes,
and hidden-note safety.

[`note-settings-native-check.json`](note-settings-native-check.json) records the
actual native bridge and generated output hashes. Both source and converted
documents render the reference and footnote with `iv`; package metadata agrees
on lower-Roman format, start 4, and per-section restart. This receipt covers those
note facts only, not the other layout features in the fixture.
