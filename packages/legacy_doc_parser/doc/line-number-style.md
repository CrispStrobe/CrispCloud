# Explicit Line Number character formatting

Generated line numbers have no ordinary text CP/CHPX run. The parser previously
retained their section numbering settings but dropped an explicitly stored
Line Number character style. The new optional `LegacyWordDocument.lineNumberStyle`
retains that resolved formatting and the DOCX writer emits the standard
`LineNumber` character style with the built-in name `line number`.

## Source contract

The source identity is `StdfBase.sti = 40`, independently of its stylesheet
index and localized display name. The source must have one unambiguous
character style (`stk = 2`). Its parent chain and character properties use
the existing bounded style resolver, including inherited fonts and explicit
boolean resets. An ordinary user style named `line number` does not acquire
the built-in meaning. Absence remains `null`; the parser does not invent a
style from a body paragraph or a renderer's fallback font.

Microsoft's [StdfBase definition](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/df0f4654-071d-442f-8563-752d7e0285ef)
specifies the language-independent identity, style kind and parent index.
The [style-property algorithm](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/9258b41c-ff0a-4c96-a3a9-610664dabbeb)
specifies inheritance from that parent. The independent fixture's raw STD
stores `sti40` at index 16, with parent 15. Its CHPX explicitly specifies
font index 8 (Courier New), 28 half-points, bold and color `CC2233`.

## Discriminating measurement

The independently authored source uses Arial 11 pt body text and Courier New
14 pt bold red line numbers. Its native DOC bridge preserves the original
page exactly. The pre-fix parser output drops the line style, changes the
number glyphs, and has 0.9 pt maximum word-origin drift. Adding only the
decoded line style to that output restores exact RGB, text and geometry;
every other package part stays byte-identical.

The actual committed runtime reproduces that result without output editing.
The initial import and all three native DOC save/import cycles match the
binary source in page RGB, layout text and word boxes, with 0.0 pt drift on
LibreOfficeDev `26.8.0.0.alpha0`, revision
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. This is a measured renderer result,
not a Microsoft Word or all-document exactness claim. Structural/default
serialization differences remain in the unmodified native reports.

See the [sealed source and rendering evidence](evidence/line-number-style-20261113/README.md)
for the failing control, the output-only counterfactual, the committed-runtime
run, exact byte inventories and the independent Open XML SDK gate.

## Remaining compatibility cases

The old `word`, `word-compatibility` and `bookmarks` source documents contain
no explicit `sti40` style. Their converted DOCX bytes are unchanged by this
fix. Their remaining native differences therefore stay visible:

- The generic `word` case retains the independently attributed native list
  indentation disagreement. Cloning the already retained note-marker direct
  formatting into a custom character style did not change its glyph geometry.
  Assigning built-in note-reference style names changed anchor behavior and
  was rejected. Neither experiment established a dropped source character
  property for those markers.
- The `bookmarks` source enables width balancing. Removing the option from
  the output reduces the measured 3.05 pt offset to about 0.018 pt, but would
  discard a valid source instruction. The existing
  [compatibility-spacing audit](layout-fidelity.md#isolated-compatibility-spacing-discrepancy)
  explains the DOC/DOCX renderer disagreement. Both true and false source
  values remain supported.
- In `word-compatibility`, the native DOC route drops the source's initial
  line-number start/restart behavior. The parser retains first-section start
  4 and restart per section. The native route also consumes an inapplicable
  old-version DOP note start; the parser's note start follows the source
  version rules, as recorded in the
  [independent note audit](evidence/note-source-attribution-20261113/README.md).
  The native DOCX exports its RTL table at indentation 11868 twips and the
  binary PDF omits `Selected table fallback`; the parser keeps the source
  table visible. This is evidence against treating native missing table
  text as a parser target, not a reason to drop the table or reverse cells.

The implementation preserves Letter defaults, section and note numbering,
source compatibility flags, and the earlier evidence. The original 24-case
native corpus is unchanged; the independent schema corpus adds this new
native fixture as its 230th case.
