// Run the original suites in one compilation to bound compiler-cache disk use.
// Each suite retains its own group, hooks, fixtures and test implementation.
// This entrypoint does not replace the original individually runnable tests.
import 'package:flutter_test/flutter_test.dart';

import '../../example/test/studio_comment_draft_proofing_test.dart' as suite10;
import '../../example/test/studio_word_chrome_settle_test.dart' as suite12;
import '../../test/word_incremental_layout_equivalence_test.dart' as suite11;
import '../../test/word_proofing_capture_cache_test.dart' as suite9;
import '../../test/word_proofing_session_test.dart' as suite8;
import '../../test/word_zotero_add_note_controller_test.dart' as suite0;
import '../../test/word_zotero_adjacent_citations_controller_test.dart'
    as suite13;
import '../../test/word_zotero_bibliography_controller_test.dart' as suite6;
import '../../test/word_zotero_citing_controller_test.dart' as suite3;
import '../../test/word_zotero_citing_dialog_test.dart' as suite4;
import '../../test/word_zotero_direct_command_test.dart' as suite5;
import '../../test/word_zotero_note_image_controller_test.dart' as suite2;
import '../../test/word_zotero_note_target_test.dart' as suite1;
import '../../test/word_zotero_rich_controller_test.dart' as suite7;

void main() {
  group('word_zotero_adjacent_citations_controller_test.dart', suite13.main);
  group('word_incremental_layout_equivalence_test.dart', suite11.main);
  group('word_zotero_add_note_controller_test.dart', suite0.main);
  group('word_zotero_note_target_test.dart', suite1.main);
  group('word_zotero_note_image_controller_test.dart', suite2.main);
  group('word_zotero_citing_controller_test.dart', suite3.main);
  group('word_zotero_citing_dialog_test.dart', suite4.main);
  group('word_zotero_direct_command_test.dart', suite5.main);
  group('word_zotero_bibliography_controller_test.dart', suite6.main);
  group('word_zotero_rich_controller_test.dart', suite7.main);
  group('word_proofing_session_test.dart', suite8.main);
  group('word_proofing_capture_cache_test.dart', suite9.main);
  group('studio_comment_draft_proofing_test.dart', suite10.main);
  group('studio_word_chrome_settle_test.dart', suite12.main);
}
