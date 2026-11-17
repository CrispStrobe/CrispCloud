# Local qualification still required

Status: **not run** for the continuation source. The workspace launcher failed
before command execution: first with no free space, then with an unavailable
exec-server process. No GitHub Actions or CI-status endpoint is needed for these
checks, and none was queried or awaited.

Canonical source: `7f116669d2512cf660c86d3c83feb64ab6b707fb`.
The host's exact canonical pin is in `tool/office_fidelity_manifest.json`.
Run against that source and the corresponding host continuation checkout.
Retain exact source SHAs, toolchain versions, commands, exit codes and raw logs
before recording any passing result. Historical receipts in neighboring
directories keep their original source identities.

## Canonical engine

From `quds_office_suite/packages/quds_office_engine`:

```bash
dart --version
dart format --output=none --set-exit-if-changed \
  lib/src/odf/odf_text.dart \
  lib/src/extract/office_search_text.dart \
  lib/src/extract/office_text_extractor.dart \
  lib/src/word/serial/odt_document_writer.dart \
  test/odf_annotation_extraction_test.dart \
  test/odt_note_fidelity_test.dart
dart analyze \
  lib/src/odf/odf_text.dart \
  lib/src/extract/office_search_text.dart \
  lib/src/extract/office_text_extractor.dart \
  lib/src/word/serial/odt_document_writer.dart \
  test/odf_annotation_extraction_test.dart \
  test/odt_note_fidelity_test.dart
dart test \
  test/odf_annotation_extraction_test.dart \
  test/odf_covered_cell_extraction_test.dart \
  test/odf_export_text_fidelity_test.dart \
  test/office_search_fidelity_test.dart \
  test/odt_document_writer_test.dart \
  test/odt_note_fidelity_test.dart \
  test/odt_header_footer_fidelity_test.dart \
  test/ods_sheet_reader_test.dart \
  test/ods_sheet_writer_test.dart
```

The annotation file adds 11 authored cases. The note file retains two new
footnote/endnote ownership cases and the independently arriving same-paragraph
case. These counts describe test definitions, not passed tests.

The newly combined proofing and ODF histories retain their source-bound
qualification evidence. Refresh their relevant cohorts on the combined source
before promoting the draft, especially the copied morphology grammar/loading
cases and editor proofing path. No previous pass total qualifies this snapshot.

## Host preview, license bundle and vendor guard

From `CrispCloud`:

```bash
flutter --version
dart format --output=none --set-exit-if-changed \
  lib/services/office_document_service.dart \
  lib/services/office_proofing_licenses.dart \
  test/office_annotation_preview_test.dart \
  test/office_proofing_licenses_test.dart
flutter analyze \
  lib/services/office_document_service.dart \
  lib/services/office_proofing_licenses.dart \
  test/office_annotation_preview_test.dart \
  test/office_proofing_licenses_test.dart
flutter test \
  test/office_annotation_preview_test.dart \
  test/office_document_service_test.dart \
  test/office_proofing_licenses_test.dart
python3 tool/verify_office_fidelity.py \
  --source ../quds_office_suite \
  --legacy-source ../legacy-doc-parser \
  --require-tracked
```

The guard command assumes sibling checkouts of the canonical source and the
unchanged standalone parser pin. The host annotation file adds eight authored
cases. The existing license suite now checks seven bundled notices, including
verbatim Unicode attribution and its complete license.

## Controls and acceptance

Run the new annotation cases against their recorded pre-fix source with the test
files present, then against the final source, and retain the actual failures and
passes. The note ownership controls use the pre-guard continuation source
`c21a1549a612bb04fcd071a50d12c28f31343d11`; retain the annotation and note test
attribution separately. No failing control was executed in this turn.

Full application/viewer/export-dialog acceptance, live Zotero/Word/LibreOffice
interoperability and native/Wasm Harper acceptance remain separate scopes.
