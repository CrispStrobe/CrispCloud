// Run the original suites in one compilation to bound compiler-cache disk use.
// Each suite retains its own group, hooks, fixtures and test implementation.
// This entrypoint does not replace the original individually runnable tests.
import 'package:test/test.dart';

import '../../test/slide_radial_opacity_test.dart' as suite10;
import '../../test/word_zotero_add_note_test.dart' as suite1;
import '../../test/word_zotero_bibliography_layout_test.dart' as suite7;
import '../../test/word_zotero_citing_test.dart' as suite3;
import '../../test/word_zotero_note_images_integration_test.dart' as suite6;
import '../../test/word_zotero_note_insertion_test.dart' as suite2;
import '../../test/word_zotero_note_list_test.dart' as suite5;
import '../../test/word_zotero_preference_flow_test.dart' as suite8;
import '../../test/word_zotero_research_target_test.dart' as suite0;
import '../../test/word_zotero_rich_edit_test.dart' as suite4;
import '../../test/word_zotero_style_preferences_review_test.dart' as suite9;

void main() {
  group('word_zotero_research_target_test.dart', suite0.main);
  group('word_zotero_add_note_test.dart', suite1.main);
  group('word_zotero_note_insertion_test.dart', suite2.main);
  group('word_zotero_citing_test.dart', suite3.main);
  group('word_zotero_rich_edit_test.dart', suite4.main);
  group('word_zotero_note_list_test.dart', suite5.main);
  group('word_zotero_note_images_integration_test.dart', suite6.main);
  group('word_zotero_bibliography_layout_test.dart', suite7.main);
  group('word_zotero_preference_flow_test.dart', suite8.main);
  group('word_zotero_style_preferences_review_test.dart', suite9.main);
  group('slide_radial_opacity_test.dart', suite10.main);
}
