import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/document_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FileReference file(String path, {String account = 'one'}) => FileReference(
  storage: StorageReference(
    kind: 'remote',
    provider: 'webdav',
    accountKey: account,
  ),
  path: path,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'edits persist, opened logging is opt-in, accounts remain distinct',
    () async {
      final history = DocumentHistory();
      await history.ready;
      await history.record(file('/one.txt'), edited: false);
      expect(history.entries, isEmpty);
      await history.record(file('/one.txt'), edited: true);
      await history.record(file('/one.txt', account: 'two'), edited: true);
      await history.configure(edits: true, opens: true);
      await history.record(file('/one.txt'), edited: false);
      expect(history.entries, hasLength(2));
      expect(history.entries.first.openedAt, isNotNull);
      final restored = DocumentHistory();
      await restored.ready;
      expect(restored.entries, hasLength(2));
      expect(restored.recordOpens, isTrue);
      history.dispose();
      restored.dispose();
    },
  );
  test(
    'export/import merges by storage and path, never enables logging',
    () async {
      final a = DocumentHistory();
      await a.record(file('/a'), edited: true);
      final json = a.exportJson();
      expect(json, isNot(contains('objectId')));
      final b = DocumentHistory();
      await b.record(file('/b'), edited: true);
      await b.importJson(json);
      await b.importJson(json);
      expect(b.entries, hasLength(2));
      expect(b.recordOpens, isFalse);
      await b.importJson(json, replace: true);
      expect(b.entries.single.file.path, '/a');
      a.dispose();
      b.dispose();
    },
  );
  test(
    'purge during preference loading cancels old loading and queued events',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final old = DocumentHistory();
      await old.record(file('/old'), edited: true);
      old.dispose();
      final gate = Completer<SharedPreferences>();
      final history = DocumentHistory(preferences: () => gate.future);
      final pending = history.record(file('/queued'), edited: true);
      final purge = history.purge();
      gate.complete(prefs);
      await Future.wait([pending, purge]);
      expect(history.entries, isEmpty);
      final restarted = DocumentHistory();
      await restarted.ready;
      expect(restarted.entries, isEmpty);
      history.dispose();
      restarted.dispose();
    },
  );
  test('invalid replacement is atomic; unsupported schema and missing dates rejected', () async {
    final history = DocumentHistory();
    await history.record(file('/keep'), edited: true);
    for (final raw in [
      'not json',
      '{"version":2,"entries":[]}',
      '{"version":1,"entries":[{}]}',
    ]) {
      await expectLater(
        history.importJson(raw, replace: true),
        throwsA(anything),
      );
      expect(history.entries.single.file.path, '/keep');
    }
    final invalid = {
      'version': 1,
      'entries': [
        {'file': file('/bad').toJson()},
      ],
    };
    expect(
      () => DocumentHistory.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
    history.dispose();
  });
  test('1000-entry retention and export remain loadable', () async {
    final history = DocumentHistory();
    await history.ready;
    final date = DateTime.utc(2025);
    await history.importJson(
      jsonEncode({
        'version': 1,
        'entries': [
          for (var i = 0; i < 1000; i++)
            DocumentHistoryEntry(
              file: file('/$i'),
              editedAt: date.add(Duration(seconds: i)),
            ).toJson(),
        ],
      }),
    );
    await history.record(file('/new'), edited: true);
    expect(history.entries, hasLength(1000));
    expect(history.entries.any((e) => e.file.path == '/0'), isFalse);
    expect(DocumentHistory.decode(history.exportJson()), hasLength(1000));
    history.dispose();
  });
  test(
    'disabled edits and persistence failures never interrupt document saves',
    () async {
      final history = DocumentHistory();
      await history.configure(edits: false, opens: false);
      await history.record(file('/ignored'), edited: true);
      expect(history.entries, isEmpty);
      history.dispose();
      final failed = DocumentHistory(
        preferences: () => Future.error(StateError('preferences offline')),
      );
      await failed.record(file('/saved'), edited: true);
      expect(failed.entries, hasLength(1));
      expect(failed.persistenceError, contains('preferences offline'));
      failed.dispose();
    },
  );
}
