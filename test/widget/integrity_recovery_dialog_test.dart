import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/integrity_recovery.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/integrity_recovery_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/widgets/integrity_recovery_dialog.dart';
import 'package:crisp_cloud/widgets/transfer_history_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String? get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final WorkflowFakeClient client;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail = 'fixture@example.test';
  @override
  String get providerName => client.providerName;
  @override
  CloudProvider get currentProvider => CloudProvider.sftp;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnreadableJournalStorage extends MemoryTransferJournalStorage {
  @override
  Future<List<String>> readLines() async =>
      throw const FileSystemException('Recovery journal is unavailable.');
}

void main() {
  late WorkflowFakeClient cloud;
  late TransferJournal journal;
  late IntegrityRecoveryDefinition definition;
  late String jobId;
  late ProviderContainer container;
  const original = [1, 2, 3, 4, 5, 6];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = WorkflowFakeClient()..put('/data.bin', original);
    final backend = CloudOperationBackend(
      cloud,
      isCurrent: () => cloud.current,
    );
    final storage = MemoryTransferJournalStorage();
    final firstSession = TransferJournal(storage);
    final job = await IntegrityRecoveryService(firstSession).prepareSplit(
      source: backend,
      file: (await backend.stat('/data.bin'))!,
      destination: backend,
      targetDirectory: '/',
      chunkSizeBytes: 2,
    );
    jobId = job.id;
    definition = IntegrityRecoveryDefinition.fromJob(job);
    final firstPart = job.entries[definition.parts.first.index];
    await firstSession.checkpoint(
      jobId,
      definition.parts.first.index,
      FileOperationEntry(firstPart.source, firstPart.destination)
        ..recovery = {...firstPart.recovery, 'phase': 'committing'},
      'committing',
    );
    // Simulate a committed first part whose acknowledgement was interrupted.
    cloud.put(definition.parts.first.destination, original.take(2).toList());
    journal = TransferJournal(storage);
    await journal.initialize();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        transferJournalProvider.overrideWithValue(journal),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> show(
    WidgetTester tester, {
    String language = 'en',
    bool narrow = false,
    bool history = false,
  }) async {
    if (narrow) {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.runAsync(() => container.read(transferProvider).ready);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: history
                ? TransferHistoryDialog(jobId: jobId)
                : IntegrityRecoveryDialog(jobId: jobId),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => container.read(transferProvider).refreshIntegrityHistory(),
    );
    await tester.pumpAndSettle();
  }

  Future<void> inspect(WidgetTester tester, {String language = 'en'}) async {
    final label = CommanderStrings.forLanguage(
      language,
      'Review integrity recovery',
    );
    final button = find.widgetWithText(OutlinedButton, label);
    await tester.ensureVisible(button);
    final dynamic callback = tester.widget<OutlinedButton>(button).onPressed;
    await tester.runAsync(() async {
      await callback();
    });
    await tester.pumpAndSettle();
  }

  Future<void> continueRecovery(WidgetTester tester) async {
    final button = find.widgetWithText(
      FilledButton,
      'Resume missing split parts',
    );
    final dynamic callback = tester.widget<FilledButton>(button).onPressed;
    await tester.runAsync(() async {
      await callback();
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a journal read failure is shown instead of an empty recovery list',
    (tester) async {
      container.dispose();
      journal = TransferJournal(_UnreadableJournalStorage());
      container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => _Auth(cloud)),
          secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
          transferJournalProvider.overrideWithValue(journal),
          localFileServiceProvider.overrideWithValue(_Local()),
        ],
      );

      await show(tester);

      expect(
        find.textContaining('Recovery journal is unavailable.'),
        findsOneWidget,
      );
      expect(find.text('No saved split or combine operations.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restart recovery verifies existing parts and writes only missing parts',
    (tester) async {
      await show(tester);
      final destinationPanel = container.read(panelProvider(PanelSide.remote));
      await tester.runAsync(() async {
        container
            .read(panelSourceProvider(PanelSide.remote).notifier)
            .setSource(
              RemotePanelSource(
                providerName: cloud.providerName,
                client: cloud,
                path: '/',
              ),
            );
        await destinationPanel.refresh();
      });
      expect(
        destinationPanel.files!.map((file) => file.path),
        isNot(contains(definition.parts.last.destination)),
      );
      await inspect(tester);
      expect(
        find.text('1 of 3 parts verified. Only missing parts will be written.'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join('\n'),
      );
      expect(cloud.writes, isEmpty);
      final retainedFirstPart = cloud.files[definition.parts.first.destination];

      await continueRecovery(tester);

      expect(journal.job(jobId)!.status, TransferJobStatus.completed);
      expect(cloud.files['/data.bin'], original);
      expect(
        identical(
          cloud.files[definition.parts.first.destination],
          retainedFirstPart,
        ),
        isTrue,
      );
      expect(
        cloud.writes.where(
          (path) => path == definition.parts.first.destination,
        ),
        isEmpty,
      );
      for (var index = 0; index < definition.parts.length; index++) {
        expect(
          cloud.files[definition.parts[index].destination],
          original.sublist(index * 2, index * 2 + 2),
        );
      }
      expect(
        destinationPanel.files!.map((file) => file.path),
        containsAll([
          for (final part in definition.parts) part.destination,
          definition.outputPath,
        ]),
      );
      expect(
        find.widgetWithText(FilledButton, 'Resume missing split parts'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source changes after review block continuation before new writes',
    (tester) async {
      await show(tester);
      await inspect(tester);
      cloud.put('/data.bin', [
        1,
        2,
        3,
        4,
        9,
        9,
      ], date: DateTime.utc(2025, 1, 1));
      await continueRecovery(tester);

      expect(cloud.writes, isEmpty);
      expect(cloud.files[definition.parts[1].destination], isNull);
      expect(find.textContaining('changed'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Resume missing split parts'),
        findsNothing,
      );
      expect(journal.job(jobId)!.isFinished, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transfer history routes integrity work to its dedicated recovery dialog',
    (tester) async {
      await show(tester, history: true);
      expect(find.text('Resume / retry remaining'), findsNothing);
      final review = find.widgetWithText(
        FilledButton,
        'Review split/combine recovery',
      );
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pump();
      await tester.runAsync(
        () => container.read(transferProvider).refreshIntegrityHistory(),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IntegrityRecoveryDialog), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Review integrity recovery'),
        findsOneWidget,
      );
      expect(cloud.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'forgetting recovery keeps files and removes stale operations-panel progress',
    (tester) async {
      await show(tester);
      expect(
        container
            .read(transferProvider)
            .operations
            .any((operation) => operation.id == jobId),
        isTrue,
      );
      Future<void>? forgetting;
      final dynamic callback = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Forget recovery, keep files'),
          )
          .onPressed;
      await tester.runAsync(() async {
        forgetting = callback() as Future<void>;
      });
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Forget recovery, keep files'),
      );
      await tester.runAsync(() => forgetting!);
      await tester.pumpAndSettle();

      expect(journal.job(jobId), isNull);
      expect(cloud.files['/data.bin'], original);
      expect(
        cloud.files[definition.parts.first.destination],
        original.take(2).toList(),
      );
      expect(
        container
            .read(transferProvider)
            .operations
            .any((operation) => operation.id == jobId),
        isFalse,
      );
      expect(
        find.text('No saved split or combine operations.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['de', 'ar']) {
    testWidgets('reviewed recovery controls fit large narrow $language text', (
      tester,
    ) async {
      await show(tester, language: language, narrow: true);
      await inspect(tester, language: language);
      final resume = find.widgetWithText(
        FilledButton,
        CommanderStrings.forLanguage(language, 'Resume missing split parts'),
      );
      await tester.ensureVisible(resume);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
      expect(cloud.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
