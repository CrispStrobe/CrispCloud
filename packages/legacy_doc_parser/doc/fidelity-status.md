# Fidelity contracts and remaining gaps

The parser preserves supported source instructions and emits editable DOCX.
Native rendering, package validity, review semantics, and source-byte retention
are checked separately. None of the following rows claims complete support for
every Word document or every renderer.

| Area | Implemented contracts | Independent checks | Remaining scope |
| --- | --- | --- | --- |
| Pagination | Paragraph keep/widow/wrapping flags; section/page breaks; unequal columns; line/page numbering; note labels and placement; source compatibility settings; table boundaries and origins | Eleven pinned DOC/native-DOCX/parser-DOCX comparisons; page text, word boxes and raster hashes; nine authored table-origin cases, including nesting and custom margins | Exact pagination across arbitrary fonts, shaping, field evaluation, wrapping, notes, tables and Office versions. Equal page counts alone are insufficient. |
| OfficeArt | Editable rectangles, ellipses, lines and bounded move/line/cubic/close paths; supported explicit paint, opacity, line and shadow properties; source evidence for unsupported geometry/effects | PDF-vector endpoints, curves, colors and widths compared with authored expectations | Arbitrary presets, adjustment formulas, complex groups/transforms, 3D, warp, and unimplemented effects. Unsupported effects are not silently replaced with a plain shape. |
| Metafiles | Bounded EMF/WMF payload validation and native image preservation; supported vector SVG previews, including compound polygons and polylines with alternate/winding fills | Real native PDF versus SVG interior-color assertions for EMF32, EMF16 and WMF; malformed record, object-table and aggregate-point tests | Complete GDI text, bitmap, clipping, brush, transform and raster-operation behavior. An unknown preview record invalidates the whole preview rather than disappearing. |
| Table styles | Table-style inheritance, all twelve conditional regions, supported cell borders/shading/margins; contextual paragraph/run properties applied before run coalescing; false/default resets | Independently assembled binary styles and PCnf/CCnf records; native style XML; source and nested-table render probes; external schema checks | Every table property and interacting conditional rule. Relative toggles may require resolved direct formatting plus an explicit native-style limitation. Properties not valid in style XML remain diagnosed. |
| Linked textboxes | Validated story chains, one owner for shared text, source margins/flow/wrap/alignment, narrowly corroborated native chain-length recovery | Resize probe verifies that markers actually move between boxes, appear once, and remain in order; placement measured separately | A native bridge fixture retains reflow but its converted boxes have a common 72-point translation. Conflicting FSPA/OfficeArt coordinate conventions remain an explicit placement failure. |
| Comments and ink | Native comment replies and resolution relationships; bounded IMsoInkData envelope extraction; immutable ISF bytes and flags retained as inert occurrence evidence | Independent comment graph and missing-parent tests; forged GUID/length, version/extent, use-bit inheritance, and no-invented-comment-link tests | Rendering/editing nonempty ink strokes, full ink/comment association, and all modern threaded-comment extensions. The ink fixture proves envelope/header handling only. |
| Lists | Supported multi-instance continuation for a shared source list without overrides; separate restarts; explicit numbering history; marker-font inheritance | Independent instance graph; continuation/restart fixtures; native marker font/bounds; positive/negative ilfo tests | Ambiguous continuation through override groups and all counter-reset interactions. A native list indentation disagreement with the binary specification is retained in the evidence, not hidden by reversing precedence. |
| Revisions | Supported inserted/deleted text and paragraph marks; run/paragraph/section formatting history; numbering NumRM history; LISTNUM display revisions; author/time and source evidence | Independent accepted/rejected text projections, previous-property checks and native section probe; malformed/hidden/private history tests | Complete move, table/object, cross-story and overlapping revision semantics, every prior-property payload, and editor-level accept/reject behavior. Reserved binary fields are not interpreted as move identities. |

## Evidence is versioned

[Checkpoint f24e5b2](evidence/f24e5b2/README.md) retains the complete compressed
native report, its source/output hashes and its initial schema failures. At
that checkpoint all eleven imports succeeded and page counts matched, but one
document matched pixels, text and geometry exactly. Every strict structural
comparison reported differences; those include representation differences and
must be inspected before classifying them as semantic loss. Later fixes do not
rewrite this earlier result into a pass.

The [table-origin golden](../test/fixtures/word_native/table-origin-golden.json)
was reviewed against nine native source cases. It measures text relative to an
independent body/outer-cell anchor and records exact native indentation. It
does not assert whole-page equivalence. The
[list-marker receipt](evidence/list-marker-font-native.json) records the font
correction and the remaining indentation discrepancy separately.

No nonempty ISF fixture was found in the inspected Quds DOCX corpus. An empty,
independently authored ISF stream tests the documented byte envelope and bounds.
It cannot establish stroke decoding or full ink-comment fidelity.

LibreOffice discards the section revision history in the dedicated native
probe. Matching that discarded native history is not accepted as correctness:
the probe separately requires the authored previous section values, authors,
dates and unique revision identities in the parser output.

## Repeatable checks

Run `dart test`, `dart analyze --fatal-infos`, and the Python tests under
`tool/fidelity`. The native corpus command accepts `--roundtrip-cycles 3` and
compares every import both with the preceding import and the first import.
It retains native-bridge changes separately from parser changes, snapshots each
completed stage before later work, and records code/compiler/executable hashes.

`--require-exact` fails on remaining rendering or structural differences. The
ordinary measurement command can succeed while reporting those differences;
its successful exit means the measurements completed, not universal fidelity.
No command automatically updates a reviewed golden.

See [the oracle guide](fidelity-oracles.md), [layout contracts](layout-fidelity.md),
[table/list contracts](table-and-list-fidelity.md), [drawing/metafile contracts](media-fidelity.md),
and [revision/comment contracts](revisions-comments.md) for the precise source
format definitions, current tests and remaining limits.
