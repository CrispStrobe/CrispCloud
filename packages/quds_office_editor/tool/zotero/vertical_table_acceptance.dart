// Execute original suites with their original hooks and assertions.
// The acceptance runner runs font-sensitive baseline files in separate Flutter
// isolates: registering the Studio fonts is global for the life of an isolate.
import 'package:flutter_test/flutter_test.dart';

import 'research_target_acceptance.dart' as research;
import '../../test/word_zotero_vertical_table_controller_test.dart' as suite0;
import '../../test/word_vertical_table_hit_test.dart' as suite1;
import '../../test/word_table_grid_history_test.dart' as suite2;
import '../../test/word_keyboard_context_geometry_test.dart' as suite3;

import '../../test/word_vertical_table_row_geometry_test.dart' as suite4;

void main() {
  group('research_target_acceptance', research.main);
  group('word_zotero_vertical_table_controller_test.dart', suite0.main);
  group('word_vertical_table_hit_test.dart', suite1.main);
  group('word_table_grid_history_test.dart', suite2.main);
  group('word_keyboard_context_geometry_test.dart', suite3.main);
  group('word_vertical_table_row_geometry_test.dart', suite4.main);
}
