# Native table-ended header and footer recovery

Four literal authored OOXML controls place the same table in a header or footer,
with either a table or a nonempty paragraph at the end of the story. The native
DOC bridge writes a closed table-row marker directly before the guard CR in the
table-ended cases. Before this change, both whole-document imports failed with
`Word header content is not a complete paragraph`; the paragraph-ended controls
already imported successfully. `before.log` retains those exact outcomes.

MS-DOC Headers §2.3.3 specifies a content CR followed by a guard CR. This change
is an explicit interoperability recovery for the observed native representation.
It accepts a table-row terminal only if the guard is present, the table parses
completely and the final table endpoint equals the declared story boundary.
It neither extends a range nor manufactures a missing row. Recovery is disclosed
through `recoveredTableStoryBoundary`. The portable controls reject stray cell
marks, unclosed rows, missing/wrong guards and incomplete text. All six header
and footer variants check exact range endpoints; the five nonfinal slots also
check that the following story remains separate.

The retained four DOC inputs and their provenance are under
`test/fixtures/word_native/header-footer-table-endings.provenance.json`.
`tool/fidelity/header_table_fixture.dart NEW_DIRECTORY` converts those exact
inputs without requiring Office, producing the four schema controls.

Native conversion/rendering uses LibreOfficeDev 26.8.0.0.alpha0
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. All four corrected imports retain the
expected story text and table. The two paragraph-ended converted packages remain
byte-identical to their pre-fix counterparts. All observed story-relative marker
positions agree exactly with the respective binary DOC source. Absolute marker
positions differ by 0.35 pt for the table-ended footer; the table-ended header's
body text also moves by 0.35 pt. Those remaining differences are recorded, not
classified as exact pagination or RGB equality.

`report.json` records each converter result, source hash, complete marker boxes,
absolute deltas, relative deltas and the measured Dart runtime source inventory.
The small archive retains literal authoring code, original DOCX, native DOC,
pre-fix log, both available pre-fix DOCX files, all corrected DOCX files, source
and corrected PDFs, and Poppler bounding boxes. `manifest.json` pins every file
and the archive; all entries were verified after packing. Extract into a new
directory and verify hashes before replaying. No input is rewritten by the
portable generator or the parser.
