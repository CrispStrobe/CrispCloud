# Original LibreOffice Zotero converter fixtures

These are unchanged files from the research-note formatting increment's
`docs/validation/zotero-note-formatting-20261122/evidence/converter-after-fix.tar.xz`.
The archive is retained in history at `b91fba039e123d3db767bc5178de59922a163e74`.
`manifest.json` records the original member names, sizes and SHA-256 hashes.

The generator produced body, authored-footnote and table-cell notes containing
two active Zotero citations, document preferences, explicit direction/alignment,
heading and empty paragraphs, indentation, foreground and highlight colors.
`original/` contains its native DOCX/ODT and its unchanged expected snapshots.
Each `*-cycle-N/` contains the actual output after N successive saves by
LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.

The earlier strict native checker refused all six saved ODTs for outline styles
and found both citations noneditable in all six saved DOCX files. The new tests
operate on those exact files; they do not simplify the input to fit the reader.
Snapshot comparisons cover text, selected paragraph formatting, colors, field
metadata, ownership and editability, preferences and balanced boundaries. They
do not qualify complete typography/pagination or installed Zotero plugins.

Additional negative controls are explicitly modified in-memory copies. Tests
must never overwrite these original converter outputs or expected snapshots.
