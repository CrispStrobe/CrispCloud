import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_storage_native.dart';
import 'package:flutter_test/flutter_test.dart';

class _PausedBatchStorage extends NativeFileCollectionStorage {
  _PausedBatchStorage(Directory directory)
    : super(directory: () async => directory);

  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> writePreparedRecord(FileCollectionStorageRecord record) {
    if (record.key == 'fails') throw StateError('Injected write failure.');
    if (record.key == 'delayed') {
      entered.complete();
      return release.future.then((_) => super.writePreparedRecord(record));
    }
    return super.writePreparedRecord(record);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prepared record retains one matching immutable UTF-8 payload', () {
    final record = FileCollectionStorageRecord('unicode', '{"name":"資料 📁"}');
    expect(utf8.decode(record.bytes), record.value);
    expect(record.bytes, utf8.encode(record.value));
    expect(() => record.bytes[0] = 0, throwsUnsupportedError);
    expect(utf8.decode(record.bytes), record.value);
  });

  test(
    'batch limits and duplicate keys reject before any fallback writes',
    () async {
      final storage = MemoryFileCollectionStorage();
      await expectLater(
        FileCollectionStorageBatch.write(storage, [
          for (var index = 0; index < 5; index++)
            FileCollectionStorageRecord('key-$index', 'value'),
        ]),
        throwsArgumentError,
      );
      await expectLater(
        FileCollectionStorageBatch.write(storage, [
          FileCollectionStorageRecord('duplicate', 'first'),
          FileCollectionStorageRecord('duplicate', 'second'),
        ]),
        throwsArgumentError,
      );
      await expectLater(
        FileCollectionStorageBatch.write(storage, [
          FileCollectionStorageRecord(
            'too-large',
            'x' * (FileCollectionStorageBatch.maxRecordBytes + 1),
          ),
        ]),
        throwsArgumentError,
      );
      expect(storage.values, isEmpty);
      await FileCollectionStorageBatch.write(storage, [
        FileCollectionStorageRecord('first', '資料'),
        FileCollectionStorageRecord('second', '📁'),
      ]);
      expect(storage.values, {'first': '資料', 'second': '📁'});
    },
  );

  test(
    'native batch shares one directory resolution and survives reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'collection-batch-',
      );
      addTearDown(() => directory.delete(recursive: true));
      var resolutions = 0;
      final storage = NativeFileCollectionStorage(
        directory: () async {
          resolutions++;
          await Future<void>.delayed(Duration.zero);
          return directory;
        },
      );
      final records = [
        for (var index = 0; index < 4; index++)
          FileCollectionStorageRecord('page-$index', '{"資料":"📁-$index"}'),
      ];
      await storage.writeBatch(records);
      for (final record in records) {
        expect(await storage.read(record.key, maxBytes: 100), record.value);
      }
      expect(resolutions, 1);
      final reopened = NativeFileCollectionStorage(
        directory: () async => directory,
      );
      for (final record in records) {
        expect(await reopened.read(record.key, maxBytes: 100), record.value);
      }
      expect(
        (await directory.list().toList()).where(
          (entry) => entry.path.endsWith('.pending'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'a failed native directory resolution is retried by the same instance',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'collection-resolver-',
      );
      addTearDown(() => directory.delete(recursive: true));
      var resolutions = 0;
      final storage = NativeFileCollectionStorage(
        directory: () {
          resolutions++;
          if (resolutions == 1) throw StateError('Temporary platform failure.');
          return Future.value(directory);
        },
      );
      await expectLater(storage.read('first', maxBytes: 100), throwsStateError);
      await storage.write('first', 'recovered');
      expect(await storage.read('first', maxBytes: 100), 'recovered');
      expect(resolutions, 2);
    },
  );

  test('native batch failure waits for every submitted write before returning', () async {
    final directory = await Directory.systemTemp.createTemp(
      'collection-drain-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = _PausedBatchStorage(directory);
    var returned = false;
    final checked = expectLater(
      storage.writeBatch([
        FileCollectionStorageRecord('fails', 'failure'),
        FileCollectionStorageRecord('delayed', 'late durable page'),
        FileCollectionStorageRecord('ordinary', 'ordinary durable page'),
      ]),
      throwsStateError,
    ).then((_) => returned = true);
    await storage.entered.future;
    try {
      await Future<void>.delayed(Duration.zero);
      expect(returned, isFalse);
    } finally {
      storage.release.complete();
    }
    await checked;
    expect(returned, isTrue);
    expect(await storage.read('delayed', maxBytes: 100), 'late durable page');
    expect(
      await storage.read('ordinary', maxBytes: 100),
      'ordinary durable page',
    );
    // Cleanup performed only after the batch settles cannot race a late write.
    await storage.remove('delayed');
    await storage.remove('ordinary');
    expect(await directory.list().toList(), isEmpty);
  });
}
