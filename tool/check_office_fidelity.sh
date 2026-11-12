#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tool/verify_office_fidelity.py
python3 -m unittest discover -s tool -p test_sync_office_fidelity.py
(cd packages/quds_office_engine && dart pub get && bash tool/fidelity/check.sh)
python3 -m unittest discover -s tool -p test_office_host_evidence.py
python3 tool/office_host_evidence.py clean
office_host_coverage_dir="${OFFICE_HOST_COVERAGE_DIR:-build/fidelity-host/coverage/run-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
rm -f build/fidelity-host/coverage/gaps.json
python3 tool/collect_office_host_coverage.py "$office_host_coverage_dir" -- \
  test/office_fidelity_workflow_test.dart \
  test/office_formatting_preservation_test.dart \
  test/office_roundtrip_preservation_test.dart \
  test/office_section_break_fidelity_test.dart \
  test/office_editor_fixes_test.dart \
  test/office_footnote_test.dart \
  test/office_ribbon_footnotes_test.dart \
  test/office_ribbon_common_i18n_test.dart \
  test/office_document_service_test.dart \
  test/legacy_word_document_test.dart \
  test/legacy_word_conversion_strings_test.dart \
  test/legacy_word_copy_target_test.dart \
  test/word_template_preservation_test.dart \
  test/word_format_strings_test.dart \
  test/office_preview_fidelity_test.dart \
  test/office_preview_strings_test.dart \
  test/preview_media_localization_test.dart \
  test/recursive_search_service_test.dart \
  test/office_pdf_service_test.dart \
  test/widget/office_editor_dialog_test.dart \
  test/widget/office_editor_ribbon_test.dart \
  test/widget/office_paragraph_dialog_test.dart \
  test/widget/office_paragraph_fidelity_test.dart \
  test/widget/office_font_fidelity_test.dart \
  test/widget/office_picture_fidelity_test.dart \
  test/widget/office_save_fidelity_test.dart \
  test/widget/legacy_word_conversion_dialog_test.dart \
  test/widget/legacy_word_routing_test.dart
python3 -m unittest discover -s tool -p 'test*office*coverage.py'
python3 tool/office_host_coverage.py "$office_host_coverage_dir/lcov.info" \
  --output "$office_host_coverage_dir/gaps.json" --require-receipt --require-all-sources
mkdir -p build/fidelity-host/coverage
cp "$office_host_coverage_dir/gaps.json" build/fidelity-host/coverage/gaps.json
python3 tool/office_host_evidence.py verify
python3 packages/quds_office_engine/tool/fidelity/corpus.py verify build/fidelity
