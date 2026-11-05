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

Local baseline (5 Nov 2026):

- engine: 454 passed, 6 skipped, 1 failure
  (`pdf_widgets_test.dart: RTL MultiPage short line starts on the right`;
  outside the DOCX save path, but still open)
- editor: 220 passed, 1 skipped, 0 failures when the editor tests use the
  patched local engine
- CrispCloud regressions: green

The editor package can resolve the published `quds_office_engine` when its
tests are run directly. Create a temporary `pubspec_overrides.yaml` before the
editor test run so the fork patches are actually exercised:

```bash
cd packages/quds_office_editor
printf 'dependency_overrides:\n  quds_office_engine:\n    path: ../quds_office_engine\n' \
  > pubspec_overrides.yaml
flutter pub get
flutter test
rm pubspec_overrides.yaml
```

`pubspec_overrides.yaml` is gitignored intentionally. See
`docs/office-engine-strategy.md` for the save-preservation gate and the
BetterOffice proof-of-concept criteria.

## Current patches

`packages/quds_office_engine`:

- footnote/endnote reference marks are imported as superscript,
- footnotes attach only to the page containing the reference glyph,
- footnote/endnote separator and continuationSeparator chrome is recreated on
  save instead of being dropped,
- PDF watermarks rotate as one marked line and survive missing-script faces,
- the feature-showcase template detail band fits its item table.

`packages/quds_office_editor`:

- selection uses the theme selection colour (previously white-on-white),
- header/footer edits force a full relayout so typed text lands in the header
  band instead of stale page chrome,
- report font tests match the supported italic/bold-italic slots,
- feature-showcase templates carry the corrected detail band.

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
