# crisp-docx independent-oracle audit — 2026-11-13

## Decision

Use crisp-docx as a **bounded external OOXML observation and fixture-generation tool**. Its successful tests, `check` result, and paragraph round trips are insufficient as a document-fidelity oracle. The executed controls below expose structural losses that plain text equality, schema success, and even a byte-exact round-trip endpoint can miss.

The audited repository is [`CrispStrobe/crisp-docx`](https://github.com/CrispStrobe/crisp-docx/tree/ddf7830d8d92e6b59b10874d144a59f163a256e1), main commit `ddf7830d8d92e6b59b10874d144a59f163a256e1`, tree `5dde3ca46e07f063534abdf2ff117a5e9b205918`. Its checkout remained clean. No crisp-docx remote, parser runtime, or app runtime was changed.

## What was actually run

- Built the current Rust core and CLI with official Rust/Cargo 1.100.0. Original source and tests were copied without modification into a separate scratch workspace; only its root member list was narrowed to core/CLI so Cargo did not need optional sibling ML repositories. The original `--locked` rejection is retained. The resolved lock keeps all retained dependency names, versions, registry sources and checksums: 225 original packages reduce to 70. Dependency-reference disambiguation and the unused serde-derive feature differ, as recorded. This is not a full six-crate workspace/ML/LLM validation.
- The scoped suite reports **127 passing tests**: 102 unit, 13 integration, five live, six parity, one compilation doctest. **Twelve of those do no fixture work** in a clean checkout: one real-document unit test, five live tests, six parity tests return early. Eleven print skip messages; the unit test returns silently. The parity fixture README correctly says CI cannot run its real-document corpus; the stronger claims in `PARITY.md` are not supported by the checked-in CI configuration.
- Re-ran all **five live tests with an actual nonempty authored note fixture and blueprint**: five pass without skipping. This does not cure their weak intermediate assertions; the same note-conversion operation has the retained failing intermediate example below.
- Executed **76 external commands on 14 independently authored controls** using the current core/CLI plus Pandoc 3.1.11.1. Every expected semantic constant was authored separately from the producer under test. A namespace-aware Python projection records story parts, paragraph/container paths, table cells, typed inline events, ranges, note references and package relationships.
- Ran the already built Microsoft Open XML SDK 3.3.0 / Office2019 validator against all 14 inputs, 45 rewritten outputs and two newly authored note documents. The source controls have two expected SDK failures (missing relationship/note targets); all other inputs, including the nested textbox and namespace-alias controls, have zero SDK errors. The unclosed bookmark is a separate range-topology control the SDK also accepts; zero schema errors is not a promise of a complete range invariant.
- Applied current crisp-docx and Pandoc read-only to **nine retained parser/native DOCX pairs** from frozen parser runtime `c5ff75e76163d9abbdd44a9f2a7c5ad210929289`. Each binary DOC and both output hashes were checked against its original native-corpus receipt. No native conversion or rendering was rerun.

The separately downloaded v0.1.0 Python wheel is identified and SHA-verified in its own receipt. Its smoke result is **not** evidence for current-head execution. The current source build supplies all substantive probes. The wheel and current Python source both lack `extract_paragraph_runs`, `replace_paragraph_runs`, and the `NotesKind` name shown by the README; the exported enum is `PyNotesKind`.

## Concrete observations

| Control | Observed current-head behavior | Why it matters |
|---|---|---|
| Plain paragraphs | Text extraction and no-op rewriting preserve the measured structure. All 14 raw `Package` save/reopen operations preserve every part's bytes. | Useful package transport and a bounded plain-text cross-check. ZIP container bytes need not match. |
| Empty `<w:p/>` | Both extraction APIs return two paragraphs for a three-paragraph input. | Paragraph count/order assertions must include self-closing empty paragraphs. The untouched empty XML remains during a no-op rewrite, concealing the extraction omission. |
| Namespace alias | Valid `x:p`/`x:t` with the same Word namespace yields zero paragraphs; the ordinary `w:` version yields two. SDK accepts both and the independent expanded-name tree is equal. | Raw-prefix matching is not a namespace-aware oracle. Pandoc also rejects this alias input. |
| Tabs/breaks | Both rewrites replace `<w:tab/>` and `<w:br/>` with tab/newline characters inside `<w:t>`. | Equal extracted strings conceal changed Word semantics; SDK accepts the rewritten XML. |
| Mid-paragraph bookmark | Range offsets `[1,2]` become `[3,3]` through run IO and `[0,3]` through text IO. | A bookmark ID count or flattened string cannot establish anchor preservation. |
| Note/link topology | The footnote at offset 1 moves to 3 with run IO and 7 with text IO. The endnote reference and hyperlink wrapper disappear. | All text remains `ABCLINK`; auxiliary note parts remain. Flat text and part inventories alone pass. |
| Tracked revisions | `Base` + inserted `NEW` + deleted `OLD` becomes unconditional `BaseNEW`; insertion/deletion wrappers are removed. | Accept/reject views and source revision provenance must be tested separately. |
| Nested textbox | Valid source has outer text `BeforeAfter` and a separate `Textbox` paragraph. Text IO flattens them; run IO observes only `Before`. Both no-op writers produce mismatched XML tags. | SDK independently accepts the source and rejects both rewritten outputs. This is not an ambiguous visual interpretation. |
| Invalid reference controls | `check_package` reports clean for a nonexistent arbitrary relationship ID and an absent footnote definition. | SDK independently rejects both. `check` is a limited diagnostic, not schema/reference-complete validation. |
| Note conversion | Footnotes→endnotes changes literal `FootnoteText` to `EndnoteText` and leaves the note's `.rels` under its old owner, breaking the hyperlink. `check` reports clean; SDK rejects the missing endnote relationship. | The reverse conversion restores **all original part bytes**. An endpoint-only metamorphic test can pass while the intermediate document is wrong. |
| Body transplant | The source hyperlink remains in the body but its relationship is not imported. | Both crisp-docx and SDK detect the resulting numeric-rId failure. Transplant is a formatting operation, not a general lossless package merge. |

All details are in `probe-report.json`, the original inputs/outputs, command logs and three SDK result sets inside `records.tar.xz`. Some findings describe deliberate scope limits rather than violations of a promised API contract; none should be promoted into our application's fidelity claims.

### The nine existing corpus pairs

Every one of the 18 DOCX files reports clean through crisp-docx. Six pairs have identical body-text arrays; seven have identical run-text arrays. Eight pairs have different Pandoc ASTs. These are observations, not eight parser bugs: Pandoc and the independent structural projection also expose representation differences such as blank/duplicate header parts, Word AlternateContent branches, numbering and native bridge normalization.

For example, `note-markers` has identical flat body text while the parser output has 11 footnote paragraphs and a one-cell note table, whereas native output has 12 paragraphs and no note table. `content-controls` even has an equal Pandoc AST while the story-part inventory differs. `word14-margin-origin` includes both DrawingML/VML branches in native XML; counting every XML paragraph is not counting rendered paragraphs. The original DOCX source, binary bridge, parser output and native output must retain separate identities before assigning a difference to a producer.

The pair records bind `word`, `poi-simple-table2`, `bookmarks`, `note-markers`, `story-media`, `comment-threads`, `content-controls`, `linked-textboxes`, and `word14-margin-origin` to `doc/evidence/native-corpus-c5ff75e7`. Their original DOCX bytes remain in that existing sealed bundle. This audit does not claim native Word execution or layout equivalence.

## Mechanisms worth reusing now

1. **An external read-only API adapter.** `oracle_adapter.rs` wraps the public Rust core and emits JSON for the body and separately selected story parts. It is available locally as `isolated-build/target/debug/examples/oracle_adapter inspect INPUT.docx`. Calling paragraph extraction once per part adds part identity; it still does not add note IDs, table/cell identity, accepted/rejected revision semantics, AlternateContent selection or layout. `ooxml_projection.py INPUT.docx` supplies the complementary namespace-aware structural observations, with its limits stated in the module header.
2. **Typed invariants between every conversion stage.** Preserve story identity, paragraph/container paths, table row/cell structure, note target IDs and offsets, bookmark ranges, field/hyperlink wrappers and revision branches. Compare these before and after each individual operation, then add endpoint round trips. The note-conversion counterexample demonstrates why order matters.
3. **Independent authored generators with measured contracts.** Both the current `inject-footnotes` CLI and its Markdown→Pandoc helper produced schema-valid notes with a bold run, italic run and hyperlink. The retained repeated-citation example deliberately exposes their difference: crisp-docx emits two references to one note ID; Pandoc creates two note definitions with separate IDs. Do not erase that distinction by normalizing IDs and calling the packages equivalent. Use single-citation fixtures when that is the intended contract, then test repeated identity separately.
4. **Pandoc JSON as a second projection, with explicit omissions.** It preserves the authored table structure, insertion/deletion spans under `--track-changes=all`, and ordinary note/link content. It ignores header/footer/textbox content in the measured controls, loses text adjacent to multiple note references in one run, and rejects the namespace-alias document. Markdown is therefore a useful additional observation, not a full document golden. The crisp-docx repository itself has no general DOCX→Markdown exporter; it has an inline note-markup parser and a Markdown→DOCX wrapper.
5. **The parity harness's two-sided validation pattern.** It runs separate Python and Rust implementations on the same input and validates each output independently before comparison. This is useful architecture. Its current equality assertions are weaker than its ledger suggests: some compare counts and part names, not XML semantics; notes conversion checks renamed parts and limited soundness. Missing fixtures must fail or be explicitly excluded from an executed-oracle count rather than appear as ordinary passes.

### Binary→OOXML handoff

crisp-docx is an OOXML tool, not an independent binary DOC decoder. Feed it a separately identified parser export or native DOC→DOCX bridge. A direct binary probe is retained: `inspect` accepts the embedded theme ZIP inside the Apache POI OLE DOC and lists five theme parts; `check` then correctly rejects the missing `word/document.xml`. Thus successful ZIP loading or `inspect` is not evidence that binary Word was decoded. Validate container type, root relationship, main content type and main Word part at the handoff.

## Source map and independence

Relevant files at the pinned commit:

- [`paragraph_runs.rs`](https://github.com/CrispStrobe/crisp-docx/blob/ddf7830d8d92e6b59b10874d144a59f163a256e1/crates/crisp-docx-core/src/paragraph_runs.rs): minimal run model, lexical `w:` matching, bookmark relocation, footnote re-emission and nested paragraph behavior.
- [`paragraph_text.rs`](https://github.com/CrispStrobe/crisp-docx/blob/ddf7830d8d92e6b59b10874d144a59f163a256e1/crates/crisp-docx-core/src/paragraph_text.rs): flattened body text and paragraph reconstruction.
- [`check.rs`](https://github.com/CrispStrobe/crisp-docx/blob/ddf7830d8d92e6b59b10874d144a59f163a256e1/crates/crisp-docx-core/src/check.rs), [`notes_kind.rs`](https://github.com/CrispStrobe/crisp-docx/blob/ddf7830d8d92e6b59b10874d144a59f163a256e1/crates/crisp-docx-core/src/notes_kind.rs), and [`transplant.rs`](https://github.com/CrispStrobe/crisp-docx/blob/ddf7830d8d92e6b59b10874d144a59f163a256e1/crates/crisp-docx-core/src/transplant.rs): diagnostics and mutation boundaries.
- [`tests/parity.rs`](https://github.com/CrispStrobe/crisp-docx/blob/ddf7830d8d92e6b59b10874d144a59f163a256e1/crates/crisp-docx-core/tests/parity.rs), `tests/live.rs`, `tests/common/mod.rs`, and `tests/parity_fixtures/README.md`: differential harness, skipped fixture paths, inline generated controls and missing real fixture corpus.
- `crates/crisp-docx-core/src/inline_md.rs`, `note_injection.rs`, `scripts/md-footnotes-to-docx.py`: bounded note authoring; the Markdown wrapper handles single-line numeric definitions, not a general lossless document projection.
- `crates/crisp-docx-py/src/lib.rs`, `crates/crisp-docx-cli/src/main.rs`, `.github/workflows/ci.yml`, `PARITY.md`: actual API/command surface and execution prerequisites.

The Rust implementation is separate from the Dart parser and no parser/app dependency appears in its source manifests. It is explicitly a port of the same author's CrispTranslator Python primitives, so Python↔Rust agreement is not two independently specified goldens. Our authored expectations, namespace-aware XML observations, Microsoft SDK, Pandoc and retained LibreOffice outputs supply different checks with different failure modes. No one check covers the whole problem.

## Licensing and retention

Upstream source is AGPL-3.0-or-later. The exact head adds a Section 7 app-marketplace distribution permission; its text explicitly leaves other terms in place. It does not make the implementation permissively licensed. The parser repository is MPL-2.0. No crisp-docx implementation was copied into production code. The standalone Rust adapter is explicitly AGPL-3.0-or-later, kept as audit tooling; the upstream license text is retained for attribution. The other new controls/projection/receipts were authored independently. Any production reuse of upstream implementation or linked distribution needs its own license decision.

No real DOCX fixture is committed by crisp-docx; its external Vielfalt fixture is not available and was neither fetched nor copied. Its inline Rust fixture builders are upstream code and were not copied into our generator. Existing paired corpus provenance remains MIT (Quds), MPL-2.0 (LibreOffice), Apache-2.0 (POI), or independently authored as declared in the pinned corpus manifest. See the retained source/manifest identities.

`records.tar.xz` contains the complete small authored inputs and outputs, raw command records, diagnostics and observations. Downloaded Rust archives, build caches and executable binaries are reproducible and omitted; official URLs, hashes, exact source hashes, lock files, build commands and executable identities are retained. The original lock rejection and later successful narrowed build remain distinct. `verify.py` checks retained bytes and the principal semantic/source bindings without rerunning Rust, Pandoc, SDK or native workflows.

### Derived-result receipt controls

The evidence-only follow-up recomputes every authored rewrite's part-byte and semantic equality from its bound projections. It also binds all retained pair text, diagnostic, Pandoc digest and comparison claims to the individual raw tool outputs and projections. Fourteen in-memory corruption controls exercise these guards, including the previously accepted false claim that the lossy note/link rewrite was semantically equal. Both ordinary and optimized Python execute the same explicit guards. The original 373-record archive and its manifest remain byte-identical; no document producer or runtime test was rerun for this correction.

Run the controls with `python3 test_verifier.py` (or `python3 -O test_verifier.py`) from this directory. They first verify the original envelope, then test semantic contradictions independently of outer hashes.
