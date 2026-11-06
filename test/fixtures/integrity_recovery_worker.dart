import 'dart:io';

import 'package:crisp_cloud/services/integrity_recovery_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/native_integrity_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final root = Platform.environment['CRISP_INTEGRITY_RECOVERY_ROOT'];
  test(
    'interrupt native split immediately after committing its second part',
    () async {
      final base = root!;
      final backend = NativeIntegrityBackend(
        afterWrite: (path) {
          if (path.endsWith('data.bin.part002')) {
            File(p.join(base, 'interrupted.marker'))
                .writeAsStringSync('committed', flush: true);
            // Deliberately skip every Dart finally and operation completion update.
            exit(71);
          }
        },
      );
      final journal = TransferJournal(
        NativeTransferJournalStorage(
          file: () async => File(p.join(base, 'journal.jsonl')),
        ),
      );
      final file = (await backend.stat(p.join(base, 'data.bin')))!;
      await IntegrityRecoveryService(journal).startSplit(
        source: backend,
        file: file,
        destination: backend,
        targetDirectory: p.join(base, 'output'),
        chunkSizeBytes: 3,
      );
      fail('The worker should terminate at the committed part.');
    },
    skip: root == null,
  );
}
