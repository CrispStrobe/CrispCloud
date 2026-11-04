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

Baseline observed on the `crispcloud` fork (4 November 2026):

- engine: 458 passed, 3 skipped, 0 failures
- editor: 220 passed, 1 skipped, 0 failures
- CrispCloud regression tests: 5 passed
  (footnote superscript, header relayout, select all, and two round-trip tests)

The remaining skips are environment-only: three engine font tests and one
editor test that needs an external PDF compare tool.

A first preservation probe found that Quds rewrites `word/footnotes.xml` and
drops the separator/continuationSeparator chrome notes while preserving the
actual footnote text. That is exactly the kind of finding the preservation gate
must track and verify in Word/LibreOffice before declaring save safety.

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

BetterOffice is Apache-2.0 and has substantial Rust OOXML engines, but no
Dart/Flutter package. The experiment must prove the integration, not just the
demo.

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
