# Audited JSDoc feature coverage

The comparison is pinned to [Alpaq92/JSDoc commit
821695a884e0c0bb8592a635d9524bb3e116cd67](https://github.com/Alpaq92/JSDoc/tree/821695a884e0c0bb8592a635d9524bb3e116cd67),
including its actual [`src/docToText.js`](https://github.com/Alpaq92/JSDoc/blob/821695a884e0c0bb8592a635d9524bb3e116cd67/src/docToText.js)
implementation. This is coverage of the inspected reader's feature families,
not a claim that either implementation supports every Microsoft Word feature.

| Inspected feature family | Standalone Dart package |
| --- | --- |
| CLX body text and auxiliary document parts | Bounded global CP-to-FC mapping with validated references for individual headers, notes, comments and textboxes |
| CHPX/PAPX and paragraph/character styles | Resolved style/direct/PRM cascade, including terminal-mark paragraph properties, style-relative toggles and ordered character-style resets |
| Font, size, color, highlight, bold/italic, caps, hidden text, strike, vertical position and spacing | Typed run properties, escaped HTML and editable DOCX properties |
| Underline variants | Every defined MS-DOC `Kul` value has its exact typed name and DOCX value; HTML decoration differences are marked |
| Alignment, indentation, paragraph/line spacing, keep and page-before flags | Resolved paragraph model and DOCX properties |
| Custom tabs | Inherited stops, deletion ranges, alignment/leaders, extended operands and document default interval; HTML tab layout remains an approximation |
| Paragraph borders and shading | Separate sides, widths/colors/flags and foreground/background/pattern values; explicit resets preserved |
| Table rows/cells, column widths, cell shading and merges | Structured cells with multi-paragraph content, exact horizontal/vertical merge flags and legacy/modern shading arrays |
| Sections, page size/margins, orientation and columns | Source section boundaries and supported layout properties, with break direction translated for DOCX section semantics |
| List definitions, level styles and overrides | Referenced LSTF/LVL/LFO data, per-level formats, starts, restarts and overrides; common HTML labels and editable DOCX numbering |
| Fields and hyperlinks | Original nested instructions, stored results and ranges; supported DOCX fields are locked, external-update fields remain inert |
| Footnote/endnote/comment/textbox anchors | Validated reference-to-story associations; typed parts and anchors in DOCX, subject to documented privacy and layout limits |
| Pictures | Referenced PICF/OfficeArt occurrences with dimensions/crop/presentation state and original bytes; no guess based on physical image order |

The package also retains bookmark ranges, supported insertion/deletion metadata,
embedded-object records, VBA storage and signature evidence described in
[media-preservation.md](media-preservation.md). These additions do not imply
execution, verification of signatures, or lossless Word pagination.

## Deliberate differences and remaining boundaries

The Dart API exposes immutable typed structures. Main-story `plainText` and
`safeHtml` preserve CrispCloud's existing main-only contract; callers inspect
individual formatted auxiliary `stories` explicitly. It is not an API-compatible
JavaScript port, and the package writes new DOCX/DOCM packages rather than
rewriting binary DOC files.

Tracked deletions and insertions remain explicitly represented. A preview does
not silently accept tracked changes. Hidden text, private field results and
their media/reference anchors are excluded from visible previews and active
conversion content. Original instructions and private cached data remain
available only in their explicitly identified metadata/evidence collections.

The inspected JSDoc reader can carve image signatures and pair recovered images
by order. This parser instead requires actual picture/shape references; an
unreferenced byte sequence never becomes an invented picture occurrence.
Malformed references fail with `FormatException` within documented resource
limits. This deliberate restriction means permissive recovery results from a
damaged source may differ.

There are also source-correct differences from that pinned implementation:
`Kul` 0x14 means heavy dotted underline; shading's background, foreground and
pattern remain distinct; table merge flags follow the defined enumerations;
and tab deletions plus the extended-length operand are applied. Such cases are
covered by binary fixtures rather than matching an upstream display error.

The HTML renderer does not activate hyperlink URLs. Word fields preserve their
instruction semantics and stored results without fetching URLs or recalculating
them during parsing/conversion. Its HTML list labels, tabs, complex border
styles, patterned shading and underline details have documented approximations
in [html-preview.md](html-preview.md).

Conditional table styles, exact line/page layout, linked-textbox reflow,
threaded-comment/ink rendering, arbitrary formatting-revision history and
signature validity after conversion remain outside the supported fidelity
claim. See [stories-fields-lists.md](stories-fields-lists.md) and
[conversion.md](conversion.md) for the precise model and output boundaries.
