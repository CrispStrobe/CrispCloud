## 0.1.0-dev.1

- Validate allocated compound directory names and exclusive ownership of stream
  and metadata sectors, with cached linear scans and requested-part validation.
  Reject negative caller-built stream sizes before aggregate read accounting.
- Preserve controls in nested cached field results while validating literal
  instructions separately; require exact story ownership and immediate parent
  ranges for all caller-built field models, including inactive fields.
- Reinspect actual EMF/WMF bytes before native image relationships, including
  textbox fills. Cache bounded validation and retain rejected raw images as
  inert evidence even when public metadata claims they are embeddable.
- Ignore restart fields on bullet/no-number levels and retain no-number literal
  labels and ancestor references in HTML. Explicitly reject literal binary
  `%1`–`%9` labels that the current native numbering model cannot represent.
- Reject UTF-16 scalars split across independent Word stories while retaining
  valid supplementary characters split across physical text pieces.
- Preserve field instruction TAB/CR/LF/CRLF exactly, including quoted literals,
  and retain nonbreaking/soft hyphens and column breaks in cached field metadata.
- Validate referenced compound allocation chains and declared table counts,
  including invalid tails beyond logical data. Cache immutable allocation
  snapshots and validated suffixes to bound repeated traversal; preserve legal
  spare capacity and partial final mini-container compatibility.
- Keep unsigned 64-bit byte helpers exact on VM and JavaScript through 2^53-1,
  reject unsupported integer values, and preserve full-width raw FILETIME paths.
- Apply declared WordDocument bounds and reserved-offset validation to the
  text-only API, and preserve column breaks as text separators.
- Keep nested field results at their original character positions, suppress
  private descendants, and verify caller-supplied field types against their
  actual instructions. Preserve formula fields with locked cached results.
- Preserve CFB stream identities with portable simple UTF-16 name comparison,
  and accept legacy version-3 uninitialized size high words while retaining
  version-4 and physical-container bounds.
- Bound aggregate ink inspection during conversion to 100,000 points and
  4,096 strokes, charging attempted work before allocation. Retain every raw
  payload and explicit limit diagnostics when inspection capacity is exhausted.

- Decode complete bounded nonempty ISF strokes using independent Windows WPF
  inputs: packet compression, pen attributes, qualified transforms and pressure
  metric prefixes. Preserve raw packets and source bytes, and keep native Word
  ink emission inactive until placement is independently established.
- Preserve editable textbox opacity, dashes, simple shadows, scaled gradients,
  embedded picture/texture fills and validated monochrome DIB patterns. Keep
  unknown effects and native tiling/secondary-alpha differences explicit.
- Couple the documented absent textbox line-width default to its qualified
  outer-frame conversion, preserving the missing source operand and keeping
  disabled, explicit zero and unresolved contexts distinct.
- Resolve the source built-in Line Number character style and its inheritance
  independently of note labels and source compatibility settings.
- Apply PICMID scale percentages with exact fractional-twip truncation after
  bounds checking; preserve source image bytes and avoid fabricated crop.
- Render a clearly labeled generated placeholder for an embedded OLE object
  without a source preview, retaining per-object identities, payloads and
  relationships in main, header and footer stories.

- Preserve corroborated occurrences of one shared header shape by source anchor
  CP, including native DOC re-exports. Keep each occurrence's geometry and
  wrapping flags and reject ambiguous payloads, links and revision histories.
- Distinguish textual tabs from tab-stop properties in semantic oracles, retain
  genuine boundary controls and use content-only revision/comment offsets.
- Recover corroborated single-frame textbox occurrences in normal and first
  headers while retaining real shape identities and a one-frame flow chain.
  Reject identity-bearing shared content and revision-bearing frame occurrences;
  preserve intentional blank paragraphs and diagnose every recovered alias.
- Preserve final-table footnote/endnote block sequences without synthesizing
  a trailing paragraph. Keep every source paragraph, including intentional
  blanks, and distinguish later native bridge additions from parser output.
- Preserve bounded solid-shape background-color context, independent OfficeArt
  group use bits and explicit layout-in-cell settings. Retain zero-count
  symmetric-curve editing hints without claiming native tangent editing.
- Exclude the documented textbox range separator while retaining empty content
  and intentional blank paragraphs in main and header stories. Require all
  fourteen boundary cases and the retained native shape input in the schema gate.
- Reconcile saved continuation branches and retain complete versioned RGB,
  structural, schema and repeated-native-import receipts. Build the independent
  Open XML SDK gate from pinned source/dependencies with exact output coverage.
- Preserve packed OfficeArt POINT arrays, verified Word position origins,
  textbox spare-range evidence, and narrowly validated native BLIP-store count
  recovery without relaxing record/image bounds.
- Preserve table mutations, indirect table properties, preferred cell-width
  units and raw/effective no-wrap state; keep grid geometry independent.
- Extend list counter transitions and 59 fixed note number formats, retaining
  explicit source codes, version gates, diagnosed fallback and unknown values.
- Emit supported row formatting history as native trPrChange, with prior height,
  split and header instructions checked through independent accept/reject
  controls; retain incomplete broader history and conditional-header formatting
  interactions as diagnosed evidence.
- Preserve bounded picture-frame flips, absolute floating quarter turns, direct
  outlines and simple offset shadows. Retain independent authored controls and
  the remaining default-PDF image-encoding difference.
- Add independent structural, accepted/rejected-text and native rendering
  oracles, pinned Office fixtures, textbox resize probes and PDF-vector shape
  checks. Keep producer round-trip losses separate from parser losses.
- Preserve unequal columns, paragraph pagination flags, note numbering and
  placement, line-number skip counts, section revision history, nested tables,
  row origins and supported list continuation.
- Add bounded native table-style inheritance and all twelve conditional cell
  regions, direct cell borders and padding, with explicit source defaults.
- Emit editable bounded OfficeArt rectangles, ellipses, lines and custom
  paths; keep unsupported effects diagnosed. Preserve native EMF/WMF payloads
  and produce bounded previews for supported vector records.
- Retain comment-thread relationships, paragraph-mark and property revisions,
  and supported numbering history without accepting or rejecting edits.
- Extract the bounded DOC/DOT parser and structured document model from
  CrispCloud as a Flutter-independent Dart package under MPL-2.0.
- Retain MIT compound-file and 0BSD JSDoc provenance notices.
- Preserve main-story formatting, basic tables, section geometry and supported
  tracked insertions/deletions, with explicit partial-support diagnostics.
- Add referenced headers/footers, footnotes/endnotes, comment metadata, bookmarks,
  nested fields, list definitions, and linked textbox stories to the typed model.
- Add custom/default tab stops, paragraph borders, paragraph/table-cell shading,
  and exact underline variants, including bounded binary property handling.
- Add a Flutter-independent DOCX/DOCM OPC writer using `archive`, with actual
  document parts and relationships for supported content. Retain the existing
  structured DOCX and explicit text-only conversion entry points.
- Retain referenced PNG/JPEG/TIFF images, crop and supported floating positions;
  preserve hidden/revision presentation and keep deleted shapes inactive.
- Preserve eligible embedded OLE and structurally complete explicit-DOCM VBA
  projects with compound-storage metadata and exact raw FILETIME bytes. DOCX
  output remains free of active VBA relationships.
- Retain unsupported content and original signatures as inert evidence with a
  manifest. Never activate copied signatures or claim signature validity.
- Keep hidden/private note/comment content out of active output references;
  lock supported fields, retain cached results, and avoid external resources.
- Add standalone parser/writer regression suites, a runnable file-copy example,
  detailed preservation contracts, and offline JavaScript/Node acceptance using
  an authored DOC plus OLE/VBA metadata fixtures.
- Host development at https://github.com/CrispStrobe/legacy-doc-parser.
