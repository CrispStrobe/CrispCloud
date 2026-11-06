import 'dart:io';

import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a valid last checkpoint without a newline survives the next mutation and restart', () async {
    final directory = await Directory.systemTemp.createTemp('journal-newline-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'journal.jsonl'));
    final storage = NativeTransferJournalStorage(file: () async => file);
    final source = TransferJobRecord(
      id: 'background-source',
      created: DateTime.utc(2026),
      source: null,
      destination: null,
      targetDirectory: '/target',
      options: const FileOperationOptions(),
      sourceLabel: 'Source',
      destinationLabel: 'Destination',
      expectedEntries: 0,
      canRecover: false,
      ready: true,
      status: TransferJobStatus.completed,
    );
    final id = 'bg_${'a' * 64}';
    await TransferJournal(storage).importRecord(source, importedId: id);
    final data = await file.readAsString();
    expect(data.endsWith('\n'), isTrue);
    await file.writeAsString(data.substring(0, data.length - 1), flush: true);
    final restarted = TransferJournal(storage);
    await restarted.initialize();
    expect(restarted.jobs, hasLength(1));
    await restarted.dismiss(id);
    final reopened = TransferJournal(storage);
    await reopened.initialize();
    expect(reopened.warnings, isEmpty);
    expect(reopened.jobs, isEmpty);
    expect(await reopened.importRecord(source, importedId: id), isFalse);
  });
}
