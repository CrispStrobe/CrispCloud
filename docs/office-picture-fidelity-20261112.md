# Picture insertion and drawing history

Word and slide picture insertion previously used fixed dimensions, stretching
portrait, square and wide images. Slide transforms and visual dimensions also
disagreed. An asynchronous picker could insert into a different document or
selection, and the host drawing command used the currently selected slide when
undoing an insertion instead of the slide that owned the shape.

## Resulting behavior

PNG, JPEG and GIF inputs are decoded on a worker before insertion. The original
bytes and content type are retained. The initial size uses 96 dpi and preserves
the decoded aspect ratio, reduced to fit the available Word column or slide
and a 360 by 240 point insertion box. A one-point minimum matches the writers;
an impossible thin-image box is rejected instead of stretching the picture.
The byte and decoded-pixel budgets bound accepted input. Invalid, unsupported,
missing or oversized data leaves the document and command history unchanged.

Picker results are bound to their original controller and editing target.
Changing the document, content, selection, interaction mode, active slide or
mounted widget while a picker is pending cannot redirect the insertion.
`OfficeEditorRibbonState.perform` returns an awaitable future for picture
actions, making actual asynchronous completion observable in regressions.

Host-added shapes keep their original owning slide through undo and redo. This
protects pictures and the existing rectangle/drawing insertion commands when
the user switches slides before using history.

## Executable and independent evidence

`test/widget/office_picture_fidelity_test.dart` uses deterministic file-picker
results and the real host action bridge. Twenty tests cover proportional
landscape/portrait/square sizing, PNG/JPEG/GIF byte and MIME preservation,
column and small-slide limits, undo/redo, cancellation and failed or stale
picker results. A drawing-history case checks both slides' exported XML after
insertion, slide switching, undo and redo.

Six Word and four slide scenarios produce three saves/reopens each. The 18 DOCX
and 12 PPTX paths are mandatory in `tool/office_host_evidence.json`. Independent
ZIP/XML readers verify actual extents, transforms, owning relationships and
original media bytes. A deliberate fixed-height corruption is rejected by an
extent assertion, and normal expectations are never refreshed from output.

The inventory now supports DOCX, XLSX and PPTX, follows the actual OPC main-part
relationship and checks format-specific content type and XML root. A Word file
renamed to PPTX cannot satisfy a slide artifact. Controls cover relocated parts,
duplicate ZIP members, wrong content types, missing/external/escaping targets,
malformed XML and missing required exports. General OOXML schema validation
remains the separate Open XML SDK gate.

The focused 20-test picture run passes under Flutter 3.47.8. The host gate also
includes the 17 font regressions and all earlier paragraph, note, TOC, table,
reference and actual-save scenarios. External rendering and schema receipts are
recorded separately from these semantic test results.

## Remaining host UI boundaries

The scripting API provides image wrapping and positioned text frames. The host
ribbon still needs dedicated Word image wrap/anchor/crop/rotation controls,
Word drawing creation, custom paragraph/character/table-style authoring and
bookmark/citation/cross-reference authoring. Native note-menu actions remain
separate from the tested Flutter ribbon commands. These are explicit UI gaps;
the implemented insertion and preservation regressions do not claim that those
controls now exist.
