# Integrated Office, path menus and portable 3D viewers

Runtime checkpoint: `0972abd0` (CrispCloud 1.3.2+25). Later test, workflow,
policy-evidence and documentation changes preserve application bytes. Branch audit cutoff:
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
  Production paths from root items/components can reference internal model parts;
  part-scoped IDs and caches keep distinct models separate.
- Orbit, scroll/pinch zoom, fit, wireframe and accessible button alternatives.
  Narrow-screen controls scroll within a bounded area so the canvas stays usable.
- Core/production 3MF geometry previews omit materials, colours, textures and print settings.
  Unknown required extensions and mixed-unit parts are refused. This is not
  manifold/printability validation or a replacement for a CAD editor.
- Limits: 16 MiB input/total model XML, 50,000 expanded triangles, 150,000 unique
  vertices, 4,096 ZIP entries/component visits, 128 model parts and 32 component levels. Shared
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

- Final parser/content/rendering cohort: **48 passed**, including production
  paths, same-ID resources in different parts, required-namespace checks,
  malformed/unsafe references, JavaScript-safe IDs, Brickwright output, shared
  vertex budgets, actual rendered pixels and narrow enlarged-text layout.
- Final actual Chrome viewer/browser-bandwidth cohort: **48 passed**.
  The browser fixture was moved inside the browser test serving root after the
  first production browser run correctly rejected the outside-root tool import.
- Full 28-file transfer/bandwidth regression: **314 passed** with the pinned SDK.
  An initial launch used Homebrew Dart 3.12.2 for the live lease-worker test;
  that failure was traced to the harness environment. Its complete 22-test
  journal cohort passed separately with pinned Dart 3.13.7, followed by the clean
  complete 314-test rerun. No application fix was needed for that mismatch.
- Read-only live model imports: **4 passed**. The two production-part 3MFs and
  corresponding STL contain 1,140 triangles each; the branded STL has 3,456.
  Third-party models remain local and were not copied into source or fixtures.
- Focused mesh analyzer: no issues found, including fatal informational lints.
- Current Brickwright 3MF, STL and authored cross-part production models: actual Dart VM and optimized JavaScript/Node
  smoke checks passed. Exact source/fixture provenance is retained separately.
- Path-menu cohort: 22 passed; covered both panes, account-bound favorites,
  other-pane navigation, swaps, touch access and stale-source/destination guards.
- Apple export source policy hashes match the reviewed inputs; declarations and
  submission decisions were not changed.

The initial 3D widget checks exposed a real enlarged-text overflow and a pending
gesture timer in the test. The layout was corrected and the test now settles the
gesture; all 48 final tests passed. Earlier failed local logs are not claimed as
acceptance. The initial combined bandwidth/highlighting run had 75 passing tests
and those two widget failures; the final renderer and complete bandwidth reruns
above are clean.

Legacy DOC, crisperbooks, CrispSorter and Catfish were fetched during this audit;
no unmerged remote changes remained in those four repositories. The newly
published HTTP bandwidth implementation and its retained qualification records
were merged through `2e683c9d`. Young branches are retained. Existing queued
GitHub release jobs and tags were left untouched.

## Local Mac acceptance checkpoint

Installed and launched `CrispCloud 1.3.2 (0972abd0).app` after deep/strict
signature verification, a 45-second startup check with credential policy ready,
and offline verification of its packaged Apple artifact. The runner and Dart
framework contain both Intel and Apple Silicon code. Exact binary hashes and
scope are in [the acceptance receipt](evidence/integration-viewers-20261114/acceptance.json).

A fresh 20:11 UTC branch audit found additional worksheet-history and Word
bookmark work published during this build. Those additions enter a subsequent
integration wave; they are not claimed by this checkpoint's binary or tests.
