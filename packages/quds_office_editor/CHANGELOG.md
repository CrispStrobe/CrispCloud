# Changelog

All notable changes to `quds_office_editor` are documented here.

## Unreleased

- Remember up to 20 native IMAP/SMTP accounts in a bounded platform-keychain
  catalog. Restore the selected account, choose another account explicitly,
  and forget only that account. Migrate the previous single-account record
  without losing credentials or resurrecting a forgotten account. Switch
  connected accounts only after saving their retained local draft, preserving
  existing per-account draft ownership and delayed-operation guards.

- Insert Zotero research notes and annotations at the active authored footnote
  or endnote caret, and replace deliberate text selections within one paragraph.
  Keep native citations in their owning note, preserve the note number and
  surrounding content, and restore the original selection with one undo.
  Refuse stale, composing, structural and protected targets before application.

- Render presentation normal-autofit line-spacing reduction consistently,
  including fully collapsed line advances, while retaining glyph extents and
  excluding authored fixed-point spacing from percentage reduction.

- Import nested and multiparagraph Zotero note/annotation lists through the
  existing native commands. Preserve citation order, surrounding prose, native
  numbering, and a single undo/redo step; refuse stale targets and excessive
  nesting before changing the document.

- Support embedded research-note pictures and Zotero image/ink annotations in
  the existing native Add Note and Add Annotation controls. Images, active
  citations, notes and preferences apply together as one undo step, with stale
  target and cancellation guards. Verify actual editor image painting and
  repeated DOCX save/reopen with undo/redo.

- Remove inherited selected gradients from the slide canvas immediately after
  a master background edit, preserving local fills and background ownership.

- Render distinct pentagon and home-plate silhouettes while retaining chevron
  geometry. Keep the Studio Mail theme's button height with a finite minimum
  width so PDF organization controls can lay out in both light and dark themes.

- Share foreground mailbox navigation across IMAP/SMTP, EWS, Gmail and
  Microsoft 365: search loaded subjects/senders, combine Unread and Flagged
  filters, use keyboard navigation and preserve selection through compact
  reader/Back transitions. Load explicit pages up to a 1,000-message ceiling,
  reject invalid or cyclic continuations, and add confirmed IMAP read/unread
  and flag/unflag controls while preserving independent unknown observations.
  Browse large and sparse IMAP folders newest UID first within existing quotas.

- Autosave one local Studio Mail draft per account across SMTP, EWS, Gmail and
  Microsoft 365. Restore incomplete recipients, reply headers and attachment
  snapshots after reconnect; flush close/send, expose storage failure and an
  explicit unsaved exit, and preserve interrupted-send warnings across restart.
  Persist the send boundary before transport and clear accepted/discarded drafts
  transactionally, retaining guarded content when acceptance cleanup fails.

- Render imported linear slide gradients across the full shape, including
  narrow vertical fills. Apply picture transparency once and draw one soft
  picture shadow while preserving existing inherited-background behavior.


- Add outgoing file attachments to native Studio Mail with immutable byte
  snapshots, all-or-none cancellable selection, ten-file/10 MiB limits and
  localized size/removal controls. Preserve attachments through uncertain
  retries and send ASCII-safe multipart MIME with exact base64 payloads.
- Add explicit Mail attachment selection and removal, with immutable draft
  snapshots, cancellable bounded file reads, a ten-file/10 MiB total limit,
  and mixed MIME submission through the existing providers. Preserve attachment
  bytes and Unicode filenames through explicit uncertain-send retries.
- Inspect a catalog reference's child notes and attachment metadata through
  **Reference details → Notes and attachments**. Add paginated browsing,
  bounded inert note previews and copying, explicit retry and library-version
  restart, and guards for changed connections. Preserve selection/search drafts
  and read-only document history; desktop children retain the parent response's
  database identity and require Zotero 10 or later.
- Preserve inherited slide decorations independently of slide animation IDs,
  retain hidden-master flags and visible layout decorations through save/reopen,
  and include decoration backing in dark-display text contrast. Integrate block
  arrows, symbol/emoji fallback and flipped connectors while retaining imported
  rich-text edits and anchored hit testing. Keep connector direction through
  geometry editing, clipboard operations, morphs and slide duplication.

- Keep painting and caret hit testing aligned for anchored slide text, apply
  current scalar formatting to imported rich text, and preserve inherited
  backgrounds and the established 16-point fallback.

- Add bounded multiple To recipients, Cc, Bcc and Reply all to native Studio
  mail. Keep hidden recipients in the explicit envelope, preserve all groups
  through uncertain retries, and reject unsupported decoded reply addresses.
- Preserve explicit white slide and layout fills while adapting inherited
  neutral paper to the display theme; retain the document-color opt-out.

- Retain slide theme inheritance and the native 16-point text default when
  rendering imported rich text. Honor scalar text formatting and paragraph
  font fallbacks while preserving authored color contrast in dark displays.

- Add a searchable Zotero tag browser with paginated results, staged filters,
  exact-name validation and selection across searches. Applying filters retains
  selected sources and unfinished input, and restarts the submitted reference
  search; cancellation and stale connections preserve the existing filters.
- Navigate from a cited source to its distinct citation fields, with cached
  text and body/note location labels. Preserve source identity aliases and
  read-only document state, retain source-picker drafts on Back, and reject
  changed destinations before moving the caret.

- Preserve validated reply-thread identifiers through native Studio composition
  and explicit uncertain-send retries. Emit bounded In-Reply-To/References
  headers, keep forwards independent, and omit unsupported or unsafe IDs.

- Add a Page Layout dialog for numeric paper, margins, header/footer distances,
  equal columns and section options. Apply validated drafts as one undo step,
  preserve imported section properties, and reject stale document targets.
- Consolidate Layout, equation, function, shape and motion presets into menus
  with selected-value feedback. Add a precise Paragraph dialog with mixed-value
  preservation, unit-aware spacing and indentation, and one-step Undo.
- Move document interaction choices to File/View as Edit document, Read and
  copy, and Preview only; theme Material dialogs, menus and fields with the
  selected appearance. Show explicit slide timing choices and disable their
  mutations in read-only modes.

- Make Insert commands compact and configurable, save ribbon layout preferences,
  simplify the title bar, and provide desktop File menus and native macOS window
  controls. Use CrispOffice for the default reviewer and newly created comments.
- Route inserted tables, pictures and diagrams through document undo history.
  Protect New, Open, Close and Quit with save confirmation, keep Save As paths
  unchanged on cancellation/failure, and preserve edits made during saving.
- Add PDF save-state revisions and repeatable snapshot encoding so a successful
  save can mark the document clean without clearing undo or mutating live PDF
  object identifiers while writing.
- Make dark document ink, rulers and measurement readouts readable while
  respecting filled cells and highlights and preserving authored export colors.

- Add native Studio bulk export for all matching archive results and explicit
  resume of an existing export directory. Freeze the selection and provenance,
  verify exact originals, preserve conflicts and report each run's written,
  existing and failed counts with cancellation and EN/DE/AR feedback.
- Add native directory import with optional recursion, explicit MBOX dialect,
  bounded traversal/parsing and relative-folder provenance. Recheck source
  files, preserve them unchanged, skip recognized export staging and distinguish
  completed, partial, limited and cancelled outcomes. Generic EML reimport does
  not restore exported manifest provenance, profiles or saved searches.

- Add a native Mail archive with EML/streamed MBOX import, connected-message and
  selected-folder collection, local FTS search and filters, saved searches,
  exact-original EML export, integrity checks and index rebuilding. Include
  EN/DE/AR controls, narrow layouts, cancellation and opt-in redacted diagnostics.
  Explicit archived copies survive account disconnection and cache removal.
- Add Gmail and Microsoft 365 / Outlook browser sign-in to native Studio Mail,
  reusing the guarded mailbox reader/actions/composer. Include session cleanup,
  optional redacted diagnostics and localized permission/throttle feedback.
- Add Yahoo, iCloud and Fastmail presets with official TLS endpoints, app-password
  guidance and primary-login/iCloud fallback settings.
- Add a native Studio Exchange Server (EWS) account window with explicit HTTPS
  configuration, NTLMv2 by default and optional Basic authentication. Browse
  folders and bounded message pages, read MIME bodies and attachment details,
  change read/flag state, move messages and use Deleted Items. Compose, reply and
  forward through EWS with explicit uncertainty acknowledgement before retry.
  This foreground host clears credentials, transient downloaded messages and
  retained drafts on disconnect or close; explicit archived copies are kept
  separately. It does not provide a durable outbox.
- Restore Studio's saved EML reader alongside native Mail accounts, preserving
  original message bytes, full/compact reading and safe delayed file selection.
  Keep native account transports outside the browser Mail entry and use a
  mailbox list/detail layout on narrow windows.
- Fetch selected native messages through the bounded Quds IMAP provider with
  mailbox/UIDVALIDITY/UID checks. Reject insecure-origin account discovery and
  contain server diagnostics at the Studio boundary.
- Use the Word RenderBox surface for plain-text Mail composition. Validate one
  recipient and headers, encode non-ASCII MIME safely, separate SMTP submission
  from Sent-folder filing, and retain unconfirmed drafts with an explicit
  acknowledgement before another attempt. Keep confirmed acceptance final when
  subsequent cleanup fails, and independently abort both owned transports when
  releasing a session. This remains a foreground,
  session-only host; durable outbox and real-provider qualification are separate.
- Retain incoming reply, text-only forward and mark-read actions. Quote the
  loaded plain-text body with Unicode-safe truncation, protect uncertain drafts
  from replacement, and verify read flags through the bounded UID provider
  before updating the foreground message. Explicit draft discard does not cancel
  an already submitted message.

- Add **Add Zotero annotation** to the native Word ribbon and **Add annotation
  from Zotero…** to the references workspace. Text annotations and their active
  citations insert as one undoable operation and return focus to writing.
- Apply the research-note caret, composition and stale-target guards to
  annotation insertion. Cancelling the picker discards staged preferences and
  temporary fields; image/ink annotations remain explicitly unsupported.

- Preserve the active Notes editor, selection and composition when opening,
  closing or resizing the Review pane so language and checking actions keep
  targeting the selected footnote or endnote text.

- Keep imported Zotero research-note lists and their numbering definitions in
  the same undo step as the note and its citations. Restore existing numbering
  on undo while preserving unrelated package parts and relationships.

- Keep Notes keyboard Undo/Redo in document history, preserve tracked correction
  records, and prevent Redo from overwriting newly typed Notes drafts.
- Apply language and checking controls to the exact Notes selection or current
  editable paragraph, including multiline and UTF-16 ranges. Retain the actual
  Notes field and selection when opening or repositioning the Writing pane.
- Retain completed manual proofing coverage, including clean results, across
  recording unchanged Notes typing into history without rerunning providers.
- Keep header/footer selections out of unrelated body table highlighting and
  ruler bounds.

- Add inline Notes spelling, grammar and style underlines with nearby
  correction, ignore/dictionary and finding-navigation controls. Keep live-check
  status and explicit checking in the pane; F7 checks and Alt+F7 /
  Alt+Shift+F7 navigate the active note's findings.
- Route Notes review to the persistent Changes pane. Reveal findings and
  supported revisions at the actual footnote/endnote text selection, preserving
  hidden reference offsets, composition guards and correction Undo ownership.
- Edit and reveal the exact rendered default, first-page or even-page
  header/footer story. Keep its caret, selection, IME, language controls and
  proofing priority together; paint selection and chrome below readable text.

- Add **Add Zotero note** to the native references tools and Studio ribbon,
  with complete insertion/undo and DOCX persistence of active citation fields.
- Return direct Zotero ribbon/keyboard commands to the body or Notes caret after
  completion or cancellation. Keep failures reviewable and retain the ordinary
  references workspace for browsing, including in Studio viewing mode.
- Add **Go to reference** for citations and complete bibliographies in body,
  table and Notes paragraphs. Read-only selection remains available without
  changing document history; note navigation reveals and focuses the target.

- Keep Shift+F7 available from both the document and the Review pane alongside
  Alt+F7 / Alt+Shift+F7 writing navigation. Keep language, changes and thesaurus
  actions within the narrow review status bar.
- Refuse thesaurus presentation during active IME composition before opening a
  modal or restoring focus, including when a menu supplies an earlier capture.
  Show a non-focus-taking notice when the host provides a Scaffold.

- Review current writing findings with Alt+F7 / Alt+Shift+F7 and use
  Shift+F10 / Menu for keyboard-operated suggestions at the caret. Preserve
  selections, adjacent finding boundaries, IME composition, and document focus
  on dismissal; repeated navigation from the pane respects its category filter.
- Keep Check document available during background checking, while repeated
  explicit requests share their existing pass and retain manual-provider rules.
- Keep Studio comment replies inline with separate thread drafts and explicit
  undoable posting. Prevent stale drafts from being attached to another thread
  or replacement document; show comments below the editor in narrow windows.
  Display live findings in the active comment body and open its Writing review
  from marked text without disrupting selection gestures.

- Preserve verified findings in unchanged paragraphs during typing and checking,
  publish new findings progressively, and keep current inline suggestions usable
  during unrelated progress. Reject stale sources and preserve explicit/manual
  checking boundaries and request coalescing.
- Add author/type/text filters, exact filtered batch Accept/Reject, and
  markup/final/original paragraph previews to the persistent Changes pane.
  Keep filters collapsible, verify source attachment, support protected text
  inspection, and advance to the next pending change with Undo/Redo.
- Add document-language selection and restoring ignored findings directly to the
  Writing pane, preserving personal dictionary entries and run languages.
  F7 works from pane controls as well as the document.
- Search and reuse cited Zotero document references offline, with stored details,
  occurrence counts, shared selection review and fresh citation options. Preserve
  mixed-library identities, explicit URI aliases and distinct offline snapshots.
- Add, remove and reorder sources while composing or editing a Zotero citation.
  Keep per-occurrence options attached and require review of custom text after
  source-list changes. Preview the current single source and preserve drafts on
  cancellation or preview failure.

- Add live writing checks by default in the shared Word editor, preserving an
  explicit off preference. Show debounce, active, paused and incomplete check
  status alongside a count of pending tracked changes.
- Keep Writing and Changes review panes open while editing, with responsive
  placement, finding/category navigation, suggestions, dictionary/ignore actions,
  reviewer attribution and undoable tracked-change decisions. Preserve advanced
  dialogs for detailed settings and two-document comparison.
- Offer suggestions directly from marked text and tracked-change actions from
  its context menu. Preserve input focus, double-click/drag selection and checked
  results during caret/viewport movement; reject stale source actions.
- Keep manual providers behind explicit F7/Check document requests and reuse an
  identical active explicit check. Export pane/status widgets and controller
  navigation APIs for embedders.

- Inspect and copy stored reference details from CSL import results and staged
  selection review, including full titles, creator roles, bibliographic fields
  and source identities. Keep offline and mixed-library selections unchanged.
- Explain the 20-source citation limit when another imported reference cannot
  be selected, including when selected sources are hidden by a filter.

- Search imported Zotero CSL references locally by title, creators, year and
  DOI, with creator/year labels, result counts and selections retained across
  filters. Preserve original import identities even when IDs or titles repeat.
- Copy selected stored CSL JSON offline or across libraries from Library and
  Import. Retain selection order, repeated records, embedded metadata and URI
  aliases without changing the document or requesting updated source data.
- Keep Zotero import controls, Library content and complete status/error
  messages usable in narrow windows with enlarged text.

- Protect complete identifiers and numeric/connector-containing spans returned
  by native spell checkers, including marked and prepended Unicode clusters.
  Keep surrounding prose, explicit hyphen parts and CJK words reviewable.

- Add a document review workspace with reviewer attribution, author/type/text
  filters, undoable filtered accept/reject, story-aware navigation, and
  original/final paragraph previews. Compare two independently picked Word
  documents with side-by-side or inline differences and export JSON reports.
- Replace the mutating controller comparison helper with a read-only result;
  preserve source documents, mark stale reports, and support narrow LTR/RTL
  review layouts and viewing mode.
- Reject incomplete or foreign Word document XML before comparison, so damaged
  sources cannot silently import as empty documents and appear unchanged.

- Keep exact reviewed macOS pixel references separate from Linux references.

- Check native spelling without discretionary soft hyphens while keeping exact
  original UTF-16 finding ranges and undoable corrections. Preserve authored
  layout outside corrections, reject layout-only suggestions, and keep links,
  code, marked identifiers and grapheme clusters protected after projection.
- Add read-only Zotero reference details and plain-text copying, plus exact tag
  filtering directly from loaded metadata. Preserve search drafts and selected
  sources, and explain tags that cannot be filtered literally.
- Add staged selection review in Library and CSL import: inspect sources across
  pages, remove individual references and arrange citation order. Apply or cancel
  without changing document history; retain original source keys and metadata.

- Keep native spelling shortlists useful by filtering blank, unchanged,
  duplicate and malformed replacements before the eight-suggestion limit.
  Preserve multiword and Unicode corrections, keep unknown words reviewable
  without a replacement, and protect numeric/connector identifier fragments.

- Add removable Zotero tag filters with an active-count indicator, inline input
  validation and a bounded chip list for narrow windows. Adding, removing and
  clearing tags preserve the last submitted query and selected sources; draft
  query/tag text never changes pagination. Retain filters across catalog scopes
  and reconnecting within the current dialog.

- Coordinate system spell checks across documents using Flutter's shared native
  channel. Bound active and queued callers, settle disposal promptly, and keep
  unfinished OS calls from colliding with a replacement provider.
- Preserve representable scripts and numeric locale regions without silently
  dropping dictionary variants; exclude URLs, emails and code from platform
  findings and reject ranges that cut Unicode graphemes.

- Add reference-browser controls for full-text search, reference type, sort field
  and direction. Keep paging bound to the submitted search while a new query is
  being typed, preserve selected sources, and keep controls usable in narrow
  windows and after reconnecting.
- Resolve document-declared transitive Zotero URI aliases during basic citation
  refresh and API bibliography preparation. Older local links can use an explicit
  synced alias without rewriting citation identities, locators, affixes or unknown
  metadata. Keep unrelated libraries separate and apply refresh as one undo step.

- Add an optional manual proofing service for preloaded grammar providers. F7
  and explicit checks include it; typing checks skip it with explicit coverage,
  keep separate caches, and preserve deterministic findings on overlap.
- Show a readable name for the German noun-case rule in ignored checks, using
  the existing review and undoable correction flow for broader noun morphology.
- Report omitted manual-model coverage only for applicable document languages,
  so a de-DE-only manual provider does not mark an English check incomplete.

- Expose a readable seit/seid rule name in ignored checks. Verify new German
  agreement and soft-hyphen corrections through the real review dialog,
  including exact source restoration on undo.

- Expose the optional Harper provider's Canadian, Australian and Indian English
  choices alongside US/UK English and German regions. Share the example host's
  language-scoped personal vocabulary with its English provider.
- Explain automatic hyphenation's German/US/UK language scope in the review
  dialog. Authored discretionary hyphens remain available in every language.

- Identify embedded PDF fonts by their full bytes instead of sampled positions,
  keeping owned immutable snapshots and bounded content-deduplication storage.
  Reuse font associations during painting without repeatedly hashing a face.
- Notify every waiting PDF canvas/thumbnail when a shared font finishes loading,
  keep failures terminal for the buffer, and clean up listeners on disposal.
  Repaint on reattachment so moved retained layers cannot freeze fallback text.

- Label invisible proofing replacements, including space insertions. Restore
  ignored words in their original language, rules and ignored occurrences
  from the review dialog without changing source text or undo history.

- Measure complete Word text runs with Flutter's shaping before wrapping,
  including contextual kerning, Arabic and grapheme advances. Cache immutable
  metrics with bounded storage and invalidate them after font registration.
- Recheck the shaped width of each painted line fragment so trimmed spaces
  and changed joining/kerning context cannot silently overflow narrow table
  cells or variable-width text bands around floating frames.
- Preserve Unicode grapheme slices and styled combining-mark ownership, keep
  nested bidi embeddings in separate paint runs, and dispose temporary native
  text painters after fitting, caret/hit testing and document painting.
- Retain invisible source controls across long paint-run gaps so caret and hit
  testing keep their authored UTF-16 offsets; exclude visible text owned by
  another sparse run regardless of gap length.
- Include full OFL notices and recorded provenance for the existing Liberation
  2.1.5 and Noto Naskh Arabic 2.004 font assets; font binaries are unchanged.

- Keep Zotero collection pages unique by key, replacing renamed metadata while
  preserving order, the selected collection and selected references. Discard
  collection continuation responses after the library or dialog has changed.

- Refresh basic Zotero citations with up to 1,000 distinct linked sources in
  sequential batches of at most 50 per library. Keep all fetched metadata
  staged until every batch succeeds and the document target remains current,
  then apply the complete refresh as one undo step. Reject oversized requests
  before contacting Zotero; formatted bibliographies retain their 50-source
  single-request limit.

- Make native Zotero catalog insertion the primary desktop action and open the
  document style chooser automatically when needed. Show the saved native
  style, language and placement. Commit the style and citation together as one
  undo step; keep the document and selected sources on cancellation or failure.
- Preserve mixed citation styling while protecting the complete linked field
  during editing and clipboard operations. Display footnote/endnote sequence
  labels consistently in the canvas, note bodies and Notes pane.

- Add native Zotero source-picker, document-style, bibliography and complete
  document-refresh controls, including catalog-seeded insertion. Apply staged
  results as one undo step with note/preferences restoration and stale-target
  guards. Review unsupported character styles and bibliography layout before
  applying simplifications; discard staged changes on desktop error alerts.
  Preserve the original selection on undo and place the caret after new fields.
  Full native app and live Zotero/Word acceptance remain pending.

- Resolve unsynced local Zotero references through the matching desktop
  connection for basic refresh, individual previews, reference export and
  formatted bibliography. Keep local profile identities distinct, validate
  connected sources before requests, preserve original citation metadata, and
  deduplicate URI aliases in the offline bibliography.

- Offer explicit online/desktop library selection in native hosts. Browse and
  cite local Zotero sources without an API key, preserve unsynced CSL links,
  and label sources without persistent identities as offline embedded records.
  Studio uses a direct loopback client; hosts opt in via `localTransport`.

- Add a shared Zotero references workspace: personal/group libraries, collection
  browsing and search, paged results, linked citation clusters, source locators,
  offline CSL JSON import/export, and complete selected-library bibliographies.
  Hosts inject their network transport and may use their existing secure key
  store. Citation editing, refresh and unlink participate in undo/redo and save
  revisions; asynchronous writes reject a changed document or caret. Basic
  author-year formatting remains an explicit fallback when native Zotero is
  unavailable. Rich/unsupported native fields remain preserved.

- Paint matching conditional-format fills and font colours in the sheet grid,
  hide hidden rows/columns, and start on the first visible worksheet. Hidden
  worksheet tabs are filtered by the host selector; the model and serializer
  retain their state through XLSX saves.

- Preserve explicit spreadsheet font-color intent through undo/redo and cell
  snapshots. Setting the currently resolved theme color creates a direct color;
  undoing that edit restores the native theme binding.

- Make Word protection changes undoable and revision-tracked. Host configuration
  updates retain native document restrictions, and protection history can undo
  its own read-only transition without allowing ordinary document edits.
  Password-protected imports cannot be unprotected without verification;
  comments/forms/tracked-only restrictions remain conservatively read-only.
  Loading another Word document clears history belonging to the previous one.

- Expose worksheet renaming through shared atomic reference rewriting and one
  undo/redo command. Commit pending drafts before planning, retain later edits
  through save/undo, and keep read-only, unchanged and rejected operations out
  of history and dirty-state changes.

- Route slide reordering through the shared section-aware plan. Undo/redo keep
  native section identities, empty sections and active-slide identity; invalid
  memberships reject before history or dirty-state changes.

- Paint explicit native Word frame outline widths, preset/custom dashes, caps,
  joins and inset alignment. Keep selection chrome separate from the document
  stroke. New frames preview their serialized one-point outline; imported
  omitted widths retain the existing approximation. Native pixel regressions
  and three reviewed outline-only golden corrections cover repeated saves.

- Commit active Word, Sheet and Slide drafts through `commitPendingEdits()`
  and both save APIs. Cell and slide text changes advance the content revision
  immediately, including edits during an asynchronous save; focus, caret and
  unchanged text stay clean. Cancel restores the draft without clearing other
  unsaved changes, and committed drafts remain undoable.

- Expose a content revision that advances immediately for pending note-pane
  edits as well as commands and history. Saves commit pending note edits before
  encoding so hosts can guard asynchronous completion against a later edit.

- Preserve native bookmark endpoints through run formatting, paragraph splits,
  inside-range edits, native clipboard insertion and undo/redo. Invalid partial
  range copies and duplicated native identities reject on export rather than
  losing markup; three actual editor exports are checked independently.

- Word, Sheet and Slide canvases dispose decoded images and suppress late
  callbacks after close. Two deterministic cache lifecycle regressions cover
  pending and ready image disposal.

- Native block content controls keep their metadata through inside edits,
  paragraph splitting, undo/redo and repeated saves. Splitting an inline-only
  control is rejected before changing the document or undo history.

- Toggling off an imported list suppresses style-based numbering through
  undo/redo and save/reopen; toggling it back on restores a list normally.

- Splitting a heading or a restarted list retains the first paragraph's anchor
  and restart without duplicating them on the new paragraph, including undo/redo.

- Relayout a replaced Word viewport so scrolling to later pages does not leave
  an empty canvas. Three reviewed page goldens cover first, even and default
  header/footer pictures before and after an asynchronous save.

- Fix the feature-showcase template detail band so its item table fits.
- Selection highlighting is visible on white pages.
- Header and footer edits force a full relayout so typed text lands in the
  correct band.

## 1.6.0

Built on `quds_office_engine` 1.5.0 and `quds_reports` 1.5.0.

- The report toolbox adds a section, a crosstab, and a subreport. The
  inspector edits their fields. Variables have "ask before preview" and
  "required".
- Ctrl+B toggles bold on the selected run of a rich paragraph.
- Bundled Liberation faces include italic and bold italic, and an embedded
  family stores those two slots beside regular and bold.
- The Excel formula bar shows the selection address or the matching defined
  name, and choosing that name selects its range.
- Word revisions draw a translucent mark in addition to the underline or
  strike.
- Ready-made templates add the sales order family, Arabic and English.

## 1.5.0

Built on `quds_office_engine` 1.4.0 and `quds_reports` 1.4.0.

- `package:quds_office_editor/quds_reports.dart` is the report designer and
  the report engine in one import: canvas, inspector, toolbox, preview, data
  explorer, bundled fonts, ready-made templates, and `QudsReportEngine`.

## 1.4.0

Built on `quds_office_engine` 1.4.0.

- Insert tools live in a side toolbox. Each tool shows a hover card with its
  name, a short description, and a small drawing. The map is its own tool.
- A shape map's choices are dropdowns. Region labels ask which field to draw,
  including calculated and constant columns from the shape table. A long menu
  scrolls, and typing filters it.
- Title, region labels, and the legend each have a format button. It opens a
  box for family, size, bold, italic, and color.
- The data explorer edits an imported shape layer as a table, so a calculated
  column can be the region's label. An imported shape file can be removed.

## 1.3.0

Built on `quds_office_engine` 1.3.0.

- The chart inspector lists the new types (including the scatter chart) and
  the plot controls that apply to the selected type: depth and skew for
  extruded charts, hole and start angle for pies and gauges, markers and
  curves for lines, axis bounds, a target and bands for gauges and bullets,
  and per-series style, secondary axis, X, and size.
- Bundled templates include a chart gallery (`chart_gallery_ar` and
  `chart_gallery_en`) with every chart type and a country shape map bound
  to its own `countries` table.
- A shape map chooses the world atlas or an imported shapefile, GeoJSON, or
  `.qmap`. **Import shapes…** embeds the file in the `.qrep` and points the
  region key at the table column that matches it (a district code, for
  example). The inspector also sets the low, high, and empty colors and
  whether wide regions are labeled.
- Calculated columns stay in their table. A formula in that table can name a
  sibling column directly (`price`) as well as `item.price`.

## 1.2.0

Built on `quds_office_engine` 1.2.0.

- Bundled templates include class certificates (`class_certificate_ar` and
  `class_certificate_en`). This is the report form of a mail merge: the
  Detail band is bound to the `students` table with **New page before**, so
  preview and export show one certificate page per student. The sample class
  has eight students.

## 1.1.0

Built on `quds_office_engine` 1.1.0.

- Two-finger zoom on the design canvas and the preview: a trackpad pinch or
  two fingers on a touch screen zoom around the point between the fingers.
- Problems panel. `ReportDesignerController.problemsOpen` shows it under
  the canvas (`QudsReportDesigner.problemsHeight`, drag to resize). It lists
  `controller.problems`: live parser and `validate()` findings, errors
  first, with each problem's kind, place, and a hint on how to fix it.
  Clicking a problem calls `revealDiagnostic`, which selects the element or
  band and scrolls the canvas to it, or opens the variable or data column,
  and marks the inspector property to fix (`highlightProperty`).
  `ReportProblemsPanel` is exported. `clearLoadDiagnostics` forgets what
  the parser corrected when the file was opened. Diagnostic messages are
  translated (`ReportDesignerStrings.diagnostic`).
- The 16 ready-made report templates ship as `.qrep` files in `templates/`
  (package assets). `ReportTemplateLibrary.bundled()` reads them in menu
  order. `QudsReportDesigner.templates` is now nullable, and null (the new
  default) offers the bundled files. `loadTemplate` loads a template's
  embedded fonts too.
- Embedded images can be replaced. Click a thumbnail on the inspector's
  Images tab, or use **Replace image…** on an image element. The image keeps
  its name, so every element showing it updates on the report at once
  (`ReportDesignerController.replaceImage`, `importReplacement`; undoable).
- `ReportDesignerController.fromXml`, `loadXml`, and `loadPackage` open a
  template that has expression errors instead of throwing, and list the
  errors in the new `loadDiagnostics`. A report saved with a typo, such as a
  variable `{{sum(item.qty}}`, can be reopened and fixed. They still throw
  `ReportTemplateException` when the XML can't be read.
- The report inspector has been redesigned:
  - Actions are icon buttons with tooltips instead of text rows.
  - The Variables tab is an explorer. Dotted names (`stats.sum`) appear as
    folders you can collapse, and the selected variable is edited below the
    tree (`selectedVariablePath`, `variableFolders`).
  - Images appear as cards with a thumbnail.
  - Embedded fonts appear as cards with a live preview, a default star, and a
    remove button.
  - Every font field opens a picker of installed fonts. It previews each font
    in its own script (Arabic, Thai, and so on), and choosing a font embeds
    it. Hosts report scripts through the new `ReportDeviceFontScripts`
    interface. `fontPreviewText` gives the sample text.
- The designer can be localized. `ReportDesignerStrings` ships English and
  Arabic. Pass it as `QudsReportDesigner.strings`, or let the designer follow
  the app's locale. In Arabic, the inspector, data explorer, menus, and status
  messages are mirrored right to left.
- `QudsReportDesigner.onPrint` adds a **Print** toolbar button and Ctrl+P.
  It hands the host the report as PDF, rendered with the preview data, so the
  host can show a print dialog. Adds `ReportToolbarIcon.print`.
- Dark `OfficeTheme`s are supported. The page stays white, while the
  inspector, data explorer, popups, and canvas grid use colors that suit the
  dark chrome.

## 1.0.0

First stable release, built on `quds_office_engine` 1.0.0. The public API
now follows semantic versioning: breaking changes wait for 2.0. This release
brings the report designer's data explorer, embedded images and fonts,
inspector tabs, and fidelity fixes for Word, Excel, and PowerPoint files.

- Depends on `quds_office_engine: ^1.0.0`.

**Calculated columns in report suggestions.**

- The report designer's `{{ }}` and expression suggestions (text, properties, variables) use the sample data as the report sees it: schema types applied and calculated columns filled in.
  - A new calculated column such as `calc1` is offered right away, with its computed value.

**Word, Excel and PowerPoint fidelity fixes ([#2](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/2), [#3](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/3), [#4](https://github.com/MohammedAsaadAsaad/quds_office_suite/issues/4)).**

- Word:
  - The Word controllers lay out with the same Flutter text metrics they paint with (`PaintRunText.advanceOf`), so lines no longer run past the column.
  - Layout runs again when system fonts change.
  - `WordEditorController.refreshMetrics()` re-measures on demand.
- Slides:
  - `QudsSlideEditor` now places `navigationBuilder` (a 220-pt pane shown when `showNavigationPane` allows it) and `notesPaneBuilder`; both were ignored.
  - An empty `PmlShape.fillColor` paints no fill instead of the `4472C4` fallback.
    - Text on unfilled shapes contrasts with the slide background.
    - Empty placeholders get a faint outline while editing.
  - The stage honors `PmlShape.textColor`.
  - Text boxes shorter than a line (`cy="0"`) grow with their text instead of being clipped away.

**Embedded report images in `.qrep` packages.**

- Packages:
  - `ReportDesignerController.fromPackage`, `loadPackage` and `toPackage` read and write the zipped `.qrep` (layout + images).
  - Legacy plain-XML files still open.
- Images:
  - `addImage`, `insertImage`, `renameImage` (repoints `<Image source>`), `removeImage` and `imageNames`.
  - Image edits are part of the undo history.
  - Loading or replacing a template now replaces `images` too.
- `QudsReportDesigner.onPickImage` (`ReportImagePicker`) turns on the import buttons:
  - The inspector's **Images** tab lists name, type, pixel size and file size, with Insert / Remove.
  - Image elements get an **Import image…** button, and their Source field suggests the embedded names.
  - Files that are not PNG / JPEG are reported in the status bar.

**Inspector tabs and resizing.**

- Tabs:
  - The inspector has **Properties**, **Variables** and **Images** tabs (`ReportInspectorPage`, `controller.inspectorPage`), with count badges.
  - Variables and images no longer crowd report settings.
  - Selecting an element or a band returns to Properties.
  - Variable edits apply even while an element is selected.
- Resizing:
  - A splitter between the canvas and the inspector resizes it; double-click restores `inspectorWidth`.
  - New parameters: `initialInspectorWidth`, `minInspectorWidth`, `maxInspectorWidth` and `onInspectorWidthChanged`.

**Embedded fonts.**

- Controller:
  - `embeddedFonts` are saved in the `.qrep` by `toPackage`; `fromPackage`, `loadPackage`, `loadXml(fonts:)` and `replaceTemplate(fonts:)` read them.
  - `effectiveFonts` (host `fonts` plus the embedded families) drives the preview, canvas charts and exports.
  - `addFont(bytes)` fills the regular or bold slot of the family the file declares; `embedFont(family, files)`, `removeFont`, `importFonts()`, `embedDeviceFont(family)` and `embeddedFamilies`.
  - Font edits are part of the undo history; italic, CFF, collection and no-embedding fonts are refused with `ReportFontException`.
  - `fontFamilies` presets include the host and embedded families.
- Inspector:
  - A **Fonts** tab (`ReportInspectorPage.fonts`) lists embedded families with faces, size, a **Report default** switch, usage count and Remove.
  - With `deviceFonts`, an **On this device** list with search and **Embed** buttons. Typing an installed family into a font field embeds it.
  - Tabs fall back to icons when the inspector is too narrow for their labels.
  - New read-only property kind `ReportPropertyKind.note`.
- `QudsReportDesigner`:
  - `onPickFont` (`ReportFontPicker`) and `deviceFonts` (`ReportDeviceFonts`) parameters.
  - Embedded families are loaded into Flutter (`FontLoader`) so the design canvas draws them; the canvas re-lays text when system fonts change.
  - Import results and errors (`controller.notice`) show in the status bar.

**Data explorer.**

- `ReportDataExplorer` / `RenderReportDataExplorer`: a painted data grid that F6 or the toolbar's **Data** button (`ReportDesignMode.data`, `toggleData`) shows in place of the canvas.
  - The sidebar lists Fields and tables with row counts, plus **+ New table**.
  - The grid has typed column headers, a row-number gutter, tinted calculated columns, formatted values, scrollbars, and a right-click menu (`ReportDataContextHit`).
  - Cells are edited in place: double-click, F2, Enter, or typing. Enter and Tab commit and move; values are checked against the column type. Ctrl+C / Ctrl+V and Delete work on cells and rows.
- Controller:
  - `sampleData` is saved in the `.qrep` (`data/sample.json`) and used by the preview after host `mockData`. Every edit is undoable.
  - Explorer views: `dataTables`, `dataTable`, `selectDataTable`, `selectDataCell`, `setDataCell`, `addDataRow`, `removeDataRows`.
  - Columns: `addDataColumn` (including calculated columns with `expression`), `renameDataColumn`, `removeDataColumn`, `setDataColumnType`, `setDataColumnExpression`, `setDataColumnFormat`.
  - Tables and fields: `addDataTable`, `removeDataTable`, `addDataField`, `renameDataField`, `setDataField`, `setDataFieldType`.
  - Imports: `importDataText(fileName, text)` takes CSV, TSV, or JSON; `importDataFile()` uses the host picker.
  - Renaming a column or field rewrites its bindings (`item.qty`, `SUM(items.qty)`, `Data.customer`) and the formulas that use it.
  - Types and formulas are written to the template's `<DataSchema>`. Host `mockData` is shown read-only.
  - Templates loaded from the menu bring their data as sample data.
- The inspector shows table, column (name, type, formula, format, description), field, and sample-data properties in data mode.
- `QudsReportDesigner.onPickData` (`ReportDataPicker`) turns on **Import CSV / JSON…**.

**Unique element names.**

- Elements get a unique name when they are added, pasted, or loaded (`text1`, `table2`, …), so code can reach them with `QudsReportEngine.setText`, `setTableRows`, `elementAs`, and the other named-element setters.
- Duplicate and invalid names typed in the inspector are rejected with a notice. An empty name generates a fresh one.
- `ReportExportFormat` now comes from `quds_office_engine`, and the editor re-exports it.

**Categorized, bilingual templates.**

- The designer's Templates menu groups families under category captions; picking a family asks for العربية or English.
- `loadTemplate` loads the template's pre-saved images with its sample data, so logos, stamps, signatures and product photos show in the canvas, preview and Images tab.

**Docs.**

- The README links to the Quds Report Studio installers for Windows and Linux, which are built on `QudsReportDesigner`. The pub.dev screenshots add the template catalog, the data explorer and the Fonts tab.

## 0.6.0

**Report designer (`QudsReportDesigner`).** Depends on `quds_office_engine` **0.6.0**.

- `ReportDesignerController`:
  - Select, move, resize, and nudge; snap to grid and guides.
  - Align, distribute, and same size; z-order; clipboard and duplicate.
  - Add and remove bands; undo and redo.
  - Typed property inspector rows; inline text editing.
  - Inferred mock data.
- RenderBox surfaces (no text fields, no scroll widgets):
  - `ReportDesignerCanvas`: bands, rulers, handles, marquee, tool creation, and cross-band drag.
  - `ReportInspector`.
  - `ReportToolbar` with vector icons.
  - `ReportPreviewSurface`: a paginated live preview painted from the engine's glyph outlines.
- Context menus; Design/Preview toggle (F5).
- Export to PDF, XLSX, or DOCX through `onExport`.
- Chart tool: creates a data-bound bar chart; the inspector edits type, data, aggregation, sort, top N, series, static points, and styling. The canvas draws the chart with the engine renderer and sample values.
- Templates button: loads one of `ReportTemplates.all` with its sample data, or a blank report (`ReportDesignerController.loadTemplate`).
- Autocomplete while editing text on the canvas or inspector values: a painted popup under the caret. ↑/↓ choose, Enter/Tab insert, Esc closes, Ctrl+Space opens it anywhere. Functions insert `NAME()` with the caret inside.
- Template variables: a Variables toolbar menu inserts `{{Variables.x}}` at the caret or as a new text box. With nothing selected, the inspector adds, renames, retypes, formats, and removes variables. Values are checked against the type, and renaming a variable rewrites its references.
- The on-canvas text editor paints on the element's fill and switches to black or white text when the element's color would be unreadable (WCAG 4.5:1).
- `ReportLayoutPainter.paintPrimitives` paints any primitive list, including chart paths.
- `ReportBundledFonts` loads the package's Liberation and Noto Naskh Arabic faces into a `ReportFontRegistry`.
- Inspector redesign (still one RenderBox):
  - Collapsible sections, a title badge with the element kind and band, and diagnostics with severity icons.
  - Controls picked from property metadata: switches for booleans, segmented icon or text choices, dropdowns, ±steppers (↑/↓ while editing, Shift for ×10), preset combos (font sizes, families, format samples), paired X/Y and Width/Height fields, and a B/I/U glyph row.
  - A painted color popover: no color, the template palette, Office theme tints and shades, and standard colors.
  - `ReportProperty` gains `hint`, `presets`, `step`, `min`, `pair`, and `glyph`. `ReportDesignerController.stepProperty` / `steppedValue` snap to the unit's step and clamp to the minimum.
- Standalone desktop app [`apps/quds_report_studio`](https://github.com/MohammedAsaadAsaad/quds_office_suite/tree/main/apps/quds_report_studio) replaces the old example entry point. It has frameless window chrome (move, resize, maximize), New/Open/Save/Save as, recent files, and an unsaved-changes guard.

**Fixes.**

- Chart visuals reserve a strip for the bottom legend, so it no longer overlaps the category labels.
- `PdfViewerController` zoom animation starts on its first frame. Calling `fitPage` / `setScale` from a tap no longer trips the scheduler assertion.
- `RenderWordCanvas.windowForPagePoint` maps a page point back to widget coordinates (the inverse of hit-testing), so hosts and tests can target page content past the rulers.
- Analyzer clean-up across the package and example (initializing formals, unnecessary casts, `onReorderItem`).
- The example studio theme uses Liberation Sans with Noto Naskh Arabic / Tajawal as fallbacks, so Latin chrome text no longer depends on host fonts.

## 0.5.1

**PDF viewer options and events.**

- `PdfViewerOptions` on `QudsPdfViewer` / `QudsPdfEditor`: fit policy, zoom
  clamps, swipe enable/axis, page fling/snap, night invert, background,
  scrollbar, password, `preventLinkNavigation`.
- Callbacks: `onViewCreated`, `onLoadComplete`, `onPageChanged`, `onRender`,
  `onError`, `onPageError`, `onLinkHandle`, `onDraw`.
- Horizontal page stack, night-mode raster invert (viewer), and snap/fling on
  the canvas.
- Depends on `quds_office_engine` **0.5.3** (Arabic tashkeel on the correct
  letter, BiDi format marks skipped, new `pdf_widgets`).

## 0.5.0

**Studio gallery ships the report template library.**

- Templates are the landing gallery rail. Category chips filter commerce,
  finance, people, operations, narrative, data, education, property,
  logistics, and programs.
- Every template sample is **two pages** in one PDF: English, then Arabic.
- Depends on `quds_office_engine` **0.5.0** (`pdf_templates`, `SheetSkin`,
  RTL table cell start alignment, Flutter twins).
- Gallery also covers Flutter-twins widgets and the existing showcase /
  Office → PDF samples.

## 0.4.0

PDF viewing matches the page that owns the text.

- Selection stays on its page. Opening another file or scrolling to another
  page does not repaint the old highlight at the same coordinates.
- `Ctrl+A` / `selectAll()` selects every text run in the file.
  `Ctrl+Shift+A` / `selectPage` selects every run on that page.
- Find walks display-list runs, including matches that span runs. Hits are
  page-tagged, the current hit scrolls into view, and next/previous wrap.
  Arabic queries fold presentation forms, alef variants, and diacritics.
- `/Rotate` is painted and hit-tested as a clockwise quarter-turn of the view.
- Depends on `quds_office_engine` 0.4.0 (`PdfToolbox` graft, shaped watermark).

## 0.3.0

**Four surfaces: Word · Excel · PowerPoint · PDF.** The editor now embeds a
full PDF viewer/editor beside the Office canvases — same RenderBox discipline,
same theme/chrome hooks.

### PDF surfaces
- `QudsPdfViewer` / `QudsPdfEditor` on `RenderPdfCanvas` (display list paint,
  find, copy, link follow, animated zoom with tile stretch).
- Viewer is display-only; editor adds markup, form fill, page ops, layer
  toggle, and incremental save.
- Host fonts: call `OfficeHostFonts.ensureRegistered()` so Standard-14 /
  common Office aliases paint without OS font folders; embedded PDF faces win.

### Office surfaces (continued)
- `QudsWordEditor`, `QudsSheetEditor`, `QudsSlideEditor` — IME, BiDi caret,
  formulas, Morph slideshow, isolate open.

### Studio example
- PDF gallery (Office→PDF, PdfDocument writer, `pdf_widgets` samples) and
  bilingual workspace.

## 0.2.0

Interactive Word ruler, notes pane, section-wide landscape, horizontal page
gutters, and English package documentation. Chrome strings stay localizable;
the canvas supports many languages and writing directions.

## 0.1.0

First public release.

### Surfaces
- `QudsWordEditor` — paginated Word canvas with IME, BiDi caret, tables, comments, headers/footers, equations, and visuals.
- `QudsSheetEditor` — virtualized spreadsheet grid with formula bar, freeze panes, fill handle, and charts.
- `QudsSlideEditor` — slide stage with transform handles, snap guides, animations, and a real slideshow (including reverse play).

### Host integration
- Controllers load and save OOXML bytes (`fromBytes` / `saveBytes`), including password-protected packages.
- `OfficeTheme` + `OfficeSurfaceConfig` for light/dark, viewing / selecting / editing modes, and localizable chrome strings.
- Page orientation applies to the whole continuous section; the Word canvas pans horizontally with side gutters.
- Undo/redo, clipboard, context menus, and keyboard intents without `TextField` / `ListView` / `InteractiveViewer`.
- Isolate open for large documents so the UI isolate stays live.

### Studio example
- Full bilingual Word / Excel / PowerPoint workspace under `example/`.
