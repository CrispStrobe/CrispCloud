# Integrated Office, path menus and portable 3D viewers

Runtime checkpoint: `3f3557a4` (CrispCloud 1.3.2+25). Later documentation-only
merges preserve the tested application bytes. Source audit cutoff:
2026-11-14 19:47 UTC.

## Office source

CrispCloud vendors all 2,182 managed files from Quds fork main
`4bdb70c9d86fd1ee09ed99d3114b178e965cfa01`. This includes the requested source
checkpoint `2d2a7be4`, schema-valid comments, cache-preserving no-edit saves,
frozen/frozenSplit anchors, undoable sorting, retained cell locks/PDF borders,
and speaker-note history. Host checkpoint `a3897dfb` and the notes/sorting
branch are included. Local host commit `ee780d7f` is retained in history;
its already-integrated source changes were checked against every managed hash.
Concurrent uncommitted work in other checkouts was left untouched.

The vendor verifier passed with `--require-tracked`, including the standalone
legacy DOC source pin `544a50e7f8ad095a618b6206ccece7e0cb335f4b`.
Quds focused analysis passed; 13 engine and 16 editor regressions passed.
The host/path/content/mesh cohort passed 108 tests. These focused cohorts do
not constitute a fresh complete Office suite or new native visual certification.
Existing broader source acceptance and its limits remain in the Office reports.

## Viewer and navigation behavior

- STL: binary (including headers beginning `solid`) and strict single-solid ASCII.
- 3MF: core triangle geometry, package model relationships, build items,
  component instances, affine transforms and conversion of declared units to mm.
- Orbit, scroll/pinch zoom, fit, wireframe and accessible button alternatives.
  Narrow-screen controls scroll within a bounded area so the canvas stays usable.
- Core/production 3MF geometry previews omit materials, colours, textures and print settings.
  Unknown required extensions and mixed-unit parts are refused. This is not
  manifold/printability validation or a replacement for a CAD editor.
- Limits: 16 MiB input/model XML, 50,000 expanded triangles, 150,000 unique
  vertices, 4,096 ZIP entries/component visits and 32 component levels. Shared
  meshes are decoded once. ZIP inflation is bounded by actual output; no parts
  are extracted and no external resources are fetched.
- Source and BSD attribution: [Brickwright reference](third-party/brickwright-cad/README.md).
  No CAD kernel, model-library asset or additional runtime dependency was added.
- F3, F4 and the preview pane share conservative 32 Ki-character content hints:
  shebangs, JSON, XML/HTML, INI and Apple/OpenStep strings. Existing filename
  mappings remain the fallback; this is not an all-language probabilistic guess.
  The actual UTF-16LE Android File Transfer `Localizable.strings` file passed
  a read-only live check. Its third-party contents were not copied into fixtures.
- Right-click/long-press a pane path to copy its full path, add/remove a favorite,
  open the captured source/account in the other pane, swap panes, edit or refresh.
  Stale menu actions cannot redirect a newly navigated source or destination.
  Archive paths copy a qualified container/member path; unsupported directory
  actions on virtual listings remain disabled.

## Verification

- Final parser/content/rendering cohort: 36 passed, including the actual current
  Brickwright exporter output, repeated component budgets, rendered pixels,
  interaction controls and 320x480 enlarged-text layout.
- Chrome viewer/browser-bandwidth cohort: 34 passed. This earlier browser cohort
  predates the two additional fixture/component-budget cases; the final parser
  also passed actual Dart-to-JavaScript/Node execution with Brickwright output.
- Focused mesh analyzer: no issues found, including fatal informational lints.
- Current Brickwright 3MF plus STL: actual Dart VM and optimized JavaScript/Node
  smoke checks passed. Exact source/fixture provenance is retained separately.
- Path-menu cohort: 22 passed; covered both panes, account-bound favorites,
  other-pane navigation, swaps, touch access and stale-source/destination guards.
- Apple export source policy hashes match the reviewed inputs; declarations and
  submission decisions were not changed.

The initial 3D widget checks exposed a real enlarged-text overflow and a pending
gesture timer in the test. The layout was corrected and the test now settles the
gesture; all 36 final tests passed. Earlier failed local logs are not claimed as
acceptance. The initial combined bandwidth/highlighting run had 75 passing tests
and those two widget failures; the subsequent full bandwidth cohort is recorded
separately when complete.

Legacy DOC, crisperbooks, CrispSorter and Catfish were fetched during this audit;
no unmerged remote changes remained in those four repositories. The newly
published HTTP bandwidth implementation and its retained qualification records
were merged through `2e683c9d`. Young branches are retained. Existing queued
GitHub release jobs and tags were left untouched.
