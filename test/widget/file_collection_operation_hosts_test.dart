import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/providers/file_clipboard_provider.dart';
import 'package:crisp_cloud/providers/file_collection_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/widgets/file_attributes_dialog.dart';
import 'package:crisp_cloud/widgets/file_clipboard_actions.dart';
import 'package:crisp_cloud/widgets/integrity_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => '/';
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async => [];
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
  String? get userEmail => 'fixture@example.test';
  @override
  String get providerName => client.providerName;
  @override
  CloudProvider get currentProvider => CloudProvider.sftp;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WorkflowFakeClient cloud;
  late FileCollectionStore store;
  late TransferJournal journal;
  late ProviderContainer container;
  late PanelNotifier panel;
  String? clipboardText;
  Future<void>? openedDialog;
  const firstPath = '/file-000.bin';
  const lastPath = '/file-500.bin';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = WorkflowFakeClient();
    final storage = storageReferenceForClient(cloud);
    final entries = <FileCollectionEntry>[];
    for (var index = 0; index <= 500; index++) {
      final name = 'file-${index.toString().padLeft(3, '0')}.bin';
      cloud.put('/$name', [index % 256]);
      entries.add(
        FileCollectionService.capture(
          FileItem(
            name: name,
            path: '/$name',
            isFolder: false,
            size: 1,
            updatedAt: DateTime.utc(2025, 1, 1),
          ),
          storage,
        ),
      );
    }
    store = FileCollectionStore(storage: MemoryFileCollectionStorage());
    journal = TransferJournal(MemoryTransferJournalStorage());
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        fileCollectionStoreProvider.overrideWith((_) => store),
        transferJournalProvider.overrideWithValue(journal),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    await store.save(
      FileCollection(
        id: 'host-fixture',
        name: 'Marked originals',
        entries: entries,
        selectedKeys: {entries.first.key, entries.last.key},
      ),
    );
    await panel.openCollection('host-fixture');
    expect(panel.files, hasLength(500));
    expect(panel.files!.map((file) => file.path), isNot(contains(lastPath)));
    expect(panel.selection, hasLength(2));
    clipboardText = null;
    openedDialog = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          if (call.method == 'Clipboard.getData')
            return {'text': clipboardText};
          return null;
        });
  });
  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> showHost(WidgetTester tester) async {
    await tester.runAsync(() => container.read(transferProvider).ready);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Column(
                children: [
                  for (final cut in [false, true])
                    TextButton(
                      onPressed: () => copyFilesToClipboard(
                        context,
                        ref,
                        PanelSide.remote,
                        cut: cut,
                      ),
                      child: Text(cut ? 'Cut marks' : 'Copy marks'),
                    ),
                  TextButton(
                    onPressed: () => showFileAttributesDialog(
                      context,
                      ref,
                      PanelSide.remote,
                      panel.selection.toList(),
                    ),
                    child: const Text('Attributes for marks'),
                  ),
                  TextButton(
                    onPressed: () => showChecksumToolsDialog(
                      context,
                      ref,
                      PanelSide.remote,
                      panel.selection.toList(),
                    ),
                    child: const Text('Checksums for marks'),
                  ),
                  TextButton(
                    onPressed: () => showSplitFileDialog(
                      context,
                      ref,
                      PanelSide.remote,
                      panel.selection.singleWhere(
                        (file) => file.path == lastPath,
                      ),
                    ),
                    child: const Text('Split off-page original'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester, String title) async {
    final dynamic callback = tester
        .widget<TextButton>(find.widgetWithText(TextButton, title))
        .onPressed;
    await tester.runAsync(() async {
      openedDialog = callback() as Future<void>;
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  Future<void> closeDialog(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.runAsync(() => openedDialog!);
    await tester.pumpAndSettle();
  }

  for (final cut in [false, true]) {
    testWidgets(
      '${cut ? 'cut' : 'copy'} captures both visible and off-page originals',
      (tester) async {
        await showHost(tester);
        final dynamic callback = tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, cut ? 'Cut marks' : 'Copy marks'),
            )
            .onPressed;
        await tester.runAsync(() async {
          await callback();
        });
        await tester.pumpAndSettle();

        final selection = container.read(fileClipboardProvider).selection!;
        expect(selection.files.map((file) => file.path).toSet(), {
          firstPath,
          lastPath,
        });
        expect(selection.cut, cut);
        expect(selection.isCurrent, isTrue);
        expect(clipboardText, startsWith('crispcloud://file-selection/'));
        expect(cloud.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a missing off-page original blocks clipboard capture completely',
    (tester) async {
      cloud.files.remove(lastPath);
      await showHost(tester);
      final dynamic callback = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Copy marks'))
          .onPressed;
      await tester.runAsync(() async {
        await callback();
      });
      await tester.pumpAndSettle();

      expect(container.read(fileClipboardProvider).selection, isNull);
      expect(clipboardText, isNull);
      expect(find.textContaining(lastPath), findsOneWidget);
      expect(cloud.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'attribute review includes the marked original outside the window',
    (tester) async {
      await showHost(tester);
      await openDialog(tester, 'Attributes for marks');
      final dialog = tester.widget<FileAttributesDialog>(
        find.byType(FileAttributesDialog),
      );
      expect(dialog.targets.map((target) => target.file.path).toSet(), {
        firstPath,
        lastPath,
      });
      expect(cloud.writes, isEmpty);
      await closeDialog(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('checksums read both marked originals across collection pages', (
    tester,
  ) async {
    await showHost(tester);
    await openDialog(tester, 'Checksums for marks');
    expect(find.text('Checksums · 2 file(s)'), findsOneWidget);
    final dynamic calculate = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Calculate'))
        .onPressed;
    await tester.runAsync(() async {
      await calculate();
    });
    await tester.pumpAndSettle();
    expect(find.text('Memory: $firstPath'), findsOneWidget);
    expect(find.text('Memory: $lastPath'), findsOneWidget);
    expect(cloud.writes, isEmpty);
    await closeDialog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'splitting an off-page original records verified durable completion',
    (tester) async {
      await showHost(tester);
      await openDialog(tester, 'Split off-page original');
      final dynamic split = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Split and verify'),
          )
          .onPressed;
      await tester.runAsync(() async {
        await split();
      });
      await tester.pumpAndSettle();

      expect(journal.jobs, hasLength(1));
      expect(journal.jobs.single.status, TransferJobStatus.completed);
      expect(cloud.files[lastPath], [500 % 256]);
      expect(cloud.files['$lastPath.part001'], [500 % 256]);
      expect(cloud.files['$lastPath.split.json'], isNotNull);
      expect(
        find.widgetWithText(FilledButton, 'Split and verify'),
        findsNothing,
      );
      await closeDialog(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
