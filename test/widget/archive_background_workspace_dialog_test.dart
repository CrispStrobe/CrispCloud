import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/models/archive_operation.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/widgets/archive_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_drop_fixture.dart';

class _Transfers extends ChangeNotifier implements TransferNotifier {
  ArchiveWorkspace? draft;
  final admission =
      Completer<ArchiveOperationHandle<ArchivePublicationReceipt?>>();
  int calls = 0;

  @override
  Future<ArchiveOperationHandle<ArchivePublicationReceipt?>>
  enqueueArchiveWorkspace(
    ArchiveWorkspace workspace, {
    ArchiveWorkspaceReview? reviewed,
    VoidCallback? onSaved,
    int priority = 0,
    DateTime? notBefore,
    String? recoveryJobId,
  }) {
    calls++;
    draft = workspace;
    return admission.future;
  }

  void accept() => admission.complete(
    ArchiveOperationHandle(
      id: 'archive_workspace_widget',
      operation: OperationProgress(
        id: 'archive_workspace_widget',
        type: OperationType.archive,
        sourcePath: draft!.outermost.file.path!,
        targetPath: draft!.outermost.file.path!,
        fileName: draft!.file.name,
        totalBytes: 0,
      ),
      control: FileOperationControl(),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late File archive;
  late ProviderContainer container;
  late PanelNotifier panel;
  late _Transfers transfers;
  late List<int> original;

  Future<void> prepare() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
    directory = await Directory.systemTemp.createTemp(
      'archive-background-view-',
    );
    archive = File(p.join(directory.path, 'work.zip'));
    original = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile.bytes('keep.txt', [1, 2, 3])),
    );
    await archive.writeAsBytes(original);
    transfers = _Transfers();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (_) => DropTestAuth(DropTestCloud('background-view')),
        ),
        localFileServiceProvider.overrideWithValue(
          DropTestLocal(directory.path),
        ),
        transferProvider.overrideWith((_) => transfers),
      ],
    );
    panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    await panel.navigateToPath(
      directory.path,
      origin: panel.captureLocalClipboardOrigin(directory.path),
    );
    await panel.enterArchive(
      panel.files!.singleWhere((file) => file.path == archive.path),
    );
  }

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    // Workspace opening performs real native file I/O. Fake clock advances
    // alone do not allow a cold reader to finish on a shared hosted runner.
    for (var i = 0; i < 1000 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      condition(),
      isTrue,
      reason: [
        ...tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
        ...tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data),
      ].join('\n'),
    );
  }

  Future<void> show(WidgetTester tester) async {
    await tester.runAsync(prepare);
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await transfers.draft?.close();
      container.dispose();
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final origin = panel.captureArchiveOrigin();
    final location = panel.captureArchiveWorkspaceLocation();
    final journal = ArchivePublicationJournal(
      storage: MemoryFileCollectionStorage(),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showArchiveWorkspaceDialog(
                  context,
                  ref,
                  PanelSide.local,
                  location.file,
                  sourceOrigin: origin,
                  location: location,
                  journal: journal,
                ),
                child: const Text('Open workspace'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open workspace'));
    await until(tester, () => find.text('keep.txt').evaluate().isNotEmpty);
    final newFolder = find.byIcon(Icons.create_new_folder_outlined);
    await tester.ensureVisible(newFolder);
    await tester.pumpAndSettle();
    await tester.tap(newFolder);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'draft-folder');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('draft-folder'), findsOneWidget);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('archive-workspace-background')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('draft-folder'), findsWidgets);
    expect(transfers.calls, 0);
    await tester.tap(
      find.byKey(const ValueKey('archive-workspace-background-confirm')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'background workspace admission detaches its original authority from pane navigation',
    (tester) async {
      await show(tester);
      await confirm(tester);
      expect(transfers.calls, 1);
      expect(transfers.draft!.dirty, isTrue);
      expect(
        find.byKey(const ValueKey('archive-workspace-background')),
        findsOneWidget,
      );
      expect(await tester.runAsync(archive.readAsBytes), original);
      transfers.accept();
      await until(
        tester,
        () => find
            .byKey(const ValueKey('archive-workspace-background'))
            .evaluate()
            .isEmpty,
      );
      await tester.runAsync(
        () => panel.navigateToPath(
          directory.path,
          origin: panel.captureLocalClipboardOrigin(directory.path),
        ),
      );
      expect(panel.isInArchive, isFalse);
      expect(transfers.draft!.isCurrent, isTrue);
      final contents = await tester.runAsync(
        () async => transfers.draft!
            .openRead('/keep.txt')
            .expand((chunk) => chunk)
            .toList(),
      );
      expect(contents, [1, 2, 3]);
      expect(transfers.draft!.draftChanges.single.path, 'draft-folder');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed workspace admission preserves the editable draft', (
    tester,
  ) async {
    await show(tester);
    await confirm(tester);
    transfers.admission.completeError(
      StateError('Could not save queue intent'),
    );
    await until(
      tester,
      () => find
          .textContaining('Could not save queue intent')
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.byKey(const ValueKey('archive-workspace-background')),
      findsOneWidget,
    );
    expect(transfers.draft!.isCurrent, isTrue);
    expect(transfers.draft!.dirty, isTrue);
    expect(await tester.runAsync(archive.readAsBytes), original);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'navigation before explicit confirmation rejects the stale pane draft',
    (tester) async {
      await show(tester);
      await tester.tap(
        find.byKey(const ValueKey('archive-workspace-background')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => panel.navigateToPath(
          directory.path,
          origin: panel.captureLocalClipboardOrigin(directory.path),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('archive-workspace-background-confirm')),
      );
      await tester.pumpAndSettle();
      expect(transfers.calls, 0);
      expect(
        find.text(
          'The archive draft changed. Review its current changes again.',
        ),
        findsOneWidget,
      );
      expect(await tester.runAsync(archive.readAsBytes), original);
      expect(tester.takeException(), isNull);
    },
  );
}
