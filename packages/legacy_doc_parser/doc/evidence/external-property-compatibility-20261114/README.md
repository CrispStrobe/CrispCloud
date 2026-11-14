# Focused property compatibility evidence

See [the audit explanation](../../external-property-compatibility-20261114.md)
for the decisions, specification sources, test scope, and limits.

- `inspect_sources.py` uses `olefile==0.47` independently of the Dart parser.
  It requires the exact three source hashes and records author-table bytes,
  numbering ancestry and raw ANLD operands, and the ignored-border operand.
- `source-structures.json` is the retained output of that read-only inspector.
- `native-comparison.json` compares visible `w:t` text and table structure with
  direct LibreOffice import of the actual DOC files. It records output hashes.
- `validation.zip` contains corrected baseline logs, final focused and adjacent
  logs, strict-analysis logs, both actual-file probe results, and both export
  modes. Early fixture-typo runs are not used as final evidence.
- `receipt.json` identifies the tested source hashes and archived evidence.

Reproduce the independent byte inspection with Python and `olefile==0.47`:

```sh
python3 doc/evidence/external-property-compatibility-20261114/inspect_sources.py
```

Reproduce the focused checks after `dart pub get`:

```sh
dart test test/legacy_word_ignored_property_test.dart
dart analyze --fatal-infos
```

The baseline logs precede strengthening the two already-failing actual-file
tests with explicit LibreOffice-derived text/table assertions. They retain the
same 82 names and acceptance/rejection expectations. The final log includes
the stronger assertions. The full repository gate is a separate integration
receipt; the adjacent total here is not the whole repository's test count.
