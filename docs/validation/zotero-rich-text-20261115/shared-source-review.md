# Implementation and independent review

## Data-loss fixes

1. A multi-run Zotero `w:fldSimple` previously lost its instruction during import.
   It now becomes a complete complex-field packet, retaining metadata, styled
   results, lock/dirty flags and unknown container attributes. Ordinary one-run
   fields still use the existing atomic representation. Nested fields and
   opaque container attributes stay protected from replacement.
2. Searching for `PAGE` anywhere in an instruction misclassified Zotero JSON
   containing the locator label `page`. Paragraph-global numeric suppression
   could then discard citation text, including a citation following a real
   page-number field. Classification now uses the command. Cached numbers are
   suppressed only after settlement proves a complete native PAGE paragraph.
   A PAGE result with an unresolved revision retains its full cache and offsets.
3. Editing an unchanged citation previously flattened styled result runs and
   rewrote `formattedCitation`. Managed metadata-only updates now retain both.
   The composer uses the visible cache when imported plain metadata is stale.

Regression fixtures cover three successive DOCX saves, direct and isolated
serialization, numeric/superscript caches, real PAGE fields, split instructions,
locks, nested fields, malformed JSON, opaque attributes and tracked offsets.

## Rich bibliography contract

`ZoteroFormattedText` converts a bounded XHTML fragment into immutable inert
spans. It supports bold, italic, underline, strike-through, subscript and
superscript. Character entities, Unicode and no-break spaces retain their text;
CDATA/comment handling does not reinterpret literal markup. Numeric CSL labels
remain beside their entry text. External links are text and no resources load.

Malformed XML, invalid entities/characters, DTDs and processing instructions
refuse the result. The parser bounds input to 8 MiB UTF-8, nesting to 64,
elements to 50,000, attributes per element to 64 and output spans to 10,000.
Independent review checked the scanner's handling of malformed comment input,
numeric margin classes, unsupported styling and omitted embedded content.

The model requires exact agreement between formatted and visible text before
mutation. Rich replacement supports paragraph-owned fields, a sole bibliography
run and a saved/reopened complex field occupying the complete paragraph by
token identity. Outside bookmarks/wrappers and genuinely inline bibliographies
refuse rich conversion. Existing stale/lock/nesting/opaque/revision guards apply.

The review UI defaults to keeping supported formatting and offers an explicit
plain-text edit choice. Cancellation and stale-target cases retain the document
and history. Both 320 × 640 layout and DOCX round-trip behavior are exercised.

## Limits retained deliberately

Small caps and paragraph layout, including hanging indents, margin columns and
spacing, remain simplified and are identified in the review. Inline CSS support
is deliberately partial. New inline citations still use the existing atomic
plain-result workflow. The ordinary editing/copying model does not yet provide
full atomic behavior for mixed complex inline fields, so new mixed-format inline
citation generation was not added.

This is not a document-wide CSL processor: numbering, disambiguation and ibid
are not recomputed across a document. The native Zotero picker/HTTP citing
transaction adapter and active ODT transfer remain absent. No native Word/Zotero
refresh acceptance or complete native app build is claimed.

Protocol references reviewed:

- [Zotero Web API bibliography XHTML](https://www.zotero.org/support/dev/web_api/v3/basics)
- [Zotero rich-text bibliography conventions](https://www.zotero.org/support/kb/rich_text_bibliography)
- [CSL display and formatting conventions](https://docs.citationstyles.org/en/stable/specification.html)
