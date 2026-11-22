# Changelog

All notable changes to `quds_office_engine` are documented here.

## Unreleased

- Accept separately named visited/unvisited ODT hyperlink styles when resolved
  supported formatting and inheritance state match across all script slots.
  Preserve nullable fallback and explicit-property distinctions so child spans
  cannot reveal a hidden difference. Keep actual visited-state differences,
  missing styles and unsupported formatting guarded. Add 20 focused regression
  cases for multilingual links, adjacent active Zotero fields, DOCX persistence
  and refusal boundaries. This increment is source-reviewed; executable
  qualification remains pending after workspace exhaustion. See the
  [continuation record](../../docs/validation/zotero-link-equivalence-20261122/README.md).

- Add bounded VBA `StrReverse` for source-known text in Word, Excel and
  PowerPoint. Reverse UTF-16 code units with once-only argument evaluation,
  explicit Empty/Null handling, strict String payloads and preallocation work
  accounting. Existing native text guards reject malformed UTF-16 at publication.
  Regression tests are authored; this increment's execution status and exact
  compatibility boundary are recorded in
  [the source-text record](../../docs/validation/word-vba-source-text-20261122/README.md).

- Preserve supported visible table borders in native Zotero ODT import and
  explicit editable export: one solid RGB stroke per table, exact eighth-point
  widths from 0.25 to 12 pt, and independent cell sides. Resolve inherited
  shorthands, explicit off edges, merged ownership and nested tables without
  changing uniform padding. Retain active citations through native Refresh and
  repeated DOCX/ODT saves. The bounded ODT reader guards mixed strokes, visible
  separating borders and conflicting covered-cell overrides; editable output
  checks the native modeled stroke and refuses right-to-left table column order
  without changing the source or active fields. Supported right-to-left
  paragraphs inside left-to-right tables remain distinct. Three cases pass six
  actual LibreOffice saves and twelve paired native DOCX/ODT cycles with all 376
  captured engine inputs unchanged. See the
  [border interoperability record](../../docs/validation/zotero-table-borders-20261122/README.md).

- Preserve Word cell borders stored as logical `start`/`end`, giving those names
  precedence over legacy `left`/`right` independently of XML order. Resolve
  effective table direction from default/named styles and direct overrides
  before mapping to physical sides, and apply the inverse mapping on DOCX save.
  Keep absent edges distinct from explicit off (`nil`/`none`); guard namespace and
  direct-child ownership. The retained Writer DOCX cell now independently
  retains all four source borders. Arbitrary external DOCX per-cell strokes and
  styles remain outside this native common-stroke qualification.

- Preserve complete run-property XML, including opaque formatting revisions,
  on native Word field boundaries through repeated DOCX saves. Keep those
  fields guarded instead of discarding their history or creating empty text
  revisions. Ordinary text retains its existing formatting review behavior,
  including text that originally shared a run with a field marker.

- Keep bounded LibreOffice-formatted Zotero DOCX fields editable while
  preserving their raw instruction/boundary formatting and empty code runs.
  Refresh or unlink empty results using cached-result or surrounding text
  formatting; instruction-only run formatting remains inert.
  Retain structural, ownership, lock and unknown-metadata guards. Reopen the
  observed unnumbered Writer ODT outline forms and clear character shading
  with an explicit background. Original converter files exercise citation
  refresh, metadata, body/note/cell ownership and repeated native saves;
  editor tests cover detached apply, selected-field context, undo/redo and
  stale-result refusal. See the
  [converter qualification](../../docs/validation/zotero-converter-parity-20261122/README.md)
  for exact limits and remaining installed-plugin acceptance.

- Add bounded VBA `Split` assignment to local dynamic String arrays in Word,
  Excel and PowerPoint. Preserve zero-based binary substring semantics,
  delimiter/limit controls, empty arrays, once-only argument evaluation, frame
  ownership, enumeration locks and metered array/String/work limits. Include a
  delimited Word table report and compiler, document, CLI/MCP and portable
  regression coverage. General array values and live document reads remain
  outside this increment. See the
  [contract](../../docs/vba-macros-details.md#splitting-source-string-arrays)
  and [qualification](../../docs/validation/word-vba-split-20261122/README.md).

- Add ordinary VBA `Left`, `Right` and expression `Mid` across Word, Excel
  and PowerPoint, with Variant String/Empty/Null behavior, bounded UTF-16
  slicing and unchanged strict `$` forms. Extend Word `Paragraphs`, `Sections`,
  `Headers`, `Footers` and their `Item` methods with required named `Index`;
  add typed `Sections`/`Paragraphs` aliases and required `ByVal` helpers.
  Preserve evaluation order, selector identity, inactive-source object/cell
  guards, native rollback and opaque DOCM parts. Include a complete five-step
  reference-label BAS, 64 independent conformance cases and native/CLI/MCP
  and VM/JavaScript checks. See the
  [contracts](../../docs/vba-word-macros-details.md#named-document-and-story-selectors)
  and [qualification](../../docs/validation/word-vba-text-selectors-20261122/README.md).

- Import Zotero research-note blockquotes as distinct native paragraphs, with
  up to eight quote levels and 18 pt of additional left indentation per level.
  Preserve supported headings, lists, links, pictures and active citations;
  retain quote ownership through merged table cells and DOCX saves. Keep
  surrounding paragraph formatting separate and refuse unsupported nesting
  before applying any document changes. See the
  [quote contract](../../docs/zotero-support-details.md#block-quotations-in-research-notes)
  and [qualification](../../docs/validation/zotero-workflow-parity-20261122/README.md).

- Add typed Word VBA `Rows`, `Row`, `Columns`, `Column` and `Cells` selectors,
  including explicit `Item`, nested `With`, retained aliases and required
  `ByVal` helpers. Support required named `Index` arguments on table
  collections and named `Row`/`Column` on `Table.Cell`, with once-only source
  evaluation order. Lower selected cells to the existing guarded native
  operations and preserve direct-cell/paragraph origin restrictions, strict
  index validation and atomic rollback. Include a 10-operation table BAS,
  an independent 32-case conformance corpus and native/CLI/MCP/portable tests.
  See the [contract](../../docs/vba-word-macros-details.md#table-row-and-column-navigation)
  and [local qualification](../../docs/validation/word-vba-table-navigation-20261122/README.md).

- Add shared VBA integer division (`\`) and signed remainder (`Mod`), with
  ties-to-even Long operands, VBA precedence, strict Empty/Null/conversion
  rules, positioned errors and existing compilation budgets. Include a
  complete grouped Word table report, a 54-case conformance corpus and
  document/CLI/MCP/portable regression coverage. The
  [contract](../../docs/vba-macros-details.md#integer-division-and-remainder)
  records exact bounds and the signed-Mod specification discrepancy;
  [local qualification](../../docs/validation/word-vba-integer-arithmetic-20261122/README.md)
  is separate from installed Office compatibility.

- Append to current Word table-cell text through direct VBA
  `Cell.Range.InsertAfter`, including named `Text:=`, typed aliases, nested
  `With` and `ByVal` helpers. Preserve original runs, sparse and zero-width
  metadata, table ownership and opaque DOCM parts; inherit the current text's
  end formatting and retain whole-run validation, rollback, policy and
  recording boundaries. Keep paragraph Range projections and structural text
  insertion refused. Include a complete BAS, independent conformance corpus,
  native preservation and CLI/MCP checks, with portable VM/JavaScript drivers.
  See the [append contract](../../docs/vba-word-macros-details.md#appending-existing-cell-text)
  and [qualification](../../docs/validation/word-vba-cell-suffix-20261122/README.md).

- Preserve continuous automatic decimal and lower/upper Roman footnote/endnote
  numbering in editable Zotero ODT export/import, including Word's default
  Roman endnotes. Verify exact native settings and every ordinal in a cited
  note class, count uncited notes, retain independent class formats, and persist
  them through DOCX reopening. Keep custom/mixed/restarted/ambiguous numbering
  guarded and ordinary ODT export unchanged. Expose read-only automatic-note
  metadata separately from cached labels. Malformed native XML retains cached
  label fallback and causes controlled editable-export refusal, including the
  native parser's mismatched-tag and unterminated-tag exceptions. See the
  [numbering qualification](../../docs/validation/zotero-note-numbering-20261122/README.md).

- Prefix existing Word table-cell text through VBA `Cell.Range.InsertBefore`
  and its selected paragraph Range, with required named `Text:=` also available
  on supported body/header/footer paragraphs. Preserve original characters,
  run boundaries, kerning and empty-run metadata with a dedicated guarded native
  operation; retain table/protection/policy and whole-run rollback limits.
  Add the eight fixed VBA String constants to all source adapters, including
  Const/default expressions, without relaxing native text controls. Include a
  complete table BAS, independent corpus and native/CLI/MCP/portable checks.
  See the [prefix contract](../../docs/vba-word-macros-details.md#prefixing-existing-cell-text)
  and [qualification](../../docs/validation/word-vba-cell-prefix-20261122/README.md).

- Permit bounded native Zotero recovery for damaged citation metadata and
  bibliography JSON with complete, exclusively owned field results. Preserve
  original payloads, accept temporary repair state only in detached operations,
  and require valid final metadata or explicit unlink/delete before publication.
  Revalidate actual body/table/note ownership, guard shared or incomplete
  packets, and preserve rich ordinary text when repaired fields are unlinked.
  See the [recovery qualification](../../docs/validation/zotero-field-recovery-20261122/README.md).

- Add bounded Word VBA `Cell.Range.Paragraphs(1)` and `.Paragraphs.Item(1)`
  selection for the existing ordinary cell paragraph. Preserve cell identity
  through Paragraph/Range/Shading aliases, nested `With` and named `ByVal`
  helpers. Apply existing paragraph styles by primary name or supported
  built-in constant, and solid RGB/palette/automatic paragraph backgrounds,
  including on empty paragraphs. Reuse guarded native style/shading operations,
  sparse XML ownership, detached mutation and whole-run rollback. Reject known
  cell-paragraph insertion/list operations even in inactive source, while
  generic helpers retain actual-selector validation. Include a complete table
  template BAS, independent conformance fixtures, native DOCX/DOCM and CLI/MCP
  checks, and VM/JavaScript agreement. See the
  [contract](../../docs/vba-word-macros-details.md#formatting-a-cell-paragraph)
  and [local qualification](../../docs/validation/word-vba-cell-paragraphs-20261122/README.md).

- Extend bounded Word VBA with direct `Cell.Range.HighlightColorIndex`,
  `NoProofing`, `LanguageID` and `LanguageIDOther` writes. Preserve table/cell
  identity through aliases and helpers, reuse guarded detached run formatting,
  and retain current-text-only, structural, protection and atomic-publication
  boundaries. Add shared `Join` for allocated local String arrays, with
  explicit delimiters, arbitrary lower bounds, fixed/dynamic array lifecycle,
  strict conversion rules and metered UTF-16 output. Include complete table
  report examples, versioned Join expectations, VM/JavaScript conformance and
  native DOCX/DOCM, CLI/MCP, recording and rollback tests. See the
  [cell text contract](../../docs/vba-word-macros-details.md#cell-highlighting-and-proofing-controls),
  [Join contract](../../docs/vba-macros-details.md#joining-source-string-arrays)
  and [local qualification](../../docs/validation/word-vba-cell-text-20261122/README.md).

- Expose typed, read-only context for native Zotero `Field.select` requests.
  Resolve original body, note and multipart bibliography ranges against the
  unchanged live document without moving the writing caret or applying staged
  results. Distinguish new insertions and detached transfer fields without
  exposing them as live source ranges, and clear context on deletion, unlinking
  and transaction completion.

- Format supported Word table cells through bounded VBA `Cell.Range.Font` and
  `Cell.Range.ParagraphFormat`, including existing font controls, paragraph
  spacing/alignment, custom line-spacing pairs, spacing methods and tab stops.
  Retain cell coordinates through aliases and named `ByVal` helpers, and use
  explicit guarded native cell selectors. Preserve the existing table text,
  structural and transaction contracts; Font writes require nonempty ordinary
  text and exclude paragraph/cell marks, while paragraph formatting accepts an
  empty ordinary paragraph. Format detached run copies to keep shared mutable
  public-model properties from changing unrelated content. Add a reusable 2×2
  table BAS and compiler/native/CLI/MCP/portable-runtime regression coverage;
  see the [contract](../../docs/vba-word-macros-details.md#formatting-existing-table-cells)
  and [local record](../../docs/validation/word-vba-cell-formatting-20261122/README.md).

- Add session-owned writing-position capture and resolution for native Zotero
  transactions. Track endpoints through citation replacement/deletion,
  bibliography reflow and note conversion without changing document content.
  Preserve offsets during metadata-only or identical-text updates, and accept
  the HTTP protocol's optional field-type argument to `canInsertField`.

- Retain document-wide footnote separator geometry through bounded native
  DOCX and editable ODT persistence, note pagination and Zotero transfer.
  Preserve supported gaps, thickness, relative width, physical alignment,
  color and hidden rules, including nondefault special-note IDs and settings
  references. Qualify combined VBA foreground writes and late-failure rollback
  without changing active notes or separators; see the
  [integrated record](../../docs/validation/word-vba-comparison-colors-20261121/README.md).

- Add shared binary `StrComp` to Word, Excel and PowerPoint VBA macros, with
  exact comparison results, explicit Empty/Null handling, strict argument
  contracts and metered UTF-16 work. Word additionally supports the complete
  fixed `Font.ColorIndex` palette and automatic foreground through `wdAuto`
  or `Font.Color = wdColorAutomatic`. Preserve native automatic identity,
  sparse theme overrides, foreign metadata and transaction rollback. Include
  a runnable report/template BAS, versioned source cases, CLI/MCP coverage,
  native save/reopen regressions and matching VM/JavaScript checks. See the
  [comparison](../../docs/vba-macros-details.md#binary-string-comparison) and
  [foreground](../../docs/vba-word-macros-details.md#font-palette-and-automatic-foreground)
  contracts.

- Fill existing Word table templates from the bounded VBA dialect using typed
  `Tables`, `Table`, `Cell` and cell-range aliases, `With` and `ByVal` helpers.
  `Cell.Range.Text` emits guarded `docx.tableCellRangeText` operations for plain
  single-paragraph cells in unmerged rectangular main-story tables. Preserve
  structure and formatting, refuse ambiguous native ownership and unsupported
  rich content, and retain the atomic CLI/MCP/recording transaction boundary.
  Add a runnable table-report BAS and portable source/native conformance checks.
  Retain explicit empty ordinary text runs during DOCX import so clearing,
  saving, reopening and refilling a cell preserves insertion formatting;
  structural markers do not acquire additional empty runs.

- Honor each table's uniform cell margin in native measurement, wrapping,
  pagination and note/nested-table layout instead of a fixed inset. Preserve
  accumulated ancestor margins when fitting pictures and splitting tall rows.
  Editable Zotero ODT exports explicit padding; native import resolves bounded
  style inheritance and retains uniform padding through DOCX saves. Admit
  LibreOffice's explicit borderless declarations, while rejecting asymmetric,
  conflicting or unrepresentable padding and visible unsupported borders.
  Check serialized content widths with exact decimal arithmetic, including
  merged spans and margins that exhaust a cell only after rounding. Render
  uniquely defined, body-referenced image-only endnotes without promoting
  orphan, duplicate or frame-only note references.

- Refuse editable Zotero ODT export when effective native text, paragraph-mark
  or note-marker formatting raises or lowers the baseline by an absolute
  amount. Check inherited positions before writing, preserve explicit zero
  overrides and keep supported superscript/subscript independent.

- Add shared bounded VBA `Abs`, `Int`, `Fix` and `Sgn` expressions to Word,
  Excel and PowerPoint macros. Preserve negative floor/truncation differences,
  numeric Variant and Empty/Null behavior, explicit coercion requirements and
  finite portable bounds. Include a runnable Word report, versioned numeric
  corpus and native/CLI/MCP transaction and VM/JavaScript coverage. See the
  [numeric contract](../../docs/vba-macros-details.md#numeric-intrinsics).

- Add bounded Word VBA `Font.Position` assignments through typed aliases,
  helpers and independent header/footer selectors. Native run formatting,
  DOCX inheritance and sparse serialization retain signed half-point positions
  and explicit zero overrides. Headless/PDF layout moves the baseline without
  resizing text, including incremental and note-copy paths; logical text,
  comparison and stale-operation identity remain intact. Include an executable
  BAS example, versioned source corpus, native/layout and CLI/MCP tests. See the
  [position contract](../../docs/vba-word-macros-details.md#baseline-position-without-resizing-text).

- Preserve semantic uppercase text when importing native Zotero ODT files.
  Resolve inherited uppercase and explicit normal-case overrides without
  changing authored Unicode, citation caches, JSON or UTF-16 endpoints. Retain
  mixed-script formatting and inline images through repeated ODT/DOCX saves.
  Reject unsupported transforms and ambiguous uppercase/small-cap combinations.
  Preserve authored picture-title distinctions in continuous header comparison
  and character styles on inline annotation pictures. See the
  [combined qualification](../../docs/validation/zotero-roundtrip-complete-20261121/README.md).

- Reopen supported native Zotero bibliographies saved by LibreOffice, including
  inherited inert section styles and rich/empty entries. Validate unused
  sequence declarations and retain protection/layout refusals. Qualify the
  identified LibreOffice decimal zero-offset note convention against exact
  visible ordinals. Preserve absolute editable-ODT table widths with physical
  left/center/right alignment and admit inert border-model defaults only within
  the bounded borderless reader. Preserve complete uniform DOCX table margins,
  including zero, through direct properties and bounded style inheritance while
  retaining unsupported source XML. Recompute optional soft-page hints and
  declare exact native note marker styles and the final endnote page master;
  validate their effective formatting and compatible geometry on reopening.
  Retain actual converter fixtures and controlled
  native refresh/edit/unlink regressions. See the
  [round-trip record](../../docs/validation/zotero-odt-roundtrip-20261121/README.md)
  for executed scope and remaining active-footnote/installed-plugin acceptance.

- Preserve bounded embedded inline PNG/JPEG pictures through native editable
  Zotero ODT import/export and further DOCX saves, including raster bytes,
  accessible titles/descriptions, links and adjacent citation ownership.
  Emit one frame per picture with unique drawing names, preserve image-run
  styling, and keep identical headers continuous after name allocation.
  Retain guarded graphic styles, raster budgets and atomic refusals for
  unsupported pictures. See the
  [qualified image work](../../docs/validation/zotero-odt-images-20261121/README.md).

- Extend Word VBA with typed `Shading` bindings on selected Paragraph/Range
  objects, RGB/automatic and fixed-palette background assignments, and all 60
  named `WdColor` constants. Add guarded native `docx.paragraphShading` with
  sparse background ownership, explicit automatic overrides, metadata
  preservation and atomic refusal of unsupported source shading. Include
  compiler, native, transaction, CLI/MCP and VM/JavaScript example coverage.
  See the [shading contract](../../docs/vba-word-macros-details.md#paragraph-background-shading).

- Add shared bounded `Space`/`Space$`, `String`/`String$`, `ChrW`/`ChrW$`, and
  `AscW` to the Word, Excel and PowerPoint source dialects. Keep exact numeric
  arguments, UTF-16 code-unit semantics, strict actual String inputs, shared
  work/output limits and existing native-publication character guards. Numeric
  code-page String operands remain unsupported. Include a runnable Word BAS
  module and source/transaction/portable tests. See the
  [construction contract](../../docs/vba-macros-details.md#text-construction-and-unicode-code-units).

- Extend bounded Word VBA with `Paragraph.Style` and selected `Range.Style`
  assignments by primary name or 13 built-in constants. Add guarded native
  `docx.paragraphStyle` with targeted inheritance refresh, preserved direct
  formatting and sparse source metadata, explicit same-value references and
  atomic refusal of ambiguous styles or changed numbering. Include a runnable
  BAS example and source, native, CLI/MCP, rollback and VM/JavaScript coverage.
  See the [style contract](../../docs/vba-word-macros-details.md#existing-paragraph-styles).

- Add explicit `OdtDocumentWriter.writeEditableZoteroBytes` copy export with
  native citation ReferenceMarks, complete bibliography TextSections and
  Unicode-safe ReferenceMark preferences. Preserve supported body, table-cell
  and decimal-note ownership, rich caches and unknown metadata; refuse active
  fields that would be lost. Keep ordinary cached ODT export unchanged.
  Preserve decimal imported endnote numbering through DOCX reopening and
  editable ODT saves; declare decimal native note configurations and refuse
  mixed fixed/automatic note numbering that cannot retain cited labels. See the
  [native-output contract](../../docs/roadmaps/zotero/native-odt-output.md).

- Extend bounded native ODT input with horizontal/vertical merged tables.
  Validate explicit covered-cell ownership, preserve originating Zotero fields,
  and emit empty native vertical continuations with summed logical widths.
  Keep existing styles and shared table/cell/paragraph budgets; refuse hidden
  covered content, ambiguous coverage, conflicting shading and repeated owners.
  Engine/editor regression sources and independent source review are preserved.
  The [editable-output continuation](../../docs/validation/zotero-editable-odt-20261121/README.md)
  executes the previously blocked local qualification and records its results.

- Preserve namespace scope when capturing XML fragments: retain inherited
  prefixes, including QName-only extension references, without allowing a
  descendant's prefix shadow to overwrite the captured root's identity.
  Expose an immutable `XmlPullReader.inScopeNamespaces` snapshot and retain
  local/default namespace declarations through repeated document saves.

- Extend bounded Word VBA with typed section `TextColumns`, named/positional
  `SetCount`, exact point `Spacing` and Boolean `LineBetween` writes. Add guarded
  native uniform-column edits with sparse section ownership, geometry checks,
  explicit same-value assignments and whole-run rollback. Preserve unrelated
  native metadata, namespace aliases and inert DOCM parts; recognize native
  separator Boolean spellings. Include a runnable two-section BAS module and
  source, native, CLI/MCP and portable regression coverage. See the
  [text-column contract](../../docs/vba-word-macros-details.md#uniform-section-text-columns).

- Extend bounded native ODT import with independently inherited Latin,
  complex-script and Asian text formatting, materialized as editable native
  runs without changing field offsets. Preserve imported script slots through
  DOCX saves and synchronize later edits only on importer-owned projections.
  Interpret supported LibreOffice defaults after inheritance and guard dormant
  paragraph/page settings against active text, language, tabs and footnotes.
  Retain the original LibreOfficeDev fixture and a separately identified
  synthetic Zotero extension. See the
  [style continuation record](../../docs/validation/zotero-libreoffice-styles-20261121/README.md)
  for qualification and the remaining native-output/installed-host boundaries.

- Add bounded `OdtDocumentReader.readBytes` and byte-based asynchronous Word
  opening for supported native ODT. Preserve rich paragraphs/styles, absolute
  external links, authored notes, simple lists and unmerged nested tables;
  reconstruct canonical Zotero citations/bibliographies by exact source
  ownership. Retain rich caches and unknown metadata through DOCX save/reopen,
  normalize ReferenceMark preferences only at the explicit import boundary,
  and archive original `meta.xml` in DOCX custom XML. Keep resource limits and
  refuse unsupported used formatting/structure before publication. Qualify
  controlled refresh/placement transactions separately from installed hosts.
  This increment retained a LibreOfficeDev 26.8 style refusal, subsequently
  addressed by the style continuation above. Ordinary ODT export remains a
  cached-result path. See the
  [rich-import record](../../docs/validation/zotero-rich-odt-20261121/README.md).

- Extend bounded Word VBA with 30 normal-slot `LanguageID` / `LanguageIDOther`
  values and independent `Font.NameBi` writes. Retain unedited language/font
  slots, theme metadata, explicit same-value inheritance overrides and inert
  DOCM contents. Correct native font ownership and namespace-aware direct/style
  projection; refuse ambiguous input before mutation. Add a runnable multilingual
  BAS module, native/compiler/transaction tests and portable VM/JavaScript
  qualification. See the [language/font contract](../../docs/vba-word-macros-details.md#proofing-language-and-complex-script-font-controls).

- Qualify the incoming bounded ODT reader's table-style inheritance. Preserve
  inherited alignment and row keep-together, honor explicit transparent cell
  fills, and distribute an explicit table width across unspecified columns.
  Refuse conflicting fixed widths, duplicate used property containers and
  unsupported structural-style metadata. Retain 23 preservation regressions
  when reconciling the incoming branch with the richer import contract above.

- Add `OdfZotero.inspect`, a bounded read-only native ODT Zotero inventory.
  Retain canonical citation ReferenceMarks, bibliography TextSections, exact
  paragraph/story/cell ownership, UTF-16 offsets, cached results and original
  document preferences. Report malformed, duplicate, overlapping, protected,
  linked and unsupported structures explicitly. Include a JSON diagnostic CLI;
  this does not enable rich ODT loading or change ordinary cached-result export.

- Preserve bounded nested tables in Zotero Add Note/Add Annotation content,
  including recursive active-citation/list order, independent span/width
  validation and supported pictures. Keep all resource budgets shared across
  the note, cap table nesting at eight levels, and create native trailing cell
  paragraphs before final index mapping for stable DOCX round trips. Retain
  main-flow destination and unsupported-structure guards.

- Extend bounded Word VBA with `Range.NoProofing`,
  `ParagraphFormat.Hyphenation`, and `Font.Kerning`, including typed helpers
  and explicit independent header/footer paragraphs. Add corresponding native
  formatting fields with exact half-point validation, sparse attribute writes,
  explicit inheritance overrides and preserved foreign XML. Include a runnable
  BAS example and source, native, layout, CLI/MCP and portable qualification.
  See the [proofing contract](../../docs/vba-word-macros-details.md#proofing-and-kerning-controls).
- Prevent incremental line translation from reusing stale page/column identity
  when an inline page break becomes active after an earlier typing edit.

- Extend Word VBA with section `Headers` / `Footers`, typed `HeadersFooters`
  and `HeaderFooter` aliases, and primary/first-page/even-page paragraph
  selection through `Range.Paragraphs`. Reuse insertion, font/paragraph
  formatting, tabs and spacing with complete story identity and normal
  transaction/policy boundaries. Guard native paragraph selection against
  inherited, shared, ambiguous and opaque header/footer targets; reject
  whole-story writes and nonbody list operations. Add a runnable BAS example
  and compiler, native, CLI/MCP and portable regression coverage. See the
  [header/footer contract](../../docs/vba-word-macros-details.md#existing-header-and-footer-paragraphs).

- Preserve adjacent equal-target ODT hyperlinks as one range with independently
  styled spans, preventing lost Unicode transfer metadata in LibreOffice.
  Define the generated `Bibliography` style through referenced-style export,
  retaining imported custom definitions and sparse styleless documents.

- Add detached `WordZoteroTransfer` / `WordZoteroTransferPlan` export and import,
  `ZoteroCitingCommand.exportDocument` and the document import/export handshake.
  Stage bounded hyperlink carriers separately from the source, retain raw
  citation/bibliography metadata and document preferences, and require native
  formatting of every imported field before publication. Support DOCX carriers,
  ODT carrier export, the legacy marker and verified Google Docs link variants.
  Preserve body/table/uniquely anchored note ownership, surrounding rich content
  and paragraph identities; reject damaged, mixed, protected, stale or excessive
  transfers. Direct native ODT reference-mark import remains separate. See the
  [transfer work record](../../docs/validation/zotero-transfer-20261121/README.md)
  for exact local and converter acceptance boundaries.

- Add `OfficeProofingProvider.categories` and the optional
  `OfficeProofingService.check(only: ...)` provider filter for category-aware
  scheduling. Providers default to all categories; the bundled German spelling
  provider declares spelling only. Existing timeout, result-validation and
  provider-ownership behavior applies to filtered checks.

- Extend section-scoped Word VBA `PageSetup` with `Orientation`, zero-argument
  `TogglePortrait`, and four `SectionStart` modes. Add guarded native
  `docx.pageOrientation` and `docx.sectionStart` operations, preserving aliases,
  helper calls, source order, recording and whole-run rollback. Orientation
  changes swap dimensions while retaining named margins, header/footer
  distances and paper code; explicit square-page orientation survives reopen.
  Section-start edits own only the native break attribute and preserve unrelated
  geometry and revision metadata. Refuse ambiguous orientation/source identity
  and unsupported new-column starts. Add an executable BAS example, source,
  native, transaction and portable checks; see the
  [section-controls contract](../../docs/vba-word-macros-details.md#section-orientation-and-start-controls).

- Replace Zotero research-content selections across consecutive ordinary
  paragraphs in one body section or authored note. Preserve rich prefix/suffix
  content, active citation order, native note separators and DOCX reopening;
  reject ambiguous ownership and selected structural/protected content before
  mutation. Add optional `insertionEndParagraph` to the staged native session.

- Extend Word VBA with explicit `Sections(i)` / `Sections.Item(i)`, typed
  `Section` and `PageSetup` aliases, `With`, and required `ByVal` helpers. Add
  eight write-only page geometry setters for dimensions, margins and
  header/footer distances, using exact twentieth-points and the existing
  measurement conversions. Lower each setter to guarded `docx.pageSetup`.
  Preserve unedited sparse section XML, namespace aliases and opaque DOCM
  parts; select custom paper on width/height writes, including same-value
  assignments. Validate each detached intermediate page body and column width,
  reject unsupported source geometry/settings, and retain whole-run rollback,
  recording and ordinary host policy. Keep reads, broadcast page setup,
  orientation and paper-size selection outside the documented source slice.
  Add compiler, native, transaction and portable examples; see the
  [source-bound qualification record](../../docs/validation/word-vba-paragraph-pagination-20261121/README.md)
  for executed checks and remaining Office/Flutter host acceptance.

- Read Zotero JSON citation placement consistently on the VM and JavaScript:
  numeric values 0, 1 and 2 include equivalent decimal/exponent spellings;
  fractional, out-of-range, string and boolean values remain invalid. Preserve
  native XML's strict placement spellings and add literal-JSON parity cases.

- Preserve vertical and combined row/column merges in Zotero research tables.
  Normalize a bounded logical grid into native restart/continuation cells and
  remap citation/list indexes by paragraph identity. Count generated cells and
  paragraphs against whole-note budgets and reject malformed or cross-group spans.
- Keep native merged-table shading and borders on every occupied page, with
  source paragraph ownership distinct from physical row geometry. Retain the
  current conservative row-height allocation and reject invalid merge chains.
- Preserve explicit per-cell border enable/disable overrides in DOCX export and
  keep tall merged-cell page cuts open independently of inherited border style.

- Preserve horizontal merged cells in Zotero Add Note/Add Annotation tables.
  Map bounded `colspan` to native `gridSpan`, reconcile `data-colwidth` vectors
  by logical column (including unspecified zero entries), and sum covered grid
  widths for each cell. Retain rich text, lists, pictures and active citations
  through body/note insertion, DOCX save/reopen and one undo/redo transaction.
  Keep whole-note resource bounds and reject malformed logical grids, nested
  tables and unsupported table groups/styles.
- Advertise native Zotero citation merging and report adjacency to the next
  enumerated field only for physically touching citation packets in the same
  paragraph/story/note. Let Zotero own order, deduplication and formatting;
  recheck packet adjacency before application and preserve atomic abort/stale
  result handling. Structural boundaries and staged field changes do not bridge
  a merge. See the
  [continuation validation record](../../docs/validation/zotero-merged-cells-20261120/README.md)
  for qualified local source checks and remaining installed-application acceptance.

- Render inline header/footer pictures and retain distinct images when their
  dimensions match. Keep continuous-section decoration separate from body
  frames so incremental layout preserves the same pictures as full layout.
  Resolve table-style header formatting through the existing cascade, preserving
  direct run overrides and explicit border widths when style color fills an
  automatic value. Keep imported compact spacing sparse on export so later style
  changes remain effective. Retain the imported empty-paragraph border behavior.

- Extend Word VBA with inches, centimeters, millimeters and picas conversions
  to/from points, plus official named arguments for all ten measurement
  functions. Preserve bounded Double arithmetic, exact native-unit checks,
  document-independent compilation and atomic publication. Add a repeatable
  Word layout example and source, saved-document, CLI/MCP and portable
  JavaScript checks; retain the independent eight-, nine- and thirteen-operation
  examples under distinct filenames. Document the Single-precision and native
  ownership limits.

- Fall back to full Word layout for changed footnote/endnote paragraphs,
  including nested note tables, so formatting edits cannot reuse stale note
  geometry. Keep incremental body edits when note content is unchanged and
  compare note text and formatting edits against fresh full layouts.

- Resolve paragraph-control style selectors from the active document's styles
  part and load lazy Word XML before guard validation. Three regression cases
  cover unreferenced paragraph/table styles and a related styles part at a
  custom path, preserving source styles through save/reopen.

- Extend Word VBA `Paragraph` and `ParagraphFormat` with `OpenUp`, `CloseUp`
  and `OpenOrCloseUp`. Native `docx.paragraphSpaceBefore` resolves toggles after
  earlier operations in the detached document, keeps same-value writes direct,
  and preserves independent after/line spacing inheritance and opaque source
  metadata. Refuse automatic, line-based, ambiguous or unsupported before
  spacing rather than inferring it. Correct default paragraph style Boolean
  flags and native style identity/based-on namespace handling. Keep ordinary
  macro permissions, recording/replay and atomic rollback boundaries.

- Extend Word VBA paragraph formatting with explicit exact, minimum and
  custom multiple line-spacing pairs, `Space1` / `Space15` / `Space2`, and
  `LinesToPoints` / `PointsToLines`. Lower each explicit rule/amount pair to
  one guarded native `docx.lineSpacing` edit; refuse incomplete pairs and
  intervening document mutations without reading live document state.
  Preserve independent spacing inheritance, native metadata and opaque VBA
  parts. Correct alternate-prefix native spacing projection during style
  resolution and repeated save/reopen. Keep ordinary macro policy, recording
  and atomic publication boundaries.

- Extend Word VBA `ListFormat` with `ApplyOutlineNumberDefault`, write-only
  `ListLevelNumber` and `ListIndent` / `ListOutdent`. Add guarded native outline
  creation and level changes, preserving list identities, imported definitions,
  paragraph metadata and atomic publication. Resolve target levels and their
  supported indentation instead of guessing from display labels or numbering
  IDs. Refuse missing levels, boundary overflow and unsupported source geometry;
  retain existing single-level defaults and serializer-sensitive field guards.
  Preserve inherited right indentation during new list edits. Resolve native
  indentation correctly when imported Word XML uses alternate or rebound
  namespace prefixes, retaining original extension metadata over save/reopen.

- Preserve foreign namespace bindings and attributes whose names collide with
  namespace prefixes during native Word list edits. Retain imported numbering
  suppression source metadata through style refresh and repeated save/reopen.

- Extend Word VBA with typed `Range.ListFormat` selectors, aliases, helpers and
  `With`; add `ApplyBulletDefault`, `ApplyNumberDefault`, and `RemoveNumbers`
  with named optional enum arguments. Resolve apply/remove toggles at native
  execution time using guarded numbering definitions, preserve imported lists
  and opaque content, and retain atomic publication. New lists use deterministic
  Quds defaults; all-number removal refuses selected LISTNUM fields, while
  paragraph-only removal preserves supported field packets. Refuse list edits
  when serialization would discard unbalanced field boundaries, including those
  crossing opaque content, before publishing any mutation. See the Word dialect contract for
  supported list behavior values and remaining gallery/layout limits.

- Extend Word VBA with typed `TabStops` selectors, aliases and helpers,
  `Add` with named/optional numeric arguments, and `ClearAll`. Add native
  single-position tab updates and inherited custom-tab clearing, retaining
  unrelated source XML, style inheritance and the document default-tab interval.
  Preserve exact signed twip positions and normal atomic publication/permissions.
  Collection reads, returned `TabStop` objects and implicit hanging-indent
  behavior remain outside this bounded source adapter.

- Extend Word VBA with typed Font/ParagraphFormat helpers, Paragraph.Format,
  reading order and exact single/1.5/double line-spacing presets. Preserve
  independent native spacing attributes and keep foreign/nested layout XML
  opaque on reopen. Add PowerPoint text-frame margins with exact EMU validation,
  per-side native ownership and matching inset placement in PDF/live models.
  Compare margin edits with the imported baseline so unchanged native margins
  preserve plain replacement behavior and direct edits back to defaults apply.
  Shared module helpers gain named arguments, optional scalar defaults and
  explicit omitted-Variant/IsMissing handling. These remain bounded adapters;
  named application-member arguments and live document reads are not added.

- Invalidate Word paragraph break caches before dirty or full-layout paths,
  including frame wrapping and empty paragraphs that do not replace the cache.
  Prevent stale glyphs reappearing when later edits move an unchanged paragraph
  into ordinary flow, while retaining break reuse for proven-clean paragraphs.

- Preserve bounded rectangular Zotero research-note and annotation tables as
  native Word blocks, including rich cell content, pictures, independent lists
  and active citations in row order. Map consistent column widths and supported
  cell fills while sharing whole-note resource budgets. Preserve surrounding
  prose, authored-note markers and a main-flow caret after trailing tables.
  Initially refuse merged/nested tables, unsupported styling and table-cell
  destinations for table payloads before publication; the continuation above
  adds horizontal merged cells. See the
  [implementation and validation record](../../docs/validation/zotero-research-tables-20261120/README.md)
  for the tested source and remaining application acceptance.

- Continue the bounded Word/PowerPoint VBA adapters with Word document aliases,
  `Paragraphs.Item`, small caps, superscript/subscript and fixed-palette
  highlighting; add PowerPoint typed text-frame/formatting/transition helpers,
  vertical text anchors, slide visibility, click advancing, duration and eleven
  supported entry effects. Preserve per-property transition source provenance
  and explicit formatting intent. Qualify the combined engine source with
  2,190 local regression cases, strict analysis and matching VM/JavaScript
  execution of both actual BAS examples. Preserve Morph/native transition
  compatibility and the accepted per-note numbering reader fix. See the
  continuation record for source hashes, results and host/UI limits.

- Extend staged Zotero research-content insertion to authored footnotes/endnotes
  and explicit single-paragraph replacement ranges. Preserve citation order,
  note ownership, rich content and leading note markers without creating nested
  notes. Revalidate ranges before application and retain atomic field, structure,
  Unicode-boundary and protection guards. Protect ordinary complex Word fields,
  bookmark endpoints and empty atomic tokens during replacement. Resolve native
  footnote/endnote list labels with independent counters when reopening DOCX.

- Add the bounded `vba-powerpoint` adapter on the shared VBA compiler: explicit
  slide/shape/text-range bindings, indexed or exact-name selectors, text,
  font/alignment and geometry writes, with strict collection guards for
  ungrouped, faithfully modeled slides. Add BAS CLI commands, default MCP
  registration and specification-derived VM/JavaScript conformance cases.
  Preserve imported rich text during native formatting, including explicit
  false and same-value assignments, and retain atomic rollback and opaque
  macro-project parts.

- Extend `vba-word` with all 18 `WdUnderline` styles, strikethrough, signed
  left/right/first-line indentation, keep-together and page-break-before.
  Negative first-line indentation clears the first-line value and writes a
  hanging indent; later positive/zero assignments clear that hanging indent.

- Preserve normal-autofit values on authored and edited presentation shapes,
  including percent-form attributes and exact zero/full-scale bounds. Apply
  reduced line advances consistently in PDF while respecting fixed-point
  paragraph spacing and retaining ordinary text-box defaults.

- Register PDF picture opacity resources and scope opacity changes to the
  picture, retaining source alpha, border opacity and caller graphics state.
  Use the same rich slide-paragraph layout for measurement and painting so
  blank, numeric, wrapped and mixed-run lines retain their vertical anchors.

- Preserve Zotero research-note lists with up to nine mixed nesting levels,
  independent counters and starting numbers, and multiple paragraphs per item.
  Keep continuation paragraphs unnumbered at the correct indent, retaining
  active citations and embedded pictures through the staged document operation
  and DOCX save/reopen.

- Keep image-only authored Word paragraphs inline when their properties or
  metadata carry list, heading, hyperlink, comment, field or revision ownership.
  Preserve their one-character caret position on repeated DOCX reopen while
  retaining the existing block-picture behavior for bare legacy paragraphs.

- Accept bounded embedded PNG and supported upright RGB/YCbCr JPEG pictures in
  Zotero Add Note and Add Annotation responses. Preserve original image bytes,
  dimensions, alternative text, title, ordinary links and active citation
  offsets as native inline Word pictures. Validate complete raster streams and
  resource budgets before publication; unsupported content refuses the entire
  staged insertion. Preserve refresh and DOCX save/reopen behavior.

- Hide the selected inherited slide gradient immediately after a direct master
  background edit in PDF export, while retaining authored slide/layout fills.

- Add the bounded `vba-word` adapter on the shared VBA compiler. Target explicit
  document paragraphs, insert text before their content, and apply supported
  font and paragraph formatting through existing atomic Word operations.
  Preserve paragraph boundaries, strict host-specific objects, exact half-point
  font/twip spacing units, XML-safe text and shared resource limits. Add explicit
  Word BAS CLI commands, default MCP registration, independent conformance and
  native/CLI/MCP integration coverage.

- Add explicit VBA Variant `Empty`/`Null` states, default Variant lifecycle,
  `IsEmpty`/`IsNull` and bounded `CVar`/`CBool`/`CDbl`/`CLng`/`CStr` conversions.
  Preserve eager Null logic, ties-to-even rounding, invariant numeric text,
  shared work limits, and strict unsupported coercions. Empty cell writes clear
  values/formulas while retaining formatting; Null publication fails before a
  plan is returned. Add independent conformance cases and a runnable Variant
  report with native runtime, MCP, CLI and rollback coverage.

- Integrate captured PPTX linear-gradient and picture-shadow work. Preserve
  gradient stops and angles through shape copying and save/reopen, render the
  gradient in PDF, and keep selected slide/layout/master gradient backgrounds
  separate from decorations so overrides and master edits remain correct.
  Preserve radial gradient snapshots and paint them through the same scoped
  editor/PDF paths. Native PowerPoint rendering is not newly qualified by this
  increment.

- Resolve PPTX picture and gradient background ownership per slide, layout and
  master, preserving authored overrides independently of hidden master shapes.
  Retain authored background XML and image relationships through copying and
  save/reopen; explicit solid edits replace the original fill without reviving it.
  Draw authored picture borders after cropping in PDF export and retain the
  existing numeric text, font fitting and connector regressions.

- Add bounded VBA `Len`, `Left$`, `Right$`, and `Mid$` string intrinsics with
  explicit UTF-16 semantics, a versioned conformance corpus, and portable
  VM/JavaScript receipts. Refuse malformed UTF-16 at workbook-write boundaries
  while preserving valid internal substring operations and transactional runs.

- Preserve nearest authored PPTX picture-background ownership and gradient
  fallback independently of master-shape visibility through copies and repeated
  native saves. Retain existing media bytes, deep and negative imported crops,
  and native master inheritance after solid-background edits. Keep explicit
  slide/layout fills authoritative and isolate PDF picture-border canvas state.
  Retain authored background XML, gradient stops, no-fill and namespace bindings
  with valid copied image relationships. Apply direct master edits during PDF
  rendering and keep inherited picture snapshots in fresh-deck copies. Add
  focused ownership, package, copy and save regressions.

- Import and render geometric/flowchart presets with distinct convex pentagon
  and home-plate silhouettes. Preserve home-plate identity through copy and
  PPTX save/reopen, and match PDF fill and outline geometry.

- Integrate inherited PPTX decorations, block arrows, short PDF heading fitting
  and authored LTR numeric text. Preserve hidden-master flags and resolved empty
  decoration lists through import/copy/save while retaining layout decorations,
  background ownership and rich-run overrides. Apply inherited PDF font scaling
  only once, retain numeric order across wrapping, and include arrow outlines,
  emoji fallback and flipped connector diagonals. Preserve connector orientation
  through save/reopen, geometry operations, morphing and full slide copies.

- Add bounded, read-only Zotero child-note and attachment metadata pages with
  exact parent/library validation, inert note markup, and explicit pagination.
  Retain local database provenance on catalog snapshots so inspecting their
  children requires the same identified Zotero 10+ database.

- Keep imported slide runs as a source snapshot while applying scalar edits
  to derived rendering runs. Respect explicit plain-run overrides, inherited
  backgrounds, and PDF text tab-stop alignment.

- Resolve direct master-background edits while preserving imported secondary
  master colors until the master changes. Keep explicit slide/layout fills
  independent and carry inherited background provenance through slide copies.

- Integrate recent PPTX background, crop, rich-text and interlaced PNG work.
  Preserve inherited master backgrounds and apply scalar text-format edits to
  imported rich runs consistently in PDF export without changing source runs.

- Add read-only paginated Zotero tag catalogs for libraries and collections,
  with literal name preservation, containing/prefix searches, optional usage
  metadata, validated requests and separate online/desktop routes. Keep manual
  and automatic tag records distinct without combining their usage counts.

- Extend `vba-excel` with local one-dimensional dynamic arrays, `ReDim`,
  `ReDim Preserve`, `Erase`, and module `Option Base 0/1`. Preserve element
  types, source evaluation order, enumeration locks, shared slot/string/work
  bounds, and the existing native-plan transaction and policy boundary.
- Add dynamic array report, lifecycle/boundary, CLI/MCP and JavaScript
  regressions, and a staged Word/Excel/PowerPoint VBA parity roadmap.

- Extend `vba-excel` with fixed one-dimensional scalar arrays, constant bounds,
  indexed reads/writes, typed defaults, `LBound`/`UBound`, and `For Each` over
  arrays and explicit rectangular ranges. Add read-only range row/column
  coordinates while retaining source-only evaluation and shared work limits.
- Bound active array slots and retained string occupancy across procedure
  calls. Preserve bare helper-call comparison syntax alongside indexed
  assignment, and add an array report plus compiler, boundary, CLI, MCP,
  rollback, and cold JavaScript regressions.
- Preserve slide table cell text colors when reopening PPTX files. Keep the
  first representative cell ink separate from its fill and enclosing shape,
  including theme-resolved colors and repeated save/reopen cycles.

- Extend `vba-excel` with conditional `Do`/`Loop` and `While`/`Wend` loops,
  `Exit Do`, and ordered `Select Case` alternatives, ranges, and comparisons.
  Keep source evaluation within the existing shared budgets and execute nested
  blocks with explicit continuations for portable maximum-depth behavior.
- Add a classification report and compiler, boundary, CLI, MCP, atomicity,
  and cold JavaScript depth regressions for the new control flow.

- Use CrispOffice for new revision/comment authors, document producer metadata,
  PDF titles, Zotero processor identification and built-in samples. Preserve
  explicit authors and attribution already stored in imported documents.

- Add the `vba-excel` language compiler for an explicitly invoked Excel VBA
  subset. Lower supported scalar expressions, variables, worksheet/range
  bindings, conditions, and bounded loops into the existing native macro plan,
  with source diagnostics and compile-time resource bounds.
- Resolve worksheet names through the shared command handler, preserving native
  zero-based indexes and translating VBA one-based indexes in the compiler.
- Add `.bas` compile, validation, and execution CLI commands, default MCP
  compilation, a monthly totals example, and portable JavaScript qualification.
  Embedded projects remain inert; full VBA and document-dependent branching
  remain unsupported.

- Add `quds_office_automation.dart` with versioned, parameterized native macros,
  successful-call recording, detached document transactions, host operation
  allowlists, limits, cooperative cancellation, and a language-compiler registry
  suitable for explicit future VBA adapters. Embedded VBA remains inert.
- Promote all 67 fidelity document operations into one portable catalog shared
  by native macros and MCP while retaining the original CLI entry points.
  Refuse unsupported protected edits and require explicit host image lookups.
- Add macro and MCP stdio CLIs, structured diagnostics, complete-output file
  publication, examples, and regression tests including opaque VBA preservation.

- Preserve combining maddah and hamza in Arabic phrase comparison and reject
  matches inside Unicode word/identifier tokens without changing source offsets.
- Keep distinct findings from one provider separate when merging equivalent
  cross-provider findings; retain complex-script language and formatting when
  deciding whether adjacent Word runs may coalesce.
- Add explicit active-language-only Word override removal while preserving the
  existing low-level reset defaults and unrelated native language metadata.
- Split proofing ranges without changing unselected text, and retain run
  boundaries when joining them would change script-dependent language routing.

- Add Zotero's native Add Annotation command for Zotero 9 and later. Selected
  text annotations use the research-note insertion protocol, preserving active
  citations, comments and supported formatting in one staged transaction.
- Expose `ZoteroCitingCommand.insertsNoteText` so hosts apply the same insertion
  preflight and cancelled-picker handling to Add Note and Add Annotation.

- Import simple bulleted and numbered Zotero research-note lists as native Word
  lists, including ordered-list starting values, rich item text and active
  citations. Keep surrounding prose and existing list counters separate, with
  scoped numbering-part undo/redo snapshots that preserve unrelated package
  content. Nested lists, multiple paragraphs per item and custom list markers
  remain explicitly unsupported.

- Add native Zotero research-note insertion through the HTTP Citing Protocol,
  retaining paragraph/heading structure, supported character formatting,
  hyperlinks and active citation placeholders. Stage complete note operations,
  respect document citation order and note placement, and refuse unsupported or
  incomplete fragments before applying them.

- Recognize decomposed accented forms of all shipped German dictionary letters,
  including Joël and Škoda, and normalize accents separated by soft hyphens.
  Personal and ignored words share the same case-sensitive comparison.
- Keep soft hyphens from exposing links, email, code and numeric/connector
  identifier fragments to German spelling corrections. Preserve exact source
  offsets and complete graphemes, including Unicode Prepend characters.

- Add bounded, read-only Word document comparison with paragraph alignment,
  grapheme-safe inline differences, revision text projections, modeled
  formatting/structure comparisons, stable locations and JSON reports.
  Disclose scope limits and coarse alignment; preserve input revision state.
- Deprecate the invalid mutating `WordCompare.compare` implementation and fail
  before mutation. Use `WordDocumentComparison.compare` or `WordCompare.diff`.

- Emit complete dynamic footer PAGE packets, preserving their result formatting.

- Offer existing accented dictionary forms for short German misspellings such
  as `Cafè` and `Joêl` through a bounded one-edit shortlist. Keep direct choices
  first, prefer matching lexical case within that fallback, and preserve the
  shared candidate limit. Protect identifier prefixes with supplementary digits,
  connectors and combining marks without copying or rescanning source prefixes.
- Expose loaded Zotero abstracts, item-specific publication titles, publishers
  and immutable exact tag names for reference inspection. Preserve optional
  metadata without changing source identities, embedded CSL or request routes.

- Count distinct displayed German corrections after applying source casing,
  so uppercase and sentence-initial variants do not consume duplicate shortlist
  slots. Preserve exact personal spelling and the existing candidate budget.

- Add bounded literal tag filters to library, collection and desktop saved-search
  requests. Multiple tags use repeated parameters to require all tags before
  pagination. Preserve Unicode and reserved characters, escape initial hyphens,
  and reject names that Zotero cannot represent literally.

- Recognize internal typographic apostrophes in German dictionary and personal
  vocabulary lookups while preserving each source apostrophe, hyphen and UTF-16
  range in corrections. Keep quotation punctuation and noun casing distinct.
- Offer complete corrections for multiple misspelled parts of explicit German
  hyphen compounds, sharing one bounded candidate budget and preserving known
  constituents, whole-word suggestions, locale and authored separator styles.

- Add typed Zotero catalog search scope, sort field and direction options, plus
  single item-type filtering, across library, collection and desktop saved-search
  requests. Existing query defaults are preserved; Zotero applies the options
  before pagination.

- Keep calendar-relative conditional formatting on the injected clock's civil
  dates across timezone offsets, daylight-saving transitions and year changes.

- Preserve floating text-frame bookmarks through LibreOffice ODT-to-DOCX
  conversion by linking their graphic style to a common ODF parent.

- Keep ODT column breaks and keep-together settings distinct when caching
  paragraph styles, and emit section column settings on the ODF columns child.

- Add the independently ignorable `de.grammar.verb-object-case` rule for
  complete, bounded pronoun/verb/object clauses. Preserve valid fronted-object
  readings and suppress unsafe adjective-case guesses in incomplete frames.

- Write ODT section columns with the required nested column properties, keep
  empty-section page anchors inside their column section, and omit invalid
  column gaps without changing the document model.
- Accept the missing finite noun forms `Schuppen` and `Lernen` without
  lowercasing correct text; keep pinned upstream and Swiss dictionaries intact.

- Prefer verified irregular participles for unknown overregularized spellings
  in bounded pronoun-and-haben contexts, keeping ordinary ranking elsewhere.

- Preserve each paragraph's tab stops when caching ODT styles, while sharing
  styles with identical normalized tab positions, alignments and leaders.

- Extract text from paragraph-anchored ODT frames without losing whitespace,
  paragraph boundaries or table structure. Keep annotation, note and covered-cell
  stories out of body/search text and apply the shared text-expansion budget.
- Keep ODT paragraph shading and border colors independent when paragraph
  styles are cached, while reusing styles with equivalent serialized colors.
- Preserve the first capital in explicit direct quotations after a colon and
  opening quote. Keep subsequent-word casing and real misspelling checks.
- Accept the missing finite `Hof` lemma and `Grüezi`/`grüezi` greeting through
  the existing first-party word supplement; retain all pinned upstream shards.
- Share the editor's deterministic-first manual proofing report merge with
  local quality evaluation, preserving statuses, snapshot identity and offsets.
- Retain structured tables inside paragraph-anchored ODF text boxes, including
  linked drawing frames. Keep authored empty paragraphs and explicit whitespace,
  omit synthetic text-box anchors, and exclude annotation, note, covered-cell and
  ruby annotation stories under the shared text-expansion budget.
- Keep physical paragraph indents when exporting RTL paragraphs and headings
  to ODT's direction-dependent margin properties.
- Extract paragraph-anchored ODF text boxes in generic extraction and search,
  preserving their whitespace and paragraph boundaries without duplicating
  surrounding inline text or exposing hidden annotation and covered-cell text.
- Preserve ODT section page styles when the first content is a list, nested
  control, table, picture, frame, or empty section. Keep resolved first-paragraph
  formatting, honor odd/even starts, and avoid extra page breaks or empty
  anchors in equivalent continuous sections.
- Preserve nested-list sibling structure, mixed marker kinds, supported decimal
  starts/restarts and continuation, exact large counters, and literal cached
  markers for unsupported numbering. Keep auxiliary and covered-cell list
  counters independent from visible document numbering.

- Expose a read-only, language-scoped German dictionary query for optional
  grammar guards, using the existing dictionary and owner vocabulary without
  generating suggestions or accepting partial tokens.
- Repair required noun endings after unambiguous genitive determiners, such as
  `des Student` and `des schlimmen Fehler`, using the existing noun-case rule.
  Retain ambiguous articles, valid alternatives, nominalized adjectives,
  source/grapheme guards and modern-spelling corroboration.

- Broaden offline German article, case and adjective checking with 67,492
  noun lemmas from pinned Unicode-3.0 Inflection data. Load lexical buckets
  lazily on Dart VM and web, preserve ambiguous and alternative readings, and
  require modern spelling corroboration for proposed noun replacements.
- Add the independently ignorable `de.grammar.noun-case` rule for required
  noun endings, and supplement basic German noun spellings across de-DE,
  de-AT and de-CH. Keep the existing English provider and English/German
  hyphenation behavior.
- Keep note references inside exported ODT comments as labels, so annotations
  cannot consume or duplicate the note body belonging to a document reference.
- Unify English/German protected-text ranges, including Unicode email/URI
  handling, bounded backtick pairing and German identifier/contraction guards.
  Preserve equivalent German language aliases across styled runs.
- Improve bounded German orthographic suggestions, sentence-initial casing,
  personal compound vocabulary and lossless language-alias restoration.
- Expand finite German agreement to 25 families, add conservative seit/seid
  guidance, and project writing findings across discretionary soft hyphens
  while preserving original UTF-16/grapheme ranges and nominal-word guards.
- Exercise new proofing and hyphenation regressions on Dart VM and compiled
  JavaScript in the local verification gate, without GitHub Actions.

- Preserve authored logical text in shaped Word, worksheet and presentation
  PDF spans, including Arabic joining, lam-alef, bidi punctuation, source
  hyphens, generated labels and trimmed wrap separators. Keep painted glyphs
  and positions unchanged. This does not replace the shaping backend.
- Scope PDF replacement text across nested marked content and accumulate
  selection bounds across every covered text showing. Keep generic rotated
  drawing independent from replacement text, retain explicit Quds watermark
  reconstruction, and read indirect/UTF-16 properties and final EOF operators.
- Validate SFNT directories and cmap subtable bounds, character/glyph ranges
  and ordering before decoding. Keep format 12 groups compact, select an
  authoritative Unicode encoding, and preserve supported legacy fallbacks.
- Retain imported conditional-rule rank and both bounds through XLSX saves
  and worksheet renames; accept XML boolean spellings and preserve native
  expression predicates through XLSX/ODS interchange. Preserve valid native
  priorities and stopping flags, and assign unique positive priorities to
  regenerated rules that need them. Keep newer page settings when undoing a
  saved rename. Expression predicates remain preserved but are not evaluated
  by the compact conditional renderer.

- Add separately licensed American and British English automatic hyphenation
  with pinned original notices, exceptions, two/three-letter fragment minima,
  per-run language dispatch and unchanged source ownership in Word/PDF layout.
  Preserve the existing German implementation and reject unsupported dialect
  mappings, protected URL/email/code spans and unsafe word fragments.
- Extend conservative German pronoun/verb agreement to nine finite present
  families, while guarding coordinated subjects, nominal pronouns, comparisons
  and ambiguous dative uses of ihr. Accept horizontal nonbreaking whitespace.
- Protect closed matching-backtick code spans consistently in German spelling
  and writing checks. Repair one unknown explicit-compound constituent while
  retaining the other noun casing and authored hyphen/nonbreaking-hyphen style.
- Preserve all existing German dictionary and pattern data. New Dart regressions
  and local verifier coverage accompany the changes; see the 2026-11-16 English/
  German continuation report for the execution-environment qualification limit.

- Keep TrueType glyph offsets aligned, retain/remap composite dependencies and
  preserve font metrics, style and embedding metadata while recomputing subset
  coverage. Reject malformed/cyclic glyph structures without recursive outline
  expansion; preserve valid nested composites and their trailing instructions.

- Preserve distinct Unicode aliases of a shared font glyph in Word, worksheet
  and presentation PDFs. Give each character its own CID, embed an explicit
  CIDToGIDMap and index PDF widths by CID. Low-level canvas callers can opt in
  with `PdfCidEncoding`; existing identity-encoded calls remain compatible.

- Preserve supplementary Unicode in embedded TrueType subsets with a complete
  format 12 cmap; correct format 4 lengths and avoid overflowing their 16-bit
  length field for large sparse mappings. Ignore invalid scalar requests.
- Encode PDF ToUnicode destinations as UTF-16BE, preserving supplementary
  characters through export, reopening, search and text extraction.

- Keep protected URL/email text out of German agreement context, retain
  surrounding URL punctuation for balance checks, recognize uppercase URL
  prefixes, and suggest Swiss `SS` for uppercase sharp-s spellings.
- Preserve ZERO WIDTH SPACE opportunities and WORD JOINER/no-break controls
  through normal, prepared, emergency and contextually measured wrapping,
  without changing source text or UTF-16 offsets.

- Add optional pure-Dart `WordRunMeasure`/`WordMeasuredCluster` contracts for
  contextual host advances before Word wrapping, preserving source ranges and
  validating complete grapheme coverage. Retain scalar/font fallback for hosts
  without a shaping callback, and carry callbacks through notes and tall tables.
- Keep lam–alef continuation glyphs in their source complex-script family.
  Compute natural line widths for left, center and right alignment; reserve
  justification expansion for justified/distributed paragraphs.
- Remeasure actual trimmed line fragments before emission and repair overflow
  at legal source boundaries with bounded host measurements. Use the same
  checks for adaptive frame widths, preserve discretionary hyphen ownership,
  and prevent ordinary breaks inside decorated-space graphemes.
- Restore original scalar/font advances when a shortened line fragment is
  declined by the host shaper, including zero-width ligature continuations.
- ODS writer now emits conditional formats (numeric, text, duplicate and
  between rules) with cell styles, and writes/reads list and numeric validations
  with prompts and error messages.

- Add `OdsSheetWriter` for the shared spreadsheet model: multiple sheets, typed
  values, cached formulas/OpenFormula references, cell styles, number formats,
  merges, geometry, hidden state, tab colours, comments, hyperlinks, named
  ranges/expressions, print areas/titles, autofilter ranges, conditional formats, validations and
  worksheet pictures through Pictures/* draw anchors. This is a new export path;
  page-style serialization remains follow-up work.

- Import spreadsheet-level ODS list-validation definitions for all referring
  worksheets, including lists resolved from a later source sheet. Retain
  table-local definition compatibility without leaking it into other sheets;
  foreign-namespace containers do not define shared rules.



- Preserve mixed native Zotero citation character styles in protected Word
  field packets, including ordinary editing, clipboard operations, paragraph
  splits, native note conversion and DOCX round trips. Keep tracked-change
  source ranges intact during import. Continue first-use style selection and
  catalog insertion inside one staged document transaction.
- Render automatic footnote/endnote labels in body order without renumbering
  stored link IDs. Honor common native number formats and section settings,
  preserve custom marks and keep display/caret offsets aligned when label
  lengths differ from source IDs.

- Add Zotero's native HTTP Citing Protocol with bounded, credential-free
  loopback transactions, exact command/field validation, cooperative cancellation
  and error cleanup. Stage complete Word citation/bibliography refreshes,
  inline/footnote/endnote insertion and safe note conversions without live
  mutation. Preserve native XML/JSON document preferences in owned, chunked
  `ZOTERO_PREF_*` custom properties. Keep processor-managed citations separate
  from the basic fallback. Verify German ibid., numeric ordering and
  disambiguation against pinned real Zotero CSL output; live native acceptance
  remains pending.

- Verify persistent source identities before connected Zotero item reads and
  selected-source exports. Check complete selections before formatting; pin
  desktop database identity and library version across aggregate requests.
  Metadata-only item reads allow basic refresh without citation-style work.
  New linked Word citations reject request aliases and malformed identities,
  while imported opaque metadata remains preserved.

- Add a credential-free desktop Zotero API client with fixed loopback routing,
  API version checks, database identity pinning, bounded pagination and local
  CSL response normalization. Separate local request aliases from persistent
  numeric or unsynced item identities; never create `/users/0` citation URIs.

- Add Zotero CSL citation and bibliography field inspection, bounded JSON
  metadata, embedded CSL items, explicit cached-text insertion/editing, and
  deliberate unlinking. Write native complex ADDIN fields and preserve rich
  imported caches and unknown Zotero metadata. Cached-text operations remain
  available without a running native Zotero processor.

- Complete the bounded ODS picture and spreadsheet-state pass: embed package
  pictures as worksheet drawings, apply nameless document default styles and
  default column/row geometry, preserve hidden rows/columns/sheets, import
  conditional formats (numeric, between, contains-text, begins/ends-with and
  duplicate) with generated dxf styling, and import literal/range-source plus whole/decimal/date/text-length/custom
  validations with operators, date serials, prompts/error styles and corrected
  Excel list quoting. Import ODS print areas/titles, named ranges/expressions, tab colours, cell
  hyperlinks, outline groups and simple database-range filter predicates; add XLSX
  print-area read/write. Documented limits remain for range-source
  validations, expression/visual conditional rules, ODS metadata and package
  part naming.

- Preserve ODS authored date-component order, literal separators, full month and
  weekday names, and cell annotations through XLSX copies. Annotation text stays
  separate from cell values; repeated notes and authors share the existing cell
  and expanded-text limits. Multiple, nested or foreign-namespace annotations
  and ambiguous authors explicitly decline. Escaped/quoted format literals do
  not become date tokens or numeric section separators.
- Reconcile current ODS geometry, currency and explicit whitespace imports with
  bounded namespace-aware parsing. Keep inherited empty-cell padding sparse,
  retain explicit formatted blanks, and reject stored cells hidden inside an
  earlier vertical merge. New regressions bind native column widths, default
  geometry and currency symbols to an XLSX copy round trip. New worksheets now
  write retained default/base column widths in native units; existing native
  sheet-format attributes remain intact.
- Accept Word OOXML formatting vocabulary, preserve all underline styles, and
  continue character formatting after splitting a paragraph at its end.

- Apply ODS cell style precedence from explicit cell, row default and column
  default styles, including repeated cells that cross differing column styles.
  Default-style padding remains sparse and column style bookkeeping shares the
  workbook dimension budget. Preserve absolute sheet references, clock component
  formats and elapsed hour/minute/second formats through XLSX saves. Quoted
  formula text and sheet identifiers retain their original content. The importer
  also retains its compatibility extension for omitted horizontal covered-cell
  placeholders; standard ODF requires those placeholders. Explicit covered cells
  consume reserved positions once, and ambiguous overlapping merges still decline.

- Import ODS merged anchors and covered cells at their original coordinates,
  including vertical spans and data after repeated blank rows. Recognize row
  and column groups by namespace, resolve named cell styles from `styles.xml`,
  and retain inherited wrap settings, explicit spaces and formula string text.
  Repeated padding advances the grid without allocating cells; meaningful data
  outside 100,000 rows or 4,096 columns declines instead of being truncated.
  The workbook shares limits of 128 sheets, 200,000 materialized cells,
  200,000 dimension assignments, 1,000 merges and 8 MiB expanded UTF-8 cell text.
  Input and combined XML each cap at 64 MiB; XML nesting/events and style work
  have separate limits. Repeated formulas, matrix formulas, repeated merged
  anchors, overlapping merges, nested tables and covered cells that contain
  stored data explicitly decline. Ordinary stored cells inside earlier merged
  coverage also decline when the required covered-cell token is missing.
  Preserve quoted sheet identifiers in converted formulas, including names
  with punctuation, through XLSX saves. This is a bounded ODS-to-XLSX import profile,
  not roundtrip preservation of arbitrary ODF features.

- Preserve imported typed formula caches through unsupported dependencies,
  including cross-sheet and runtime references. Resolve recalculations before
  writing caches, retain unsupported provenance through nested values, and keep
  genuine formula errors and cycles distinguishable.
- Preserve native SpreadsheetML namespaces, foreign extensions and unedited
  style properties when formatting cells. Horizontal alignment no longer adds
  vertical centering. Clearing the last direct format now reaches the saved
  workbook, including resets of bold, font size/colors, fill and alignment.
- Preserve all native Word protection edit modes and password/hash metadata.
  Expose native formatting restrictions so hosts can enforce them conservatively.
- Refuse signed spreadsheet and presentation import/export for editing when
  OPC signature paths, content types or relationships are present. This detects
  signature markers; it does not verify cryptographic validity.

- Use the pure-Dart `characters` package for Unicode 16 extended grapheme
  boundaries. Indic conjuncts, spacing marks and other previously omitted
  clusters retain their original UTF-16 ownership during constrained wrapping
  and caret lookup; the public grapheme API remains unchanged.

- Wrap overflowing words inside fixed table cells and text frames at source
  grapheme boundaries, retaining normal word breaks and original Arabic/bidi
  shaping. Row measurement grows with the wrapped content. Body paragraphs keep
  their existing overflow policy. Correct flag pairing, emoji modifier grouping
  and supplementary UTF-16 line ends; an indivisible cluster wider than its box
  stays intact. Authored nested-cell references and direct/isolate regressions
  require complete visible text before pixel comparisons can pass.

- Preserve native table-cell preferred widths, including percent, automatic and
  nil widths, through direct and isolate saves. Explicit point-width edits now
  reach DOCX output, and merge/unmerge updates widths from the logical grid.
  Capturing a namespaced XML element no longer lets `xmlns:w` overwrite `w:w`.
  Scripted cell edits and unmerge accept `gridColumn` to address the visible
  origin of merged cells while retaining legacy physical `column` indexes.
  Independently authored native baselines, three-save XML oracles and corruption
  controls cover nested tables, spans, rich text, widths and bookmark identity.

- Provide bounded legacy DOC/DOT body-text conversion into a newly authored DOCX
  with an explicit text-only result contract. Port global compound-file directory
  ownership and raw stream-size checks; identify relocated DOCM/DOTM main parts
  without lowercasing case-sensitive package keys. Host conversion dialogs and
  destination capture remain in CrispCloud.

- Preserve imported formula caches when the evaluator cannot parse the entire
  expression, and serialize supported string, Boolean and error results with
  their native cell types. Internal error provenance keeps literal error-looking
  text distinct while the public evaluator continues returning scalars. Decode
  escaped formula quotes and resolve worksheet
  names case-insensitively without redirecting missing sheets to the active one.
  Rename undo updates owned reference slots without discarding later cell edits
  or values produced by a save; complete shared-formula groups remain supported.

- Expose namespace-aware Office part navigation and bounded OOXML/OpenDocument
  text search through the pure-Dart engine. Follow declared package graphs and
  referenced stories, notes, worksheets and slides; reject ambiguous roots,
  duplicate identities, malformed selected XML/ZIP and exhausted input/output
  budgets. Hosts retain cloud traversal and presentation rather than format
  extraction implementations.

- Retain native slide placeholder type/index bindings on save so layout/master
  inheritance keeps title alignment and bullets. The section corpus now compares
  each first export's page text and RGB fingerprints with an independently
  authored source-page permutation, in addition to three-save stability.

- Add reference-aware worksheet renaming across formulas, names, native rules,
  links, charts and pivot sources. Preserve strings, structured references and
  external workbook qualifiers/cache data. Reversible edits preflight stale
  model/native changes and opaque reference owners before mutation; repeated
  whole-row/column qualifiers and three-dimensional endpoints are handled.

- Preserve native slide section GUIDs, empty sections, membership metadata and
  foreign extension namespaces. Reorder slides through an atomic plan that
  adopts the original destination section while keeping every other membership;
  malformed sections and stale plans reject before mutation. Independent native
  XML oracles cover within-section, forward/backward and emptied-section moves
  through three direct/isolate saves.

- Expose shared bounded compound-file reading, legacy Word text extraction and
  macro/template preservation guards. Optional ZIP limits check actual inflated
  bytes before growth; opaque-part relationships and native main-part/type
  identity are verified before host upload.

- Expose read-only native DrawingML line geometry for Word frame previews,
  including explicit width, preset/custom dash spacing, caps, joins and inset
  alignment. Preserve the original XML through clone, color edits and repeated
  direct/isolate saves; malformed fragments retain the visual fallback.

- Reserve native footnote/endnote separator-definition IDs when inserting new
  notes, including relocated note and main parts. Imported absence of separator
  definitions also suppresses the preview rule; new note parts retain their
  standard definitions. Three-save regressions preserve both behaviors.

- Integrate formatting-aware note updates with native markers: Enter and
  backspace carry actual inline boundaries and styled text; imported unmarked
  or later-marked notes retain visible leading whitespace. More complex
  paragraph-count replacements containing native ranges reject before mutation.
  Heading ID allocation also reserves bookmarks inside preserved opaque XML.

- Preserve native bookmark IDs, names, optional attributes and exact ordered
  endpoints across multiple ranges, overlapping ranges, paragraphs, tables,
  header/footer stories and notes. Zero-width markers survive run edits,
  paragraph splitting and copies; generated heading anchors avoid collisions.
  Unpaired/duplicate identities reject before package mutation. Bookmark
  endpoints outside modeled paragraphs reject explicitly on import.

- Preserve native block and inline content-control properties, IDs, aliases,
  tags and end formatting around ordinary editable content, including nested
  and empty controls, table-cell/note blocks and legacy qudsFrame geometry.
  Invalid or crossing boundaries and duplicate IDs fail before export changes
  package parts. Inline-control paragraph splits reject before changing history;
  unsupported row/cell wrappers, block header/comment controls and inline
  drawing containers and controls inside hyperlink/revision wrappers fail
  explicitly on import instead of losing their wrappers.

- Preserve the absence, exact positions and individual run properties of native
  automatic footnote/endnote body markers, including multiple marks and marks
  inside tables. Whole-body text replacement keeps the first existing mark as a
  leading mark; unmarked imported notes remain unmarked. New notes retain their
  conventional leading marker and separator. This is export preservation; the
  canvas continues to use its conventional note-label layout.

- Explicitly clearing a list suppresses inherited numbering through style
  refresh, clone/history, export and reopen. Applying a list or numbered style
  restores numbering. Script formatting rejects empty ranges with the failing
  step number instead of silently leaving the document unchanged.

- Preserve imported direct table properties, including border absence, inherited
  style borders and explicit nil overrides, in body and note tables. Deliberate
  border edits retain widths, layout, cell margins and captions; new tables keep
  their existing border defaults.

- Preserve omitted, zero and small picture wrap distances on DOCX export instead
  of adding attributes or increasing them to the minimum picture size. Clones
  carry source presence, while deliberate distance edits, including zero, emit
  explicitly. Scripted paragraph splits retain
  one bookmark/restart identity, and style edits bind the Word namespace locally
  when imported style parts use different prefixes.

- Preserve sparse paragraph/run formatting when importing a document with no
  style definitions; retain empty catalogs and avoid adding unreferenced Normal
  defaults, while exporting explicitly referenced built-in styles and edits.

- Preserve imported footnote/endnote marker formatting verbatim, including an
  absent `rPr`, and retain exact source separation: no space, multiple spaces or
  tabs. New notes keep conventional superscript markers and one separator.
- Honor inherited `xml:space="preserve"` for whitespace-only text in the XML
  DOM so copied rich text and note spaces remain intact.

- Preserve imported `altChunk` blocks in body, table and note stories with
  immutable source XML and payload identity; rebind their relationships when
  moved or cloned between stories. Their external content remains unrendered.
- Allocate stable unique section-revision IDs when cloning imported sections,
  preserving their history and settings without duplicate schema identifiers.
- Add independently authored diagnostic probes for content-control wrappers
  and multiple/cross-paragraph bookmark ranges, plus passing structural
  regressions, corruption controls and three-cycle export oracles for both.

- Join native comment replies and resolved state through the final paragraph's
  `w14:paraId`, retain anchors through comment copies/edits, allocate new anchors
  without collisions, and normalize MIME declarations when clearing comments.

- Add strict DOCX/XLSX/PPTX import, inspect, edit and repeated-save scripts with
  43 operations, authored semantic expectations and deliberate corruption checks.
  Explicit script formatting retains false/zero/default values as direct edits.

- Preserve imported list-level overrides and export explicit restart instances
  while keeping subsequent items attached to the restarted numbering sequence.
- Import only the first supported markup-compatibility Choice, or its Fallback,
  throughout Word body, table, header/footer and note stories.
- Retain imported section metadata, page numbering, grids, borders, custom
  columns and revision history through unrelated edits and section cloning;
  merge deliberate page and column edits without discarding other settings.
- Export referenced built-in styles missing from an imported style catalog,
  including known parent styles and references from notes and headers.
- Write line feeds as Word breaks, read run-contained line/page/column breaks,
  and use the standard extended-comments content type.

- Preserve one worksheet drawing relationship across absolute/relative target
  forms, emit SpreadsheetML chart transforms, and normalize pivot cache links.
- Keep imported font properties, number formats and borders during cell edits
  while serializing font properties in schema order.
- Convert stored column widths with the ISO maximum-digit-width formula;
  preserve untouched import precision and export edited pixel widths accurately.
- Preserve hidden/grouped columns, default column styles, best-fit/phonetic flags
  and width-less column definitions through edits and column insertion/deletion.

- Preserve imported PowerPoint rich text bodies and export scalar font/color
  edits; use proper paragraph boundaries for multiline shape text.
- Emit valid PowerPoint chart-frame transforms and transition durations, and
  allocate valid chart axis IDs for nonconforming imported identifiers.

- Preserve pictures and charts in default, first-page and even-page headers
  and footers; keep their relationships scoped to the owning story.
- Follow package relationships when saving nonstandard Word main, styles, notes
  and settings parts, so edits reach the part opened by external applications.
- Replacing or reordering Word media no longer overwrites payloads shared by
  other stories or retained package parts. Repeated saves reuse unchanged data.

- Fix the feature-showcase template detail band so its item table fits.
- Watermark text rotates as one marked line on every page.
- Imported DOCX footnote and endnote reference marks render as superscript.
  Notes attach to the page containing the reference glyph.

## 1.5.0

- A variable can ask for a value before preview, print, and export
  (`prompt`, `required`). The saved value stays the sample default.
- A report can hold more than one detail. Each `<Section>` has its own
  data set, group header, and group footer. A file with only section 0
  stays a single flat report.
- A crosstab pivots a data set by row field, column field, and value, using
  the existing aggregates. Empty cells show 0. More than 12 columns keeps
  the first 12 and warns.
- A subreport draws another template stored at `subreports/<name>.xml` in
  the same package, once, or once per row when it sits in a repeating
  detail. The child is shifted into the parent box. A child taller than
  the parent content area warns.
- A text element can hold `<Run>` children: bold, italic, size, color,
  underline, and a link. The link becomes a PDF URI annotation and a Word
  hyperlink.
- Fonts accept `italic.ttf` and `boldItalic.ttf` beside the regular and
  bold faces. Shear is used only when the real italic face is absent.
- Barcodes add EAN-13. Twelve digits gain a check digit; a wrong check
  digit warns.
- Excel export draws images and barcodes as pictures, and writes a text
  page header or footer into the sheet header. Word export draws a barcode
  as PNG, and a shape that is not a horizontal line as an image.
- An image taller than the page continues on the next page. A chart that
  does not fit moves to the next page; one taller than the content box is
  scaled to fit, with a warning.
- `PdfToOffice` reads a PDF file into DOCX, XLSX, or a freeform PPTX.
  DOCX keeps each line and each JPEG or PNG in a page-anchored box, turns
  a clearly ruled grid into a table, and turns vector bars, pie wedges, or
  a polyline into a native chart. A PDF outline or a dot-leader list becomes
  a table of contents, and link annotations become hyperlinks. XLSX keeps
  those tables and each chart's values, and writes other text as a single
  column.
  PPTX puts each page on a slide of positioned text boxes and PNG pictures.
  A page with no text layer is reported. Scanned pixels are not read.
- `CffRaster` fills a Type 2 charstring into a bitmap. It is not a general
  CFF text face for PDF.
- `GsubLigatures` applies OpenType GSUB lookup type 4 before line breaking,
  and the ligature glyph is subsetted into the PDF font.
- Redaction in remove-content mode clears `Tj` and hex strings whose text
  origin lies inside the rectangle, then paints black. Other operators stay.
- `PdfToolbox.stamp` and `numberPages` embed a supplied TrueType face and
  shape Arabic. Without those bytes they still use Helvetica and skip
  non-Latin text.
- `WordMailMerge.documentFor` repeats a table row that contains
  `MERGEFIELD` once per record, and otherwise repeats the body with a page
  break between records.
- Ready-made templates add a sales order (`feature_showcase_ar` and
  `feature_showcase_en`): prompted customer, purchase order, and delivery
  date, a rich confirmation, an italic note, an EAN-13 code, a nested
  delivery schedule, an item table, and a branch crosstab.
- JBIG2 arithmetic, symbol, and text regions are still not decoded.

## 1.4.0

- A shape map labels each region from an attribute, a calculated column on
  the shape table, or a formula in `labelField`. The formula may name shape
  attributes directly (`Name`, `Concat(Name, "\n", SHAPE_Area)`) as well as
  `Row.`.
- The map title, the region labels, and the legend each have their own font.
  `titleStyle`, `labelStyle`, and `legendStyle` set family, size, bold,
  italic, and color. An empty field inherits the chart font. An empty label
  color keeps the contrast color, white on a dark region. XML writes
  `titleFont`, `titleSize`, `titleBold`, `titleItalic`, and `titleColor`,
  and the same prefixes for `label` and `legend`.

## 1.3.0

- Report charts add percent-stacked columns, stacked area, column-and-line
  combo (with a secondary axis), waterfall, gauge, bullet, funnel, scatter,
  bubble, radar, heatmap, sparkline, and extruded (oblique 3D) columns, pie,
  and donut. Each has controllable depth, skew, hole, start angle, curve,
  markers, line width, axis bounds, target, bands, and waterfall colors.
  Scatter and bubble plot one point per row (`x`, `y`, and `size`). PDF and
  preview draw them as vectors. Word and Excel get a native chart where
  Office has one, and the nearest bar, line, or donut otherwise.
- Ready-made templates add a chart gallery (`chart_gallery_ar` and
  `chart_gallery_en`): every chart type, then a world shape map colored
  from a separate `countries` table (`Row.code` to `Row.revenue`).
- Shape maps color regions from the bundled country atlas or from a shapefile
  or GeoJSON stored in the report (`shapes/<name>.qmap`). The atlas matches
  an ISO alpha-2 or alpha-3 code and an English, Arabic, or French name.
  PDF and preview draw the polygons in Web Mercator, a min/max legend, and
  labels on the widest regions without overlap. A world-sized layer leaves
  Antarctica out of the frame. Word and Excel show a bar of the region values.
- A chart that crosses the bottom of a page moves to the next page together
  with the charts below it, so a row is not drawn on top of the one that moved.

## 1.2.0

Reports can do the same job as a mail merge, inside one file.

- A free-form Detail band (no table inside it) honors `newPageBefore` and
  `newPageAfter`. Each row of its data set starts on its own page. Preview,
  PDF export, and Word export all include those pages. Word writes a page
  break between the rows. A Detail band that contains a table still flows
  its rows down the page, so invoices are unchanged.
- Word's own mail merge is separate. `WordMailMerge` fills `«Field»` and
  `MERGEFIELD` tokens. `merge` fills one record, and `mergeAll` returns one
  document per record.
- New template family `class_certificate` (Arabic and English): one A4
  landscape certificate for every row of a `students` table. The sample is
  a class of eight students, so opening it and previewing shows eight pages.

## 1.1.0

- `ReportDiagnostic.target` says where a finding points
  (`ReportDiagnosticTarget`: band, element index, table column or cell,
  chart series or point, attribute, variable, data table and column,
  settings section), and parser and `validate()` paths for the same spot
  agree. `ReportDiagnostic.kind` (`ReportDiagnosticKind`) says what kind of
  problem it is, and `summary` drops the exception class name from parser
  messages.
- The parser warns "No Detail band" only when the template declares data
  tables, so certificates and vouchers no longer get it.
- Templates are files. A `.qrep` that holds a `template.json` manifest
  (`ReportTemplateManifest`: id, family, titles, descriptions, category,
  language, order) is a template. `ReportPackage.template` reads and writes
  the manifest. `ReportTemplateInfo.fromPackage` and
  `ReportTemplateInfo.decode` build a catalog entry from such a file, and
  `ReportTemplateInfo.manifest`, `order`, and `compare` describe and sort
  entries. `ReportTemplateInfo.package()` returns a file-based template's own
  package, fonts included.
- `ReportTemplates` is deprecated. The same 16 templates ship as `.qrep`
  files with `quds_office_editor` (`ReportTemplateLibrary`). The class keeps
  working until 2.0.
- `ReportParseResult.readable` is false only when the XML can't be read at
  all (malformed XML, an empty document, or a root that isn't
  `<QudsReport>`). A template with expression errors is still readable, so a
  designer can open it and show the errors.
- Aggregates over `item.` in template variables, such as
  `{{SUM(item.amount)}}` or `COUNT()`, now run over the detail band's data
  set. They returned 0 before, because variables had no rows in scope.
- Template variable names may contain dots, such as `stats.sum`. Expressions
  read them as `{{Variables.stats.sum}}`. Adds `ReportVariable.segments`,
  `folder`, and `leaf`, and `ReportGenerator.nestVariables`.
  `ReportVariable.isValidName` accepts dotted names. Validation, completion,
  and variable renames all handle dotted names.
- `ReportFontFileInfo.scripts` lists the writing systems a font covers,
  read from its `cmap`. The new `ReportScript` enum has a sample text for
  each script, plus `previewText` and `primary`, so a font picker can
  preview each font in its own script.

## 1.0.0

First stable release. The public API now follows semantic versioning:
breaking changes wait for 2.0. This release brings `.qrep` packages with
embedded images and fonts, report data schemas with calculated columns, 16
bilingual report templates, and a fidelity pass over Word, Excel, and
PowerPoint files saved by other office suites.

**Files saved by LibreOffice and other suites.**

- Word:
  - Numbering levels with `numFmt="none"` or an empty `lvlText` print no label. Writer ties every heading style to such an outline list, which used to show as an extra "1." before each heading.
  - Runs inherit bold, italic and color from their paragraph style chain. A run's own `w:b w:val="0"` still wins.
  - `w:b` / `w:i` with `false` or `off` turn the toggle off, in runs and in styles.
- Excel:
  - Header and footer sections keep their formatting codes (`&"Arial,Bold"`, `&12`). These codes used to swallow the section text.
  - PDF export expands `&D` and `&T`, drops font, size, color and toggle codes, and places the left, center and right sections on their own.
  - PDF export draws each cell at its font size, bold when the cell font is bold, and honors left / center / right alignment. Numbers under General alignment sit on the right, as in Excel.
- PDF: faux bold (used when no bold face is embedded) offsets its second pass by 5% of the em instead of 0.35 pt, so it reads as bold at every size.

**Calculated columns in suggestions.**

- `ReportCompleter` also suggests the columns `<DataSchema>` declares for a table (after `item.`, `items.`, `Data.items.`, `Group.rows.`), including calculated columns and tables with no sample rows yet.
  - Calculated columns show their expression as the detail.

**Word import and layout fixes ([#2](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/2)).**

- `WordLayoutEngine(measure:)` takes a `WordGlyphMeasure` that gives glyph widths when no font face is loaded, so line breaks match the host's text painting.
- Body text uses `fallbackWidthFactor`; the wider 0.72 em estimate is now limited to table cells and frames.
- Paragraph indents are subtracted once, not twice.
- Style numbering and indents (`w:numPr`, `w:ind` in `styles.xml`) now apply through `basedOn`, so heading and list styles get their markers.
  - `w:numId="0"` removes numbering.
  - `w:start` / `w:end` indents are read.
- Table styles from `styles.xml` apply `tblBorders` plus `firstRow` / `band1Horz` shading, following `w:tblLook`.
  - A table's own borders and cell fills win.

**Excel import fixes ([#3](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/3)).**

- `t="inlineStr"` cells keep their text: rich runs are joined, phonetic runs skipped.
- Shared formulas (`<f t="shared" si>`) expand from the master formula to every follower with `FormulaRefShift.shift`.
  - Relative references move, `$` parts stay fixed, and references pushed off the grid become `#REF!`.
- `FormulaDepGraph.recalculate` skips empty formulas.
  - It keeps a cell's cached value when the engine cannot compute the formula (`#NAME?` / `#ERROR!`), so recalc and save no longer overwrite Excel's result.
- `_xlfn.` / `_xlws.` function prefixes are ignored when evaluating; the formula text keeps them.
- Number formats support positive;negative;zero sections, thousands grouping, `,` scaling, `%`, quoted literals, `[Red]` and `[$€-407]` currency tokens.
  - `0%` no longer shows two decimals.
- Charts without a value cache are drawn from their `c:val` / `c:cat` ranges, on the same sheet or another one.
  - `SmlDrawing` gains `sourceSheetName`, `labelsFromA1` and `labelsToA1`; `SheetChartData.fromSeries` pairs values with category labels.

**PowerPoint import fixes ([#4](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/4)).**

- Only `p:pic` and shapes with a `blip` fill become pictures. Text boxes no longer turn into empty "Picture" boxes because of an `xfrm` or a shadow.
- `off` / `ext` are read only inside the shape's own `xfrm`, so `a:extLst/a:ext` no longer zeroes a shape's size.
- `p:ph` is read into `PmlShape.placeholder`, `placeholderType` and `placeholderIndex`.
- Slides follow their `slideLayout` → `slideMaster` → `theme` relationships:
  - Placeholders without their own `xfrm` inherit the layout's geometry (matched by `idx`, then by type), then the master's.
  - `PmlSlide.layoutName` is set.
  - `PmlPresentation.layouts` lists the deck's layouts, without their prompt text.
- `a:schemeClr` / `a:sysClr` colors resolve through the theme and the master's `p:clrMap`, with `lumMod`, `lumOff`, `shade` and `tint`.
  - `p:style` `fillRef` / `lnRef` / `fontRef` give default fill, outline and text colors, so PowerPoint autoshapes keep their fill.
  - `gradFill` / `pattFill` use their first color.
- Slide order follows `p:sldIdLst` through `presentation.xml.rels`, and slide parts no longer have to be named `slide1..n`.
  - `SlideSerializer` writes the real relationship ids into `p:sldIdLst`.
- Morph transitions keep an empty fill instead of blending through blue.

**`.qrep` packages.**

- A `.qrep` file is now a ZIP holding `layout.xml` (the `<QudsReport>` template) and pre-saved images under `images/<name>.png|jpg`.
  - A stored `mimetype` entry (`application/vnd.quds.qrep+zip`) comes first.
- `ReportPackage`:
  - `encode()` and `ReportPackage.decode(bytes)`; `decode` also opens legacy plain-XML `.qrep` files.
  - `keyFor(fileName)` derives unique image keys; `isValidKey` checks a name.
  - PNG / JPEG only (`ReportImageFormat.sniff`); each entry is capped at 64 MB.
  - Errors raise `ReportPackageException`.
- `QudsReportEngine.fromPackage(bytes, {images})` uses the embedded images; host `images:` win on name clashes. `engine.toPackage()` writes a package.

**Embedded fonts in `.qrep` packages.**

- Packages carry TrueType families under `fonts/<family>/regular.ttf|bold.ttf`, so a report exports with the faces it was designed with.
- `ReportPackage.fonts` (`Map<String, ReportFontFiles>`), `fontRegistry({base})`, `mergeFonts(base, embedded)` and `isValidFontFamily`.
  - Host families come first and win on name clashes; the host registry is not modified.
  - Every font is checked when it is written or read.
- `QudsReportEngine.fromPackage` registers the embedded fonts; `embeddedFonts` keeps them so `toPackage()` writes them back.
- `ReportFontFile.inspect(bytes)` / `inspectWith(read)` return `ReportFontFileInfo` (family, weight, italic) from the `name`, `OS/2` and `head` tables without parsing glyphs.
  - They throw `ReportFontException` for `.ttc` collections, CFF (`.otf`) outlines, missing tables, and fonts whose `fsType` forbids embedding.

**Report data schema and sample data.**

- `<DataSchema>` in the layout declares fields and tables with typed columns (`text`, `number`, `boolean`, `date`). This is `ReportTemplate.dataSchema` (`ReportDataSchema`, `ReportDataTable`, `ReportDataColumn`, `ReportDataField`).
  - Calculated columns (`expression="qty * price"`) are evaluated for every row at export; bare names refer to the row's columns.
  - Exports coerce values to the declared types. `engine.prepare(data)` returns the record the layout sees.
  - The parser warns about unknown types, duplicates, missing names, and broken formulas.
- Packages can carry design-time sample data as `data/sample.json` (`ReportPackage.sampleData`, `engine.sampleData`). Exports only use it when the host passes it.
- `ReportData`: dotted-path `get` / `set` / `remove` / `setTable` / `addRow` / `rows`, deep `merge`, and JSON round-trip with ISO dates. `ReportDataType` handles inference and coercion.
- `ReportCsv.parse` / `rows` / `write`: delimiter detection (`,` `;` tab), quotes, BOM, and typed columns.

**Named elements and runtime data.**

- Templates keep element names unique: `uniqueElementName`, `assignElementNames`, `elementNamed` (case-insensitive), `duplicateElementNames`, `isValidElementName`.
- `QudsReportEngine`:
  - Host data: the `data` constructor parameter (`ReportData`) is merged under the map passed to each export.
  - `export(format, {data})` / `exportSync`. `ReportExportFormat` moved here from the editor.
  - Element access by name: `elementNames`, `element`, `elementAs<T>`.
  - Setters by name: `setText` (with `literal`), `setImage`, `setBarcode`, `setTableRows`, `setChartRows`, `setChartPoints`, `setVisible`.
  - An unknown name or wrong type throws `ReportElementException`.

**Bilingual, categorized templates with saved images.**

- `ReportTemplates.all` now has 16 templates: eight families, each with an Arabic (RTL) and an English version.
  - New families: product catalog (a photo per row) and certificate of appreciation.
  - New English versions of the VAT invoice, account statement, receipt voucher and inventory report, and an Arabic version of the commercial invoice and the sales dashboard.
  - Existing ids are unchanged.
- `ReportTemplateInfo` gains `family`, `language` (`ReportTemplateLanguage`), `familyTitle` / `familyTitleAr`, `strings`, `images()` and `package()`.
  - Both versions share one layout with `[[key]]` tokens filled from per-language strings.
- `ReportTemplates.families`, `variants`, `find`, `counterpart` and `inCategory`.
- `ReportTemplateCategory` gains `hr` (Human resources) and bilingual `title` / `titleAr` / `titleFor`.
- Templates carry pre-saved PNG images (logo, stamp, signature, seal, product photos) in their package.
  - The images are drawn by the new `ReportTemplateArt` (`logo`, `stamp`, `signature`, `seal`, `product(ReportProductArt)`), an anti-aliased pure-Dart rasterizer.
- `AMOUNTWORDS(amount, 'USD', 'en'|'ar')` and the `words:USD` format spell amounts in English (`EnglishWords`, 21 currencies).
- The `dateAr:` format uses Arabic month and day names (`10 أكتوبر 2026`).

**Fixes.**

- Elements that share a top edge now paint in document order. Before, an unstable sort could draw a filled shape over the text placed on it (for example, the receipt voucher amount).
- Raw deflate now emits overlapping matches and caps hash-chain walks, so long runs (for example, transparent PNG rows) compress fast and much smaller.

**Docs.**

- The README links to the Quds Report Studio installers for Windows and Linux, which design `.qrep` reports for this engine. The pub.dev screenshots include the studio and the new templates.

## 0.6.0

**Band report engine (`quds_reports.dart`).**

- `.qrep` templates:
  - `QudsReportXmlParser` gives line:column diagnostics.
  - `QudsReportXmlWriter` round-trips templates.
  - The mutable `ReportTemplate` model is built for designers.
- `QudsExpressionEngine`:
  - `System.*`, `Variables.*`, and `Data.*` paths; arithmetic, comparisons, and aggregates.
  - Formats such as `currency:LYD` and dates.
  - Arabic `TAFQEET(amount, code)` (`ArabicTafqeet`).
- Generator:
  - Report, page, and group headers/footers, detail bands, and repeating tables.
  - `canGrow` text, page splitting, and `System.TotalPages`.
  - BiDi, Arabic shaping, and RTL x mirroring (`mirrorRtl`).
- `QudsReportEngine.fromXml(xml)` exports with `exportToPdf`, `exportToExcel`, and `exportToWord`.
- `ReportMockData.infer` builds preview data from a template's bindings.
- Charts (`<Chart>` / `ReportChartElement`):
  - Types: bar, horizontal bar, stacked bar, line, area, pie, donut.
  - Data: a dataset grouped by a category expression with `sum`/`avg`/`count`/`min`/`max`/`first`/`last`, sorting, and top N; or static `<Point>` values.
  - PDF and preview draw vectors (`ReportPathPrimitive`); RTL templates mirror the plot.
  - DOCX and XLSX embed native DrawingML charts; XLSX adds the data table.
- `ReportTemplates.all`: six ready-made templates with sample data (Arabic VAT invoice, English invoice, sales dashboard, account statement, inventory, receipt voucher).
- `ReportCompleter`: suggestions inside `{{ }}` and expressions: functions with signatures, `Data`/row fields from the preview data, `System`/`Group`/`Variables`, format specs after `|`, and currency codes in `TAFQEET`/`FORMAT`.
- Typed template variables (`<Var name type value format description/>`): `text` (may hold `{{ }}`), `number`, `boolean`, `date` (ISO, `today`, `now`), `list` (`;`-separated), and `expression`. Later variables can use earlier ones, host `variables:` still override, and the validator flags values that don't fit their type.
- `XlsxSheetBuilder.addChart` anchors a DrawingML chart part on a sheet.
- XLSX builder `style(rightToLeft:)` emits `readingOrder="2"`.
- `ReportCompleter.formats` exposes the format specs (with samples) that the designer offers as presets.
- XLSX and DOCX report exports: transparent text on a filled shape takes the shape's fill (white titles on a colored banner stay readable). XLSX chart placeholder rows get explicit heights, so the chart no longer overlaps its data table in LibreOffice.
- `tool/dump_report_shots.dart` renders every bundled template to PDF (and the sales dashboard to XLSX/DOCX through LibreOffice) for the README gallery.
- Limits are listed in `docs/STANDARDS.md`.

**PDF fidelity.** Five waves: OpenType marks, appearances, page graft, AcroForm write,
and a first slice of “files people send”.

- GPOS LookupType 4 (MarkToBase, including type-9 extensions). Combining
  marks use font anchors for `paintDx` / `paintDy`; the previous
  “center of advance” placement is the fallback.
- FreeText `/AP` (then Tx on fill) is a Form XObject through `LineBreaker`
  + Arabic shaping + a glyf Identity-H subset. Helvetica is not used for
  non-Latin text. `/NeedAppearances` stays if generation cannot embed a face.
- `PdfFile.appendPages` / `mergeFrom` rebuild via `PdfPageGraft`, so fonts
  and images survive. `PdfToolbox` remains the batch assembler.
- `pdf_widgets` `TextField` / `Checkbox` / `Radio` still draw marks. Pass
  `acroForm: true` (or use `ChoiceField`) to emit real `/Tx` `/Btn` `/Ch`
  fields on the writer `PdfDocument`.
- `/JBIG2Decode` decodes MMR generic regions (scanner dual-tone) with the
  same size cap as other filters. Arithmetic coding, symbol dictionaries,
  and JPX stay typed-unsupported placeholders.
- Signature fields: ByteRange coverage plus CMS `SignedData` `messageDigest`
  match (`valid` / `invalid`). Unknown digest algorithms are `unsupported`.
  Creating signatures and trusting a system root list are still out.

## 0.5.3

- High-value `pdf_widgets`: `PageNumber`, `HeaderFooter`, `SignatureLine`,
  `KeepTogether`, `Badge`, `Callout`, `Steps`, `DataGrid`, `Barcode` (Code128),
  `QrCode`, and `SvgImage` (path subset).
- Bilingual widget catalog via `pdf_widgets_samples.dart` /
  `example/pdf_widgets_catalog.dart`.
- Skip invisible BiDi marks (`LRE`/`PDF`/`LRM`/…) so `intl` dates do not
  paint as `.notdef` boxes.
- Reorder Arabic by grapheme cluster so tashkeel (ضمة on `أُنشئت`) stays
  on its letter after PDF export.

## 0.5.2

- Do not mid-cut Arabic chart axis labels (keeps joining forms intact).

## 0.5.1

- Soft-wrapped `Text` keeps the full max width so RTL `start` / `justify`
  paint on the start edge (headers, bullets, paragraphs).
- `TextAlign.justify` origins follow direction instead of always left.
- `Bullet` uses `TextAlign.start`. Chart titles follow direction; long axis
  labels are shortened to fit their slot.

## 0.5.0

**Report templates that look different, not only read different.**

- `pdf_templates.dart` ships **100+** classified report templates across
  commerce, finance, people, operations, narrative, data, education,
  property, logistics, and programs. Pick a named class
  (`InvoiceTemplate`, `PurchaseOrderTemplate`, …) and keep developing it.
- **`SheetSkin`** is the composition surface: invoice bar, receipt slip,
  letterhead, certificate frame, payslip split, checklist boxes, route
  endpoints, voucher, grades, identity panel, notice strip, journal,
  comparison columns, and more. Labels stay language. Direction stays
  layout. `TemplateTheme.copyWith` stays brand.
- `TemplateCatalog.all` / `inCategory` index every entry.
  `TemplateSuite.demo` writes a sample page. `joinTemplateFiles` joins
  English and Arabic into one PDF.
- `Table.fromTextArray` defaults to `AlignmentDirectional.topStart`, so
  Arabic table cells pin text to the start edge in RTL.
- `pdf_widgets` Flutter twins: `Transform`, clips, `FractionallySizedBox`,
  `IntrinsicHeight`, `CustomPaint`, `ListTile`, directional insets, and
  more. `TextOverflow.ellipsis` cuts a line.
- `OfficeColors.red` and other common names are `RRGGBB` strings for
  `OfficePalette` without touching Flutter `Colors`.

## 0.4.0

PDF is a file you can assemble, not only a file you can open or export.

- `PdfToolbox` grafts a new PDF 1.7 so fonts and images survive merge, extract,
  split, reorder, remove, reverse, insert, and mix. Range groups are
  1-based (`1-3`, `8-10`, `15`). One source may contribute several groups.
- `/Rotate` is a clockwise quarter-turn added to the existing value. It does
  not rewrite MediaBox. `PdfPageView` maps view space to unrotated crop space.
- Appearance overlays: Helvetica stamp, page numbers, Bates, and CropBox crop.
  Stamp is Latin only. A shaped watermark belongs on `pdf_widgets`.
- `pdf_widgets` watermark is one rotated string (ActualText + visual-order
  glyphs) so Arabic stays joined.
- Office slide export can stack two slides on one page (`slidesPerPage: 2`).
  The default remains one slide per page.
- `ArabicShaper.nominal` maps presentation forms back to isolated letters.
- Package documentation covers the full public surface, including honest
  limits (no OCR, no CMS verify, no certified PDF/A, no content-stream reflow).

## 0.3.1

- Keep `pdf_widgets` on its own library import
  (`package:quds_office_engine/pdf_widgets.dart`) so Flutter hosts do not see
  colliding `Text` / `TextStyle` / `Widget` names from the main barrel.

## 0.3.0

**Office + PDF in one pure-Dart engine.** This release makes PDF a first-class
citizen alongside DOCX / XLSX / PPTX — open, compose, and export without Flutter.

### PDF as a file (`PdfFile`)
- Open ISO 32000 packages: xref table/stream, object streams, incremental
  updates, filters (including CCITT G3/G4), encryption/password paths.
- Display list for page paint (`b`/`b*`, graphics state, Type 3, axial/radial
  shadings, OCG, SMask→RGBA, CMYK/ICCBased images).
- Text extract (WinAnsi / MacRoman / PDFDoc, Standard-14, `/ActualText`,
  `/StructTreeRoot` reading order).
- Typed honesty for signatures (`ByteRange` status), PDF/A detection (not
  certification), and unsupported codecs (JBIG2/JPX, in-engine CFF raster).

### PDF widgets (`pdf_widgets.dart`)
- Flutter-like constraint layout in pure Dart: `Document`, `Page` /
  `MultiPage`, `Table` / `TableBorder` / column widths, flex, text, media.
- Real bold faces via `Document.fontBold` (Type0 `/F3`), not faux stroke.
- Table cells expand to full width×row height (package:pdf-style fills).
- Synchronous `Document.save()` → native `PdfDocument` writer bytes.

### Office (unchanged strengths)
- Round-trip DOCX / XLSX / PPTX, formulas, BiDi/RTL, isolate open/save.
- `OfficePdfExport` still compiles Word / Excel / PowerPoint to PDF 1.7.

### Breaking
- Word widget DSL removed. Use `pdf_widgets` for PDF layout and
  `DocxDocumentBuilder` for DOCX.

## 0.2.0

- English package documentation, Word widget DSL (later removed), and
  PDF export polish.

## 0.1.0

- First public release: Office builders, models, formulas, BiDi, PDF export.
