# Native shared header textbox recovery

This checkpoint fixes the two retained header paragraph/table controls that
previously failed with `Invalid Word drawing-to-textbox reference`. Each has
one singleton source textbox range referenced by independent normal and first
header shapes. Both now retain the text and table in both editable header parts.

The same-binary before/after evidence uses a baseline converter compiled from
`2d8607b` and a corrected converter whose complete runtime source hashes and
patch are in `report.json`. Renderer, compiler, font and executable identities
are recorded. No reviewed golden was changed.

Both repaired controls keep source text, page count, and story-relative table
geometry. Their existing +0.35 pt absolute textbox displacement remains; RGB
and strict absolute placement comparisons therefore still differ. The first
header instance is inactive in the native one-page controls and is checked in
the editable package rather than claimed as a separately displayed page.

An additional literal-source three-page control explicitly selects the same
OOXML header for first/even/default pages. The native bridge wrote three
independent FTXBXS stories for that control, so it already imported correctly.
Its corrected DOCX is byte-identical to baseline. The initial probe's assumption
that this case would also fail was disproved; the original assertion log is
retained, and the script now treats it as an unchanged valid control. All three
page variants retain their text and relative geometry, with the same existing
absolute displacement.

Portable verification passes 57 focused tests, including all six header/footer
slots, reversed primary occurrence order, field events in every shared part,
and rejected malformed owner/count/link cases. Scoped analysis is clean.

`artifacts.tar.xz` retains the exact authored DOCX, native DOC, available baseline
DOCX, corrected DOCX, before failures, PDF/text/bounding boxes, verified gzip RGB
rasters, raw binary stream observations, authoring/measurement scripts, source
receipts and verification logs. `manifest.json` pins the archive and every
retained file, verified after packing. Inputs are separately retained for
portable regression under `test/fixtures/word_native/`; their provenance file
lists exact hashes and authoring sources. See
[the contract](../../shared-header-textboxes.md) for the strict recovery bounds.
