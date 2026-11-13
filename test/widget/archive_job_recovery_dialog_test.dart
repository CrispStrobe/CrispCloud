import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/transfer_recovery_service.dart';
import 'package:crisp_cloud/widgets/archive_job_recovery_dialog.dart';
import 'package:crisp_cloud/widgets/transfer_history_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

TransferJobRecord _job({
  String kind = 'create',
  bool password = false,
}) => TransferJobRecord(
  id: 'archive_${kind}_saved',
  created: DateTime.utc(2026, 11, 13),
  source: const StorageReference(
    kind: 'local',
    provider: 'fixture',
    accountKey: 'original',
  ),
  destination: const StorageReference(
    kind: 'local',
    provider: 'fixture',
    accountKey: 'original',
  ),
  targetDirectory: '/output',
  options: const FileOperationOptions(),
  sourceLabel: 'Original source',
  destinationLabel: 'Original destination',
  expectedEntries: 1,
  canRecover: true,
  ready: true,
  status: TransferJobStatus.interrupted,
  entries: [
    TransferEntryRecord(
      index: 0,
      source: FileItem(
        name: 'notes.txt',
        path: '/input/notes.txt',
        isFolder: false,
        size: 3,
      ),
      destination: '/output/notes.zip',
      recovery: {
        'archiveVersion': 1,
        'archiveKind': kind,
        'name': 'notes.zip',
        'format': 'zip',
        'compression': 'normal',
        'passwordRequired': password,
        'encryptNames': false,
        // Even an archive record carrying these fields cannot expose generic
        // copy/move backup restoration or infer an executable file-copy plan.
        'backupPath': '/output/saved-backup.zip',
        'backupSha256': '0' * 64,
      },
    ),
  ],
);

class _Transfers extends ChangeNotifier implements TransferNotifier {
  _Transfers(this.job);
  final TransferJobRecord job;
  final dismissed = <String>[];
  bool live = false;
  @override
  Future<void> get ready => Future.value();
  @override
  Future<void> refreshBackgroundRecovery() async {}
  @override
  List<TransferJobRecord> get savedJobs => [job];
  @override
  TransferJobRecord? savedJob(String id) => id == job.id ? job : null;
  @override
  bool isJobLive(String id) => live;
  @override
  String? get recoveryError => null;
  @override
  List<String> get recoveryWarnings => const [];
  @override
  ArchiveWorkspace? archiveWorkspaceForJob(String id) => null;
  @override
  Future<void> dismissArchiveJob(String id) async {
    dismissed.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _Transfers transfers,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [transferProvider.overrideWith((ref) => transfers)],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'archive history routes to dedicated recovery without copy actions',
    (tester) async {
      final transfers = _Transfers(_job());
      await show(
        tester,
        transfers,
        TransferHistoryDialog(jobId: transfers.job.id),
      );
      expect(
        find.byType(DropdownButtonFormField<TransferRecoveryMode>),
        findsNothing,
      );
      expect(find.text('Review saved plan'), findsNothing);
      expect(find.text('Restore backup'), findsNothing);
      final review = find.byKey(const ValueKey('archive-job-review'));
      await tester.ensureVisible(review);
      await tester.pumpAndSettle();
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveJobRecoveryDialog), findsOneWidget);
      expect(find.text('/input/notes.txt'), findsOneWidget);
      expect(find.text('Compression: Normal'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('archive-recovery-restart')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('archive-recovery-inspect')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening a protected recipe asks for password without starting it',
    (tester) async {
      final transfers = _Transfers(_job(password: true));
      await show(
        tester,
        transfers,
        ArchiveJobRecoveryDialog(jobId: transfers.job.id),
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('archive-recovery-password')),
      );
      expect(field.obscureText, isTrue);
      expect(field.controller!.text, isEmpty);
      expect(
        find.byKey(const ValueKey('archive-recovery-restart')),
        findsNothing,
      );
      expect(
        find.text(
          'Passwords are not saved with queued jobs. Enter the original password again.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a restored workspace offers publication recovery without a lost draft restart',
    (tester) async {
      final transfers = _Transfers(_job(kind: 'workspace'));
      await show(
        tester,
        transfers,
        ArchiveJobRecoveryDialog(jobId: transfers.job.id),
      );
      expect(
        find.byKey(const ValueKey('archive-recovery-publication')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('archive-recovery-save-draft')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('archive-recovery-restart')),
        findsNothing,
      );
      expect(
        find.text(
          'Only publication recovery survives an app restart. Reopen the archive to create a new draft.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an active archive cannot be inspected or restarted through recovery',
    (tester) async {
      final transfers = _Transfers(_job())..live = true;
      await show(
        tester,
        transfers,
        ArchiveJobRecoveryDialog(jobId: transfers.job.id),
      );
      expect(
        find.byKey(const ValueKey('archive-recovery-inspect')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('archive-recovery-restart')),
        findsNothing,
      );
      expect(
        find.text(
          'This archive is active in the operation queue. Use its pause or stop controls there.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('malformed archive recipes stay out of generic recovery', (
    tester,
  ) async {
    final job = _job()..entries.clear();
    final transfers = _Transfers(job);
    await show(
      tester,
      transfers,
      TransferHistoryDialog(jobId: job.id, reviewOnOpen: true),
    );
    expect(find.byType(ArchiveJobRecoveryDialog), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<TransferRecoveryMode>),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('archive-recovery-inspect')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('archive-recovery-restart')),
      findsNothing,
    );
    expect(
      find.text(
        'This saved archive recipe is incomplete. Reopen its original sources.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
