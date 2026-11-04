# Quds forks

The local packages under this directory are development copies of the
MIT-licensed Quds Office engine/editor.

- Upstream: https://github.com/MohammedAsaadAsaad/quds_office_suite
- Our fork: https://github.com/CrispStrobe/quds_office_suite
- Our branch: `crispcloud`

## Tests

Upstream deliberately excludes `test/` from the published archives via
`.pubignore`, but the repository has tests. They are vendored here and in our
fork.

```bash
cd packages/quds_office_engine && dart pub get && dart test
cd packages/quds_office_editor && flutter pub get && flutter test
```

Baseline on the `crispcloud` fork (4 Nov 2026):

- engine: 456 passed, 3 skipped, 1 pre-existing failure
- editor: 214 passed, 1 skipped, 3 pre-existing failures in report/font tests
- CrispCloud regressions: 5 passed
  (`test/office_editor_fixes_test.dart`, `test/office_roundtrip_preservation_test.dart`,
  and the fork's `crispcloud_regressions_test.dart`)

The pre-existing failures are recorded, not hidden. See
`docs/office-engine-strategy.md` for the save-preservation gate and the
BetterOffice proof-of-concept criteria.

## Current patches

`packages/quds_office_engine`:

- footnote/endnote reference marks are imported as superscript,
- footnotes attach only to the page containing the reference glyph.

`packages/quds_office_editor`:

- selection uses the theme selection colour (previously white-on-white),
- header/footer edits force a full relayout so typed text lands in the header
  band instead of stale page chrome.

## Upstream contribution rules

We follow
[CONTRIBUTING.md](https://github.com/MohammedAsaadAsaad/quds_office_suite/blob/main/CONTRIBUTING.md):

- engine and editor fixes are separate commits,
- engine code stays pure Dart (no Flutter or `dart:ui`),
- editor document surfaces stay `RenderBox`/`LeafRenderObjectWidget` only,
- tests live next to the behavior they cover,
- package CHANGELOGs get an `Unreleased` entry for user-visible behavior,
- versions are not bumped outside a release.

The `crispcloud` branch currently has two feature commits:

1. `Word: render imported footnote references as superscript`
2. `Word editor: visible selection and header/footer relayout`

## Syncing

The app currently resolves the packages through local `path` overrides in
`pubspec.yaml`, so builds are reproducible without network access. After
changing a vendored package:

```bash
# in the fork working copy, with the crispcloud branch checked out
rsync -a /path/to/CrispCloud/packages/quds_office_engine/ \
  packages/quds_office_engine/
rsync -a /path/to/CrispCloud/packages/quds_office_editor/ \
  packages/quds_office_editor/
git add packages/quds_office_engine packages/quds_office_editor
git commit -m "CrispCloud: update Quds patches"
git push origin crispcloud
```

Keep fork commits small and add a regression test in CrispCloud for every
upstream bug fixed. Do not rewrite the packages on a sync; copy only the
intended files.
