import 'dart:convert';

import 'package:crisp_cloud/services/file_selection_pattern.dart';
import 'package:crisp_cloud/services/selection_pattern_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('recalls all matching options across service instances', () async {
    final pattern = FileSelectionPattern(
      r'^/photos/IMG_\d+\.JPG$',
      mode: FilePatternMode.regex,
      caseSensitive: true,
      matchFullPath: true,
      includeFolders: false,
    );
    await SelectionPatternHistory().remember(pattern);
    final restored = (await SelectionPatternHistory().load()).single;
    expect(restored.toJson(), pattern.toJson());
  });

  test('simultaneous dialogs preserve history and recall moves a pattern first', () async {
    final first = SelectionPatternHistory();
    final second = SelectionPatternHistory();
    await Future.wait([
      first.remember(FileSelectionPattern('*.jpg')),
      second.remember(FileSelectionPattern('*.png')),
    ]);
    expect((await first.load()).map((p) => p.expression), ['*.png', '*.jpg']);
    await second.remember(FileSelectionPattern('*.jpg'));
    expect((await first.load()).map((p) => p.expression), ['*.jpg', '*.png']);
  });

  test('history is bounded and invalid persisted entries do not hide usable ones', () async {
    final history = SelectionPatternHistory();
    for (var i = 0; i < SelectionPatternHistory.maxEntries + 2; i++) {
      await history.remember(FileSelectionPattern('file-$i.*'));
    }
    final entries = await history.load();
    expect(entries.length, SelectionPatternHistory.maxEntries);
    expect(entries.first.expression, 'file-21.*');
    expect(entries.last.expression, 'file-2.*');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(SelectionPatternHistory.storageKey, [
      'not json',
      jsonEncode({'expression': '*', 'mode': 'unknown'}),
      jsonEncode(FileSelectionPattern('*.txt').toJson()),
      jsonEncode(FileSelectionPattern('*.txt').toJson()),
      'null',
    ]);
    expect((await history.load()).map((p) => p.expression), ['*.txt']);
  });
}
