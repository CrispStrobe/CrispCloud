import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _JournalBackend extends FileOperationBackend {
  _JournalBackend(this.label);
  @override
  final String label;
  @override
  StorageReference get storageReference =>
      StorageReference(kind: 'remote', provider: 'test', accountKey: label);
  @override
  Object get identity => storageReference.id;
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent => true;
  @override
  bool get canRecover => true;
  // These tests only persist a reviewed plan. No storage I/O is permitted.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage I/O: ${invocation.memberName}');
}

FileOperationPlan _plan() => FileOperationPlan(
  source: _JournalBackend('source'),
  destination: _JournalBackend('destination'),
  targetDirectory: '/target',
  options: const FileOperationOptions(kind: FileOperationKind.move),
  entries: [
    FileOperationEntry(
      FileItem(name: 'a.txt', path: '/a.txt', isFolder: false, size: 12),
      '/target/a.txt',
    ),
  ],
  errors: [],
);

void main() {
  test(
    'scheduled jobs survive replay and compaction but require review',
    () async {
      final storage = MemoryTransferJournalStorage();
      final journal = TransferJournal(storage);
      final instant = DateTime.parse('2027-02-03T17:15:00+02:00');
      final job = await journal.create(
        'scheduled',
        _plan(),
        scheduledAt: instant,
      );
      expect(job.scheduledAt, DateTime.utc(2027, 2, 3, 15, 15));
      expect(job.toHeaderJson()['scheduledAt'], '2027-02-03T15:15:00.000Z');
      await journal.updateQueue('scheduled', priority: 10, queueOrder: 4);
      await journal.compact();
      final reopened = TransferJournal(storage);
      await reopened.initialize();
      expect(reopened.job('scheduled')!.scheduledAt, instant);
      expect(reopened.job('scheduled')!.priority, 10);
      expect(reopened.job('scheduled')!.queueOrder, 4);
      expect(reopened.job('scheduled')!.status, TransferJobStatus.interrupted);
      expect(reopened.job('scheduled')!.ready, isTrue);
    },
  );

  test(
    'reschedule and explicit clear replay independently of priority',
    () async {
      final storage = MemoryTransferJournalStorage();
      final journal = TransferJournal(storage);
      await journal.create('job', _plan());
      final start = DateTime.utc(2027, 3, 1);
      await journal.updateQueue('job', scheduledAt: start);
      await journal.updateQueue('job', priority: -10);
      expect(journal.job('job')!.scheduledAt, start);
      await journal.updateQueue('job', clearScheduledAt: true);
      await journal.compact();
      final reopened = TransferJournal(storage);
      await reopened.initialize();
      expect(reopened.job('job')!.scheduledAt, isNull);
      expect(reopened.job('job')!.priority, -10);
      await expectLater(
        reopened.updateQueue('job', scheduledAt: start, clearScheduledAt: true),
        throwsArgumentError,
      );
    },
  );

  test('old job headers without a schedule remain readable', () async {
    final journal = TransferJournal(MemoryTransferJournalStorage());
    final job = await journal.create('legacy', _plan());
    final oldHeader = job.toHeaderJson()..remove('scheduledAt');
    expect(TransferJobRecord.fromHeaderJson(oldHeader).scheduledAt, isNull);
  });
}
