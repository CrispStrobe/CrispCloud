# External corpus audit evidence, 14 November 2026

This directory preserves an immutable checkpoint of the 88-file external audit.
The original 40 DOC and 48 DOCX documents and upstream notices are tracked at
`test/fixtures/external/poi-20261114`. They were obtained from Apache POI commit
`47dcff769bb395034dddfd59c4609659b6dbc6a4` with exact source hashes. They are
externally authored regression and feature samples, including website-named
documents; they are not all certified untouched production documents.

`receipt.json` identifies each archive, its SHA-256, the exact parser runtime
commits and the checkpoint counts. Each ZIP contains `CONTENTS.json`, listing
every enclosed file's path, byte length and SHA-256. Archive CRCs and all entry
hashes were checked before saving.

## Archives

- `baseline-and-oracles.zip`: original parser observations; 40 independent
  LibreOffice DOC imports and PDF renders; Apache POI observations for all 88
  documents; baseline Open XML SDK reports; and focused failing regressions.
- `integration-0537.zip`: both converted field modes for all 31 accepted DOCs;
  all 62 native PDF renders and extracted text; SDK reports; text/table/PDF
  comparisons; the 4,063-test Dart run, 197 Python tests and analysis receipts;
  exact oracle source snapshots; and the independent revision investigation.
- `visual-review.zip`: source and converted first-page images for six varied
  documents, including tables, symbols, forms, revisions and floating objects.

## Reading the results

The initial runtime converted 26/40 DOC files. Runtime `0537d1e` converts 31/40
in both field modes, with deterministic repeat output and unchanged inputs.
All 62 output packages have zero Open XML SDK errors and render in LibreOffice.
Normalized accepted main-story text agrees with LibreOffice for 30/31 sources;
every table's grid and row/cell sequences agrees for all 31 sources.

The remaining main-text disagreement, `53446.doc`, is explained by an
independent raw CHPX walk and Apache POI's run-level observations: the source
contains mixed unchanged, inserted and deleted spans with a deleted paragraph
mark. Our model retains those spans. LibreOffice labels the entire paragraph
deleted. This is retained as an oracle disagreement, not a reason to delete
source text in our parser.

Apache POI 6.0.0 reads 87/88 originals. It explicitly rejects
`deep-table-cell.docx` because nesting exceeds its supported depth of 1,000.
The report exits nonzero for this rejection; it is not counted as a pass.
The published dependency checksums and final SHA-256 pins are retained.

The source DOCX corpus already has 20 SDK errors across five packages. The
192 `crisp-docx` outputs at this checkpoint retain exactly those same error
sets, with no additions: 20 errors repeated for four operations. An invalid
source is not described as made valid by an unchanged round trip. LibreOffice's
40 DOC-to-DOCX imports also contain SDK findings; the native importer is not a
schema oracle.

Native PDF comparisons include generated numbering, notes, headers, footers,
revision display and embedded objects. At this checkpoint 56/62 renders have
the same page count and 36/62 have identical normalized PDF text. Text extraction
order can differ even when a page looks the same. These observations do not
establish pixel equality, complete layout preservation or Microsoft Word
behavior. The native reader was LibreOfficeDev 26.8.0.0.alpha0, commit
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.

Any subsequent fix or final acceptance run is recorded separately. These
archives must not be rewritten to conceal a later-discovered discrepancy.
