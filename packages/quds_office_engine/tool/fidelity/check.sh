#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Generate every required output before running the independent oracles. Missing
# or stale/incomplete inventories fail; this command never regenerates goldens.
python3 tool/fidelity/inventory.py clean
dart test \
  test/office_fidelity_oracle_test.dart test/office_steps_test.dart \
  test/scripted_workflows_test.dart test/numbering_collision_test.dart \
  test/list_restart_fidelity_test.dart test/rich_note_test.dart \
  test/native_presentation_test.dart test/native_spreadsheet_test.dart \
  test/style_cascade_test.dart test/story_media_fidelity_test.dart \
  test/word_part_routing_test.dart test/sheet_schema_fidelity_test.dart \
  test/slide_text_fidelity_test.dart test/word_compatibility_fidelity_test.dart \
  test/word_referenced_styles_and_breaks_test.dart \
  test/comment_thread_fidelity_test.dart test/word_altchunk_fidelity_test.dart \
  test/opaque_word_test.dart \
  test/word_section_clone_fidelity_test.dart test/note_separator_fidelity_test.dart \
  test/xml_whitespace_fidelity_test.dart test/styleless_import_fidelity_test.dart \
  test/table_border_fidelity_test.dart test/word_picture_distance_fidelity_test.dart \
  test/word_edit_integrity_test.dart test/inline_field_fidelity_test.dart \
  test/scripted_transitions_test.dart
dart run tool/fidelity/scenarios.dart
python3 tool/fidelity/corpus.py verify
dart run tool/fidelity/cross_format.dart
python3 tool/fidelity/cross_oracle.py
dart run tool/fidelity/notes.dart
python3 tool/fidelity/notes_oracle.py
dart run tool/fidelity/office_steps.dart modify test/fixtures/fidelity/word.docx tool/fidelity/example_steps.json build/fidelity-script.docx
dart run tool/fidelity/office_steps.dart inspect build/fidelity-script.docx > build/fidelity-script.json
python3 tool/fidelity/styles_oracle.py
python3 tool/fidelity/native_oracle.py
python3 tool/fidelity/story_media_oracle.py
python3 tool/fidelity/lists_oracle.py build/fidelity-lists
python3 tool/fidelity/scripted_oracle.py
python3 tool/fidelity/word_compatibility_oracle.py
python3 tool/fidelity/comment_threads_oracle.py
python3 tool/fidelity/altchunk_oracle.py
python3 tool/fidelity/edge_oracle.py
python3 tool/fidelity/table_borders_oracle.py
python3 tool/fidelity/inline_fields_oracle.py
python3 tool/fidelity/audit_operations.py
python3 tool/fidelity/inventory.py verify
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
