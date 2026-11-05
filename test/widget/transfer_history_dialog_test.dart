import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/widgets/operations_panel.dart';
import 'package:crisp_cloud/widgets/transfer_history_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File source;
  late File destination;
  late TransferJournal journal;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
    root = await Directory.systemTemp.createTemp('crisp_recovery_widget_');
    source = File(p.join(root.path, 'source', 'a.txt'));
    destination = File(p.join(root.path, 'destination', 'a.txt'));
    await source.parent.create();
    await destination.parent.create();
    await source.writeAsString('verified payload');
    await destination.writeAsString('verified payload');
    final local = LocalFileService()..currentPath = root.path;
    final backend = LocalOperationBackend(local, isCurrent: () => true);
    final plan = await const FileOperationService().prepare(
      source: backend,
      destination: backend,
      targetDirectory: destination.parent.path,
      files: [(await backend.stat(source.path))!],
      options: const FileOperationOptions(kind: FileOperationKind.move),
    );
    final row = plan.entries.single;
    row.outcome = FileOperationOutcome.metadataFailed;
    row.message = 'Contents copied before interruption; cleanup remains.';
    row.recovery = {
      'phase': 'metadataFailed',
      'sourceSha256': sha256
          .convert(utf8.encode('verified payload'))
          .toString(),
      'contentSha256': sha256
          .convert(utf8.encode('verified payload'))
          .toString(),
      'dataVerified': true,
    };
    journal = TransferJournal(MemoryTransferJournalStorage());
    await journal.create('saved_move', plan);
    await journal.setStatus('saved_move', TransferJobStatus.failed);
    final secure = InMemorySecureStorage();
    final configPath = p.join(root.path, 'config.json');
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            initialProvider: CloudProvider.filen,
            config: FilenConfigService(
              configPath: configPath,
              secureStorage: secure,
            ),
            configPath: configPath,
            secureStorage: secure,
          ),
        ),
        transferJournalProvider.overrideWithValue(journal),
        localFileServiceProvider.overrideWithValue(local),
        secureStorageProvider.overrideWithValue(secure),
        configPathProvider.overrideWithValue(p.join(root.path, 'config.json')),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.runAsync(() async {
      await container.read(transferProvider).ready;
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> invoke(WidgetTester tester, String label) async {
    final finder = find.widgetWithText(FilledButton, label);
    expect(finder, findsOneWidget);
    final button = tester.widget<FilledButton>(finder);
    final dynamic callback = button.onPressed;
    await tester.runAsync(() async {
      await callback();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('review and finish a verified saved move without copying again', (
    tester,
  ) async {
    await show(tester, const TransferHistoryDialog(jobId: 'saved_move'));
    expect(find.text('Transfer history and recovery'), findsOneWidget);
    expect(find.text('Run reviewed remaining items'), findsNothing);
    await invoke(tester, 'Review saved plan');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(
      find.text('Keep verified copy; finish metadata and source cleanup'),
      findsOneWidget,
    );
    await invoke(tester, 'Run reviewed remaining items');
    expect(journal.job('saved_move')!.status, TransferJobStatus.completed);
    expect(await tester.runAsync(source.exists), isFalse);
    expect(await tester.runAsync(destination.readAsString), 'verified payload');
    final remaining = await tester.runAsync(
      () => destination.parent.list().toList(),
    );
    expect(remaining!.map((entry) => p.basename(entry.path)), ['a.txt']);
  });

  testWidgets(
    'changed sources require explicit exclusion and fit narrow windows',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => source.writeAsString('changed payload'));
      await show(tester, const TransferHistoryDialog(jobId: 'saved_move'));
      await invoke(tester, 'Review saved plan');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Source changed since the saved transfer'),
        findsOneWidget,
      );
      final run = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Run reviewed remaining items'),
      );
      expect(run.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await invoke(tester, 'Record recovered completion');
      expect(
        journal.job('saved_move')!.entries.single.outcome,
        FileOperationOutcome.skipped,
      );
      expect(await tester.runAsync(source.readAsString), 'changed payload');
      expect(
        await tester.runAsync(destination.readAsString),
        'verified payload',
      );
    },
  );

  testWidgets(
    'operations panel retains recovery and concurrency controls after hiding rows',
    (tester) async {
      await show(tester, const OperationsPanel());
      expect(find.byTooltip('Review saved transfer'), findsOneWidget);
      expect(find.text('History and recovery'), findsOneWidget);
      expect(find.text('Parallel transfers: '), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
      container.read(transferProvider).clearCompletedOperations();
      await tester.pumpAndSettle();
      expect(find.text('History and recovery'), findsOneWidget);
      expect(find.text('1 saved transfer(s)'), findsOneWidget);
    },
  );
}
