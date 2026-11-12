#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Generate every required output before running the independent oracles. Missing
# or stale/incomplete inventories fail; this command never regenerates goldens.
python3 tool/fidelity/inventory.py clean
dart test \
  test/legacy_word_document_test.dart test/bounded_cfb_reader_test.dart \
  test/word_package_preservation_test.dart test/zip_bounded_read_test.dart \
  test/drawing_line_style_test.dart \
  test/office_fidelity_oracle_test.dart test/office_steps_test.dart \
  test/scripted_workflows_test.dart test/numbering_collision_test.dart \
  test/list_restart_fidelity_test.dart test/rich_note_test.dart \
  test/native_presentation_test.dart test/native_spreadsheet_test.dart \
  test/slide_section_fidelity_test.dart \
  test/style_cascade_test.dart test/story_media_fidelity_test.dart \
  test/word_part_routing_test.dart test/sheet_schema_fidelity_test.dart \
  test/slide_text_fidelity_test.dart test/word_compatibility_fidelity_test.dart \
  test/word_referenced_styles_and_breaks_test.dart \
  test/comment_thread_fidelity_test.dart test/word_altchunk_fidelity_test.dart \
  test/opaque_word_test.dart test/note_edit_test.dart test/note_marker_merge_test.dart \
  test/word_section_clone_fidelity_test.dart test/note_separator_fidelity_test.dart \
  test/note_chrome_fidelity_test.dart \
  test/xml_whitespace_fidelity_test.dart test/styleless_import_fidelity_test.dart \
  test/table_border_fidelity_test.dart test/word_picture_distance_fidelity_test.dart \
  test/note_marker_legacy_fidelity_test.dart \
  test/bookmark_fidelity_test.dart test/content_control_fidelity_test.dart \
  test/word_edit_integrity_test.dart test/inline_field_fidelity_test.dart \
  test/word_structure_steps_test.dart test/word_structure_integrity_test.dart \
  test/word_revision_story_test.dart test/word_step_atomicity_test.dart \
  test/word_bibliography_fidelity_test.dart test/note_marker_fidelity_test.dart \
  test/word_note_script_break_test.dart \
  test/word_revision_validation_test.dart test/word_tree_test.dart \
  test/word_frame_wrap_test.dart test/variable_line_breaker_test.dart \
  test/word_content_control_fidelity_test.dart test/word_bookmark_fidelity_test.dart \
  test/word_find_replace_atomic_test.dart \
  test/word_note_bookmark_edit_test.dart \
  test/word_table_nested_layout_test.dart test/word_table_tall_toc_layout_test.dart \
  test/word_table_tall_frame_layout_test.dart test/word_table_picture_pagination_test.dart \
  test/word_auxiliary_content_control_test.dart test/word_native_presentation_test.dart \
  test/word_style_introduction_test.dart test/word_table_direction_test.dart \
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
python3 tool/fidelity/slide_sections_oracle.py
python3 tool/fidelity/story_media_oracle.py
python3 tool/fidelity/lists_oracle.py build/fidelity-lists
python3 tool/fidelity/scripted_oracle.py
python3 tool/fidelity/word_compatibility_oracle.py
python3 tool/fidelity/comment_threads_oracle.py
python3 tool/fidelity/altchunk_oracle.py
python3 tool/fidelity/edge_oracle.py
python3 tool/fidelity/table_borders_oracle.py
python3 tool/fidelity/note_markers_legacy_oracle.py
python3 tool/fidelity/bookmarks_oracle.py
python3 tool/fidelity/content_controls_oracle.py
python3 tool/fidelity/inline_fields_oracle.py
python3 tool/fidelity/word_structure_oracle.py
python3 tool/fidelity/revision_story_oracle.py
python3 tool/fidelity/bibliography_oracle.py
python3 tool/fidelity/note_markers_oracle.py
python3 tool/fidelity/frame_wrap_oracle.py
python3 tool/fidelity/content_control_oracle.py
python3 tool/fidelity/auxiliary_content_control_oracle.py
python3 tool/fidelity/bookmark_ranges_oracle.py
python3 tool/fidelity/unsupported_word_audit.py
python3 tool/fidelity/audit_operations.py
python3 tool/fidelity/inventory.py verify
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
