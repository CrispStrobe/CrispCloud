import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_split_service.dart';
import 'package:crisp_cloud/services/integrity_recovery_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/native_integrity_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a new process recovers flushed split evidence after the writer exits without cleanup', () async {
    final root = await Directory.systemTemp.createTemp('integrity-process-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final original = List.generate(10, (index) => index);
    await File(p.join(root.path, 'data.bin'))
        .writeAsBytes(original, flush: true);
    final output = await Directory(p.join(root.path, 'output')).create();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final executable =
        Platform.environment['CRISP_FLUTTER_EXECUTABLE'] ??
        (flutterRoot == null
            ? 'flutter'
            : p.join(
                flutterRoot,
                'bin',
                Platform.isWindows ? 'flutter.bat' : 'flutter',
              ));
    final worker = await Process.start(
      executable,
      [
        'test',
        '--no-pub',
        '--concurrency=1',
        '--reporter=expanded',
        'test/fixtures/integrity_recovery_worker.dart',
      ],
      environment: {'CRISP_INTEGRITY_RECOVERY_ROOT': root.path},
      runInShell: Platform.isWindows,
    );
    final stdout = worker.stdout.transform(utf8.decoder).join();
    final stderr = worker.stderr.transform(utf8.decoder).join();
    final code = await worker.exitCode.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        worker.kill();
        throw StateError('The interrupted worker did not exit.');
      },
    );
    expect(code, isNot(0));
    expect(
      await File(p.join(root.path, 'interrupted.marker')).exists(),
      isTrue,
      reason: '${await stdout}\n${await stderr}',
    );
    final firstPart = File(p.join(output.path, 'data.bin.part001'));
    final firstModified = await firstPart.lastModified();
    expect(await File(p.join(output.path, 'data.bin.part002')).readAsBytes(), [
      3,
      4,
      5,
    ]);

    final journal = TransferJournal(
      NativeTransferJournalStorage(
        file: () async => File(p.join(root.path, 'journal.jsonl')),
      ),
    );
    await journal.initialize();
    expect(journal.warnings, isEmpty);
    expect(journal.jobs.single.status, TransferJobStatus.interrupted);
    final backend = NativeIntegrityBackend();
    final recovery = IntegrityRecoveryService(journal);
    final review = await recovery.review(
      journal.jobs.single.id,
      source: backend,
      destination: backend,
    );
    expect(review.verifiedParts, 2);
    await recovery.resume(review, source: backend, destination: backend);
    expect(
      await firstPart.lastModified(),
      firstModified,
      reason: 'Confirmed parts must not be recopied.',
    );
    final manifest = SplitManifest.decode(
      await File(p.join(output.path, 'data.bin.split.json')).readAsBytes(),
    );
    expect(manifest.status, SplitManifestStatus.complete);
    final combined = <int>[];
    for (final part in manifest.parts) {
      combined.addAll(await File(p.join(output.path, part.path)).readAsBytes());
    }
    expect(combined, original);
    expect(await File(p.join(root.path, 'data.bin')).readAsBytes(), original);
    expect(journal.jobs.single.status, TransferJobStatus.completed);
  }, timeout: const Timeout(Duration(seconds: 150)));
}
