# Office engine strategy

Status: CrispCloud keeps the patched Quds fork as the current engine.
BetterOffice is the only migration candidate currently worth a bounded proof
of concept.

## Decision summary

| Option | Decision |
|---|---|
| Quds fork | Keep as the shipping editor engine while building regression and preservation coverage. |
| BetterOffice | Time-boxed proof of concept before any migration. |
| L’Office | Defer. Its documented Go-server ownership model does not fit the current local-first architecture. |
| Folio Office | Exclude. One commit and an old Dart constraint are not a foundation for the product. |
| Build a new engine | Reject. Targeted fixes to an existing engine are the rational investment. |

## Quds baseline

The published packages exclude `test/` via `.pubignore`; the upstream repository
does contain tests. We vendored those tests into the local package copies.

Run them from the `crispcloud` fork or the local package directories:

```bash
# engine
cd packages/quds_office_engine
dart pub get
dart test

# editor
cd packages/quds_office_editor
flutter pub get
flutter test
```

Local verification on 5 November 2026:

- engine: **454 passed, 6 skipped, 1 failure** — the failure is
  `pdf_widgets_test.dart: RTL MultiPage short line starts on the right`, a PDF
  layout assertion (`lastLeft` 90.9 vs expected >200). It is outside the DOCX
  save path but should be investigated before any engine update.
- editor: **220 passed, 1 skipped, 0 failures** when run against the patched
  local engine. The editor's own `pubspec.lock` can otherwise resolve the
  published engine and produce a false footnote regression; use a temporary
  `pubspec_overrides.yaml` pointing `quds_office_engine` at
  `../quds_office_engine` as documented in `packages/QUDS_FORKS.md`.
- CrispCloud regression tests: green.

The earlier preservation probe found that Quds rewrote `word/footnotes.xml`
and dropped the separator/continuationSeparator chrome notes while preserving
the actual footnote text. The vendored serializer now recreates the standard
Word chrome. Independent checks on 5 November 2026 re-opened untouched and
minimal-edit outputs with Pandoc and python-docx:

- paragraph text survived;
- both real footnotes survived;
- `w:type="separator"` (`id=-1`) and
  `w:type="continuationSeparator"` (`id=0`) are present again;
- each real footnote body has a `footnoteRef` mark and a separating space;
- the minimal edit (`X` inserted at the start) survived.

Microsoft Word **is installed** and has now reopened, saved and exported the
untouched/minimal outputs. The automated check is
`tool/verify_word_roundtrip.py`; it stages files in Word's own sandbox
container (`~/Library/Containers/com.microsoft.Word/Data/tmp/...`) so macOS
does not repeatedly prompt for folder access. Word reported two footnotes,
preserved body/footnote text, regenerated the separator chrome, and rendered
superscript note marks with a space before the note text. The generated PDF is
checked with `pdftotext`.

## Hard gate: save preservation

Visual display is not enough. For every supported format, an edit must satisfy:

1. **Display** — the document renders acceptably.
2. **Edit** — input, selection, undo/redo, formatting and formulas behave.
3. **Preserve** — the requested edit survives and unrelated content survives.

The third gate is mandatory. Quds regenerates important XML from its model, so
retaining the original ZIP package is not proof that unsupported content inside
rewritten XML survives.

Tests should:

- reopen outputs in an independent consumer (Microsoft Office or another
  editor), not only in the engine that wrote them;
- compare document semantics and package parts, not whole-file hashes;
- cover untouched save and minimal-edit save separately;
- compare text, styles, relationships, media, footnotes, headers and formulas.

## BetterOffice proof of concept

Status 5 November 2026: the upstream project is active and Apache-2.0, with
Rust crates, npm packages (framework-free cores and React editors), Python
wheels, and WASM builds. There is still **no Dart/Flutter package**. A real
PoC therefore requires a host-owned WebView, an offline bundle of JS/WASM,
workers, fonts and dynamic chunks, plus a byte/save bridge. No PoC was run in
this environment because iOS hardware was unavailable and the browser runtime
has not been packaged for the app.

### CLI verification recommendations

Use a layered harness rather than one parser:

1. **Fast structural checks** — `python-docx`, `openpyxl`, `python-pptx`,
   `lxml` and `zipfile` for relationships, parts, styles and note structures.
2. **Semantic/text checks** — `pandoc` for DOCX→plain/Markdown, plus
   `pdftotext` for rendered text and `pdftoppm` + ImageMagick `compare` or an
   SSIM tool for visual regression.
3. **Native consumer checks** — Word/Excel/PowerPoint AppleScript, using each
   app's sandbox container for staging. This is the highest-value check for
   actual Word compatibility; LibreOffice headless (`soffice --convert-to`) is
   a useful cross-suite fallback if installed, but is not currently present.
4. **Package/part diffing** — compare semantic XML parts, not whole-ZIP
   hashes: content types, relationships, styles, numbering, footnotes,
   headers/footers, media and formulas.

CrispSorter's `scripts/verify_docx_independent.py` is the right *pattern*:
author fixtures independently, run the real CLI, then verify with
python-docx/zipfile. CrispTranslator's `debug_format.py` is directly reusable
for DOCX XML checks (`footnotes`, separators, `footnoteRef`, styles, rsid
hygiene, relationship integrity). CrispSorter is Tauri/Rust and
CrispTranslator is Python, so neither supplies a Dart library; reuse their
fixtures, assertions and CLI workflow rather than their runtime.

The experiment must prove the integration, not just the demo.

### Gate 1 — packaged offline runtime

- Bundle JavaScript, WASM, workers, dynamic chunks, CSS and fonts.
- Launch on macOS and physical iOS hardware.
- Open DOCX, XLSX and PPTX with networking disabled and no warmed cache.
- Verify worker, `OffscreenCanvas`, `createImageBitmap` and dynamic chunk
  loading on the actual targets.

### Gate 2 — native persistence

- CrispCloud host owns file identity, bookmarks, authorized access, reads,
  writes, conflicts, recovery and save confirmation.
- Editor owns bytes, rendering, editing, commands and exported bytes.
- A save is successful only after the native host has persisted the revision.
- Failed saves leave the original intact and the document marked unsaved.

### Gate 3 — comparative quality

- Use CrispCloud’s problem documents plus representative DOCX/XLSX/PPTX files.
- Compare against the patched Quds build.
- Run untouched save and minimal-edit save through both.
- Reopen outputs in Microsoft Office or another independent consumer.
- Require material improvement in relevant defects with no unexplained loss of
  content, formatting, formulas or relationships.

### Gate 4 — product usability and cost

- Keyboard, focus, touch, clipboard, undo/redo, mixed RTL/LTR, background and
  resume.
- Startup, memory, bundle size, font packaging and update size.
- Native menus, file manager workflow, localization and accessibility.

### Decision

Proceed to broader qualification only if BetterOffice materially improves the
important document cases, preserves saved content, works offline on both
targets, and integrates acceptably with CrispCloud.

If only one format shows a compelling advantage, consider format-specific
adoption only if maintaining two engines is justified. If rendering is better
but saving or input is worse, stop the migration.

Collaboration is out of scope for the first experiment.
