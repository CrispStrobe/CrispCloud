// Execute original suites with their original hooks and assertions.
import 'package:test/test.dart';

import '../../test/rich_note_test.dart' as suite12;
import '../../test/word_contained_text_wrap_test.dart' as suite17;
import '../../test/word_footnote_reference_test.dart' as suite9;
import '../../test/word_header_picture_identity_test.dart' as suite14;
import '../../test/word_header_picture_layout_regression_test.dart' as suite13;
import '../../test/word_header_visual_reconciliation_test.dart' as suite19;
import '../../test/word_note_bookmark_edit_test.dart' as suite10;
import '../../test/word_note_numbering_test.dart' as suite8;
import '../../test/word_note_script_break_test.dart' as suite11;
import '../../test/word_styles_layout_test.dart' as suite16;
import '../../test/word_table_cell_border_roundtrip_test.dart' as suite21;
import '../../test/word_table_direction_test.dart' as suite1;
import '../../test/word_table_grid_addressing_test.dart' as suite2;
import '../../test/word_table_nested_layout_test.dart' as suite3;
import '../../test/word_table_picture_pagination_test.dart' as suite4;
import '../../test/word_table_style_import_regression_test.dart' as suite20;
import '../../test/word_table_style_precedence_test.dart' as suite15;
import '../../test/word_table_tall_frame_layout_test.dart' as suite5;
import '../../test/word_table_tall_toc_layout_test.dart' as suite6;
import '../../test/word_table_test.dart' as suite0;
import '../../test/word_table_vertical_merge_layout_test.dart' as suite7;
import '../../test/word_vertical_table_row_geometry_test.dart' as suite18;
import 'research_target_acceptance.dart' as research;

void main() {
  group('research_target_acceptance', research.main);
  group('word_table_test.dart', suite0.main);
  group('word_table_direction_test.dart', suite1.main);
  group('word_table_grid_addressing_test.dart', suite2.main);
  group('word_table_nested_layout_test.dart', suite3.main);
  group('word_table_picture_pagination_test.dart', suite4.main);
  group('word_table_tall_frame_layout_test.dart', suite5.main);
  group('word_table_tall_toc_layout_test.dart', suite6.main);
  group('word_table_vertical_merge_layout_test.dart', suite7.main);
  group('word_note_numbering_test.dart', suite8.main);
  group('word_footnote_reference_test.dart', suite9.main);
  group('word_note_bookmark_edit_test.dart', suite10.main);
  group('word_note_script_break_test.dart', suite11.main);
  group('rich_note_test.dart', suite12.main);
  group('word_header_picture_layout_regression_test.dart', suite13.main);
  group('word_header_picture_identity_test.dart', suite14.main);
  group('word_table_style_precedence_test.dart', suite15.main);
  group('word_styles_layout_test.dart', suite16.main);
  group('word_contained_text_wrap_test.dart', suite17.main);
  group('word_vertical_table_row_geometry_test.dart', suite18.main);
  group('word_header_visual_reconciliation_test.dart', suite19.main);
  group('word_table_style_import_regression_test.dart', suite20.main);
  group('word_table_cell_border_roundtrip_test.dart', suite21.main);
}
