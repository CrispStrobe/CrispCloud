# HTML preview contract

`renderLegacyWordHtml(blocks, numberingDefinitions: ..., defaultTabStopTwips: ...)`
produces bounded HTML with fixed elements and CSS property names. Document text,
list labels and font names are escaped; the output contains no script, external
resource reference or original document markup. The parser supplies the
numbering definitions and default tab interval for both the main preview and
each referenced auxiliary story.

## Formatting represented

- Resolved character formatting, headings, paragraph alignment/indents/spacing,
  explicit breaks and table structure, including bounded horizontal/vertical
  cell merging. Continuation text is retained.
- Single, double, dotted, dashed and wavy underlines use fixed CSS styles.
  A separate nested decoration preserves a different strike/double-strike style
  on the same run.
- Generated decimal, two-digit decimal, upper/lower Roman, upper/lower Latin
  letter and literal bullet labels. Supported levels use their starting values,
  nested restart rules, legal-decimal placeholders, label character style and
  stored suffix. Letter numbering follows Word's repeated-letter sequence:
  `Z, AA, BB`; it does not use spreadsheet column numbering.
- Basic paragraph border lines, color, width and spacing. Adjacent paragraphs
  in the same block or cell can share an outer border and use a between border
  when their exposed border definitions and indents match.
- Paragraph and table-cell shading. `clear` uses the background color;
  `solid` uses the foreground color. The start cell supplies the background of
  a merged HTML cell.
- The DOP default tab interval and uniformly spaced left-aligned custom stops
  without leaders, using CSS `tab-size`. Original tab characters remain in the
  content.

List labels are generated for preview only. They do not rewrite source runs or
the parser's `plainText`. Counters follow original global CP order before table
merging changes HTML markup order. Hidden runs and hidden markers are omitted;
paragraphs with no visible text do not expose generated labels. Inserted and
deleted runs remain visibly marked. Private cached field results and field
instructions continue to be suppressed by the parser.

## Explicit approximations

HTML is not a Word pagination or glyph-measurement engine. Font availability,
line wrapping and page geometry can differ. The following generated attributes
identify narrower limitations without substituting a different numbering scheme:

| Attribute | Meaning |
| --- | --- |
| `data-word-numbering="unsupported"` | The definition/format or a placeholder cannot be represented by the supported label subset; its label is omitted. This includes Roman values outside 1–3999 and very long repeated-letter values. |
| `data-word-numbering="instance-approximation"` | Distinct list instances share a source list identity whose continuation cannot be established from the exposed model. Counters are displayed independently per instance. |
| `data-word-border="approximate"` | Between-border grouping, advanced line styles, shadows or frame effects are not fully represented. The ignored MS-DOC paragraph bar border is never activated. |
| `data-word-shading="approximate"` | A percentage pattern is shown as an averaged color, or another pattern uses only its explicit background. Hatching and pattern geometry are not reconstructed. |
| `data-word-tabs="uniform-approximation"` | Uniform custom left tab stops use one repeated CSS interval; later default stops and Word's measured text fitting may differ. |
| `data-word-tabs="approximate"` | Irregular, center/right/decimal/bar/list tab stops or leaders remain typed metadata. The preview retains tabs and the default CSS interval without inventing precise placement. |
| `data-word-underline="approximate"` | Words-only, heavy, long-dash, dot-dash or double-wave underlining uses its closest fixed CSS line style. Words-only underlining does not reproduce Word's exact whitespace skipping. |

Border grouping in Word also depends on properties such as table depth and
`sprmPIpgp` that this preview does not fully expose. Shadows and frame flags do
not create additional CSS effects. Missing/automatic colors retain the browser's
normal color behavior.

The preview remains text/table HTML. Referenced images, OLE, VBA and signatures
are available through the [media catalog](media-preservation.md) and the separate
DOCX/DOCM conversion surface. They are not inserted as data URIs or active
objects into preview HTML. This also matches the distinction in the reviewed
[JSDoc HTML API](https://github.com/Alpaq92/JSDoc/blob/821695a884e0c0bb8592a635d9524bb3e116cd67/src/docToText.js):
its styled HTML contains text spans; its separate `images()`/`model()` APIs
supply carved image assets. This package follows recorded image references
instead of adopting that carving order.

## Bounds and tests

The renderer caps generated HTML at 24 MiB of UTF-8 and structural work at
200,000 items. Numbering definitions are bounded to 4,096 instances and nine
levels each. Expanded labels are capped at 4,096 UTF-16 code units per label and
4 Mi code units in total before HTML allocation. Custom tabs remain bounded to
64 ordered stops. Malformed public models fail with `FormatException`.

`legacy_word_preview_parity_test.dart` exercises number formats, nested restarts,
legal placeholders, numbering through merged cells, hidden labels, escaped
bullets, border grouping, shading roles, tab approximations and hostile model
limits. The existing renderer tests continue to cover revision visibility,
Unicode escaping, table continuation text and the final output budget.

Number-format identifiers follow
[MS-OSHARED MSONFC](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-oshared/57c8f7d4-1426-44e0-b58d-6fa1a5a81659)
and the ISO/IEC 29500-1 `ST_NumberFormat` definition. Restart behavior follows Microsoft's
[lvlRestart implementation notes](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/140a2cd9-2f26-456d-9760-ae6ecef4e8b5).
