# Preferred cell widths and no-wrap provenance

The cell model keeps the preferred width separately from the physical grid
interval. `LegacyWordTableCell.widthTwips` still describes geometry from the
row's cell boundaries. `LegacyWordTableCellFormat.preferredWidth` retains the
source unit and value from TC80 or `sprmTCellWidth` (`0xD635`). The writer emits
the preference as native `w:tcW` without changing `w:tblGrid` or merge spans.

| Binary width | Model unit | Native cell width | Value |
| --- | --- | --- | --- |
| `ftsNil` | `nil` | `w:type="nil"` | Undefined operand normalized to zero |
| `ftsAuto` | `auto` | `w:type="auto"` | Zero |
| `ftsPercent` | `percent` | `w:type="pct"` | Fiftieths of a percent, 0–5000 |
| `ftsDxa` | `twips` | `w:type="dxa"` | Twips, 0–31680 |

This separation matters when a 2400-twip grid cell has a 1200-twip preferred
width, or when the source explicitly selects automatic sizing. Substituting
the grid interval for every preferred width discards those distinctions.
Range edits keep the preferred width attached to the same cell through later
insertions and deletions. A later table style does not erase cell definitions.
The independent Word-authored Apache POI fixture `poi-simple-table2.doc` retains
its three 3192-twip preferred widths in each row, including properties obtained
through the Data stream.

## Evaluate no-wrap after width resolution

TC80's `fNoWrap`, range `sprmTFCellNoWrap` (`0xD639`), and the table-style
no-wrap property retain their raw preference as `noWrapPreference`. The public
`noWrap` getter reports the effective value: MS-DOC requires this preference to
be ignored for a `ftsDxa` preferred width. Merging styles, conditions, and direct
cell formats therefore merges the raw preference and width separately.

For example, a raw true preference followed by a dxa width is currently off.
A later `TCellWidth` selecting auto makes that original preference effective
again. An explicit false range property remains false. A regression test also
applies one conditional first-row rule to two cells, proving that auto remains
on while dxa is explicitly off without losing the original rule.

The DOCX writer uses the effective value with schema-valid `on`/`off` values.
OOXML no-wrap has a different interaction with fixed preferred widths, so
copying an ignored binary true flag into `w:noWrap` would change its meaning.
When a true source flag is suppressed by dxa, `word/evidence/manifest.json`
records `cellNoWrapWidthContext`, the table and cell character positions, the
source flag, and the width. This is retained provenance, not an Office feature
that automatically reactivates the flag after a user changes the DOCX width.

The parser rejects invalid range endpoints, non-boolean no-wrap operands,
undefined or spacing-only cell width units, negative TC80 widths, out-of-range
percent/dxa widths, and a nonzero automatic `FtsWWidth_TablePart` operand. A nil
range operand is undefined by the specification and is ignored. TC80's
nonnegative but otherwise unused nil/auto operand is normalized to zero.

## Evidence and oracle limits

`tool/fidelity/table_width_fixture.dart` produces 18 literal DOC inputs and
their converted DOCX files. The fixture module imports no production parser
or model. It covers six pairs of TC80 versus range representations, both
width-change directions, explicit no-wrap reset, inherited style no-wrap,
asymmetric preferences, and a changed-grid control.

The independently built Open XML SDK 3.3.0 validator reports zero errors for
all 18 converted files. The focused table suite passes 125 tests. Existing
native measurements also remain green: nine origin cases, twelve border
cases, and eight row/cell layout cases. These results are distinct checks;
schema validity does not establish rendering equivalence.

LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, exposes an important oracle limit:

- All six TC80/range pairs yield matching native projections and geometry.
  However, the bridge rewrites nil, auto, percentage, and differing dxa
  preferences to physical dxa grid widths and removes no-wrap. It cannot
  independently establish that those source distinctions are implemented.
- The 16 non-style inputs have matching word sets, page placement, and word
  bounds between source DOC and converted DOCX, with a maximum measured delta
  of 0.0 points. Asymmetric preferred widths alone leave `SECOND` at x=197.5
  points. Changing the physical grid moves it to x=137.5 points in both paths,
  confirming that the measurement detects actual geometric changes.
- The two TInsert-only style inputs are flattened by the native DOC importer.
  Their different source and converted layouts are recorded explicitly. They
  remain binary/model/XML and SDK checks, not passing native table-rendering
  comparisons.

`test/fixtures/word_native/table-width-golden.json` retains reviewed source
hashes, both native projections, and word bounds. It deliberately keeps the
lossy native result separate from the expected converter properties. The
golden checker rejects replacing preserved automatic or percentage output
with the bridge's dxa projection even when the pixels match. It also rejects
changed source bytes, missing or duplicate cases, altered page placement,
word loss, and more than 0.1-point drift. Goldens are never updated by the
probe.

To regenerate and compare the full fixture inventory:

```sh
dart run tool/fidelity/table_width_fixture.dart build/table-width
python tool/fidelity/table_width_probe.py \
  --office /absolute/path/to/soffice \
  --fixtures build/table-width \
  --output build/table-width-native \
  --golden test/fixtures/word_native/table-width-golden.json
```

This increment does not add the range text-flow, fit-text, or hide-mark
properties. Their existing TC80 support remains; corresponding range forms
need independently discriminating fixtures. Table-wide preferred widths and
full automatic layout negotiation also remain separate work. These bounded
cell semantics do not establish complete table or pagination fidelity.

## Primary format references

- [MS-DOC TableCellWidthOperand](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/e0d4c0db-623d-4a6f-94d2-48e05f34f564)
- [MS-DOC FtsWWidth_TablePart](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/78aa9e68-a732-4bd6-9344-9c9d2b8a6e55)
- [MS-DOC TC80](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/9dd62a79-8c0b-4b11-99ee-05742ae7cf6d)
- [MS-DOC TCGRF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/11bf5b1c-943f-421d-bbf3-39088cd1b8dd)
- [MS-DOC Fts](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/930b1e39-1132-4f68-9cb0-eb1ebdc39c5e)
- [MS-DOC CellRangeNoWrap](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/2e44082b-2cf0-464f-9167-05b83f0ba97d)
- [MS-DOC Table Properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/b39a6648-501c-4361-8366-4f042f579469)
- [Open XML noWrap](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.nowrap?view=openxml-3.0.1)
- [Open XML TableCellWidth](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.tablecellwidth?view=openxml-3.0.1)
