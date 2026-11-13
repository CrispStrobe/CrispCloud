import 'dart:convert';

import 'package:crisp_cloud/models/archive_job.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_job_journal.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:flutter_test/flutter_test.dart';

ArchiveJobRecord record({String id = 'job-00000001', bool protected = false}) =>
    ArchiveJobRecord(
      request: ArchiveJobRequest(
        id: id,
        storageId: 'local:test:jobs',
        created: DateTime.utc(2026),
        destinationDirectory: '/output',
        name: 'copy.7z',
        format: ArchiveCreationFormat.sevenZip,
        compression: ArchiveCreationCompression.lzma2,
        passwordRequired: protected,
        encryptNames: protected,
        files: [
          FileItem(
            name: 'file.txt',
            path: '/input/file.txt',
            isFolder: false,
            size: 12,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      ),
      status: ArchiveJobStatus.queued,
      updated: DateTime.utc(2026),
    );

class _LostAcknowledgement extends MemoryFileCollectionStorage {
  bool failBefore = false;
  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    if (failBefore) throw StateError('Disk failure before write');
    await super.compareAndSwap(key, expected, value);
    throw StateError('Acknowledgement lost after durable write');
  }
}

void main() {
  test(
    'journal round trip preserves an immutable selection without a password',
    () async {
      final store = MemoryFileCollectionStorage();
      final journal = ArchiveJobJournal(storage: store);
      final selected = record(protected: true);
      expect(
        selected.request.options(password: 'secret-🔒').password,
        'secret-🔒',
      );
      await journal.replace([selected], paused: true);
      final reloaded = ArchiveJobJournal(storage: store);
      await reloaded.load();
      expect(reloaded.records.single.toJson(), selected.toJson());
      expect(reloaded.paused, isTrue);
      expect(store.values.values.single, isNot(contains('secret-🔒')));
      expect(store.values.values.single, isNot(contains('validation-only')));
      expect(() => reloaded.records.single.request.options(), throwsStateError);
      expect(() => reloaded.records.clear(), throwsUnsupportedError);
      expect(
        () => reloaded.records.single.request.files.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('unknown or credential-bearing persisted fields are refused', () {
    for (final field in ['password', 'token', 'shellCommand', 'futureField']) {
      final value =
          jsonDecode(jsonEncode(record().toJson())) as Map<String, dynamic>;
      (value['request'] as Map)[field] = 'must not be accepted';
      expect(() => ArchiveJobRecord.fromJson(value), throwsFormatException);
    }
  });

  test('unsafe persisted destinations and source selections are refused', () {
    for (final path in [
      'relative',
      '/input/../elsewhere',
      '/input/\u0000bad',
    ]) {
      final value =
          jsonDecode(jsonEncode(record().toJson())) as Map<String, dynamic>;
      (value['request'] as Map)['directory'] = path;
      expect(() => ArchiveJobRecord.fromJson(value), throwsFormatException);
    }
    final duplicate =
        jsonDecode(jsonEncode(record().toJson())) as Map<String, dynamic>;
    final files = (duplicate['request'] as Map)['files'] as List;
    files.add(files.single);
    expect(() => ArchiveJobRecord.fromJson(duplicate), throwsFormatException);
  });

  test('receipts bind the exact destination, size, entries and hash', () {
    final original = record();
    for (final prepared in [
      ArchiveCreationPrepared('/other/copy.7z', 1, 10, 'a' * 64),
      ArchiveCreationPrepared(original.request.outputPath, 1, -1, 'a' * 64),
      ArchiveCreationPrepared(
        original.request.outputPath,
        200001,
        10,
        'a' * 64,
      ),
      ArchiveCreationPrepared(
        original.request.outputPath,
        1,
        10,
        'not-a-sha256',
      ),
    ]) {
      final value = original
          .change(ArchiveJobStatus.running, prepared: prepared)
          .toJson();
      expect(
        () => ArchiveJobRecord.fromJson(Map<String, dynamic>.from(value)),
        throwsFormatException,
      );
    }
    expect(
      () => ArchiveJobRecord.fromJson(
        Map<String, dynamic>.from(
          original.change(ArchiveJobStatus.completed).toJson(),
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'lost write acknowledgement is reconciled only by exact persisted bytes',
    () async {
      final store = _LostAcknowledgement();
      final journal = ArchiveJobJournal(storage: store);
      await journal.replace([record()]);
      expect(journal.records.length, 1);
      store.failBefore = true;
      await expectLater(
        journal.replace([record(id: 'job-00000002')]),
        throwsStateError,
      );
      expect(journal.records.single.id, 'job-00000001');
      final reloaded = ArchiveJobJournal(storage: store);
      await reloaded.load();
      expect(reloaded.records.single.id, 'job-00000001');
    },
  );

  test(
    'stale catalog writers cannot replace another owner’s job history',
    () async {
      final store = MemoryFileCollectionStorage();
      final first = ArchiveJobJournal(storage: store);
      final second = ArchiveJobJournal(storage: store);
      await first.load();
      await second.load();
      await first.replace([record()]);
      await expectLater(
        second.replace([record(id: 'job-00000002')]),
        throwsStateError,
      );
      await second.load();
      expect(second.records.single.id, 'job-00000001');
    },
  );

  test(
    'record count and duplicate IDs are checked before publication',
    () async {
      final store = MemoryFileCollectionStorage();
      final journal = ArchiveJobJournal(storage: store);
      await expectLater(
        journal.replace([record(), record()]),
        throwsStateError,
      );
      await expectLater(
        journal.replace(
          List.generate(
            129,
            (i) => record(id: 'job-${i.toString().padLeft(8, '0')}'),
          ),
        ),
        throwsStateError,
      );
      expect(store.values, isEmpty);
    },
  );

  test(
    'malformed, oversized and future catalogs leave storage unchanged',
    () async {
      final store = MemoryFileCollectionStorage();
      for (final raw in [
        '{',
        '{"version":2,"records":[],"paused":false}',
        'x' * (ArchiveJobJournal.maximumBytes + 1),
      ]) {
        store.values[ArchiveJobJournal.key] = raw;
        await expectLater(
          ArchiveJobJournal(storage: store).load(),
          throwsA(anything),
        );
        expect(store.values[ArchiveJobJournal.key], raw);
      }
    },
  );
}
