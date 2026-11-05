# Quds forks

Local development copies of the MIT-licensed Quds Office engine/editor.

- Upstream: https://github.com/MohammedAsaadAsaad/quds_office_suite
- Fork: https://github.com/CrispStrobe/quds_office_suite
- Branch: `crispcloud`

## Test commands

The published packages exclude `test/`; the local copies and fork retain it.

```bash
# Engine
cd packages/quds_office_engine
dart pub get
dart test

# Editor — exercise the patched local engine, not the published snapshot.
cd packages/quds_office_editor
printf 'dependency_overrides:\n  quds_office_engine:\n    path: ../quds_office_engine\n' \
  > pubspec_overrides.yaml
flutter pub get
flutter test
rm pubspec_overrides.yaml
```

`pubspec_overrides.yaml` is gitignored intentionally. Without it, the editor
tests can resolve the published engine and produce a false footnote regression.

## Baseline — 5 November 2026

- Engine: **454 passed, 6 skipped, 1 failure**
  - failure: `pdf_widgets_test.dart: RTL MultiPage short line starts on the
    right` (`lastLeft` 90.9 vs expected >200)
  - outside the DOCX save path; next Quds defect to investigate
- Editor: **220 passed, 1 skipped, 0 failures** with the local-engine override
- CrispCloud Office regressions: green

The remaining skips are environment-only: font availability and an external
PDF comparison tool.

## Local patches

### Engine

- footnote/endnote reference marks import as superscript;
- footnotes attach only to the page containing the reference glyph;
- `separator` and `continuationSeparator` note chrome is recreated on save;
- each note body gets a `footnoteRef`/`endnoteRef` mark with direct superscript
  formatting and the conventional separating space;
- PDF watermarks rotate as one marked line and survive missing-script faces;
- feature-showcase template detail bands fit their item table.

### Editor

- selection uses the theme selection colour (previously white-on-white);
- header/footer edits force a full relayout so typed text lands in the header
  band;
- report font tests match the supported italic/bold-italic slots;
- feature-showcase templates carry the corrected detail band.

Some of these changes are currently in the vendored copies first. Sync only the
intended files back to the fork before treating the fork branch as canonical.

## Independent Word verification

```bash
~/miniconda3/bin/python tool/verify_word_roundtrip.py \
  build/quds_roundtrip/unedited.docx \
  build/quds_roundtrip/minimal.docx
```

The harness stages files in Word’s own sandbox container
(`~/Library/Containers/com.microsoft.Word/Data/tmp/crispcloud-word-verify`) so
Word does not repeatedly request folder access. It opens/saves/exports through
Microsoft Word, then checks paragraph text, footnote count/text, `footnoteRef`
markers, separator chrome and PDF text.

The untouched and minimal-edit outputs both passed. Word rendered correctly
formatted superscript note numbers. See `docs/office-engine-strategy.md` for the
full verification stack, BetterOffice status and remaining work.

## Upstream contribution rules

Follow
[CONTRIBUTING.md](https://github.com/MohammedAsaadAsaad/quds_office_suite/blob/main/CONTRIBUTING.md):

- engine and editor fixes are separate commits;
- engine code stays pure Dart (no Flutter or `dart:ui`);
- editor document surfaces stay `RenderBox`/`LeafRenderObjectWidget` only;
- tests live next to the behavior they cover;
- package CHANGELOGs get an `Unreleased` entry for user-visible changes;
- do not bump versions outside a release.

## Syncing

The app resolves these packages through local `path` overrides in
`pubspec.yaml`, so builds are reproducible offline.

```bash
# In the fork checkout on branch crispcloud:
rsync -a /path/to/CrispCloud/packages/quds_office_engine/ \
  packages/quds_office_engine/
rsync -a /path/to/CrispCloud/packages/quds_office_editor/ \
  packages/quds_office_editor/
git add packages/quds_office_engine packages/quds_office_editor
git commit -m "CrispCloud: update Quds patches"
git push origin crispcloud
```

Keep commits small and add a CrispCloud regression test for every fixed bug.
Do not rewrite the packages during sync; copy only intended files.
