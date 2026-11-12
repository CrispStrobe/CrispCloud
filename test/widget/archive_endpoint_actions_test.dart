import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_endpoint_strings.dart';
import 'package:crisp_cloud/l10n/archive_transfer_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/file_clipboard_provider.dart';
import 'package:crisp_cloud/providers/native_file_operations_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/screen_dialogs.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_container_publisher.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/native_file_operations.dart';
import 'package:crisp_cloud/widgets/archive_endpoint_actions.dart';
import 'package:crisp_cloud/widgets/archive_workspace_dialog.dart';
import 'package:crisp_cloud/widgets/file_clipboard_actions.dart';
import 'package:crisp_cloud/widgets/file_context_menu.dart';
import 'package:crisp_cloud/widgets/file_operation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_drop_fixture.dart';

void main() {
  late Directory directory;
  late String input, output, archivePath;
  late List<int> original;
  late ProviderContainer container;
  late PanelNotifier left, right;
  late WidgetRef widgetRef;
  Map<String, Object?>? nativeClipboard;
  Completer<void>? pendingClipboard;
  var clipboardReads = 0;
  const nativeChannel = MethodChannel('test/archive-clipboard');
  const native = NativeFileOperations(channel: nativeChannel);
  const desktop = TargetPlatformVariant({TargetPlatform.linux});

  FileItem sourceFile() =>
      left.files!.firstWhere((file) => file.name == 'new.txt');

  Future<void> prepareFixture() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
    expect(InstallationIdentityService.instance.current.persistent, isTrue);
    directory = await Directory.systemTemp.createTemp('archive-host-');
    input = p.join(directory.path, 'input');
    output = p.join(directory.path, 'output');
    await Directory(input).create();
    await Directory(output).create();
    await File(p.join(input, 'new.txt')).writeAsString('new contents');
    archivePath = p.join(output, 'work.zip');
    original = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile.bytes('folder/keep.txt', [1, 2, 3])),
    );
    await File(archivePath).writeAsBytes(original);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (_) => DropTestAuth(DropTestCloud('archive-host')),
        ),
        localFileServiceProvider.overrideWithValue(
          DropTestLocal(directory.path),
        ),
        nativeFileOperationsProvider.overrideWithValue(native),
      ],
    );
    nativeClipboard = null;
    pendingClipboard = null;
    clipboardReads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          if (call.method == 'writeClipboard') {
            nativeClipboard = Map<String, Object?>.from(call.arguments as Map);
          }
          if (call.method == 'readClipboard') {
            clipboardReads++;
            final snapshot = nativeClipboard;
            await pendingClipboard?.future;
            return snapshot;
          }
          return null;
        });
    left = container.read(panelProvider(PanelSide.local));
    right = container.read(panelProvider(PanelSide.remote));
    await Future<void>.delayed(Duration.zero);
    await left.navigateToPath(
      input,
      origin: left.captureLocalClipboardOrigin(input),
    );
    await right.navigateToPath(
      output,
      origin: right.captureLocalClipboardOrigin(output),
    );
    await right.enterArchive(
      right.files!.firstWhere((file) => file.path == archivePath),
    );
    expect(right.isInArchive, isTrue);
    await right.navigateInto(
      right.files!.firstWhere((file) => file.name == 'folder'),
    );
    container.read(activePanelProvider.notifier).state = PanelSide.local;
  }

  Future<(String, List<int>)> prepareArchiveSource() async {
    final path = p.join(input, 'source.zip');
    final bytes = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile.bytes('members/new.txt', [7, 8, 9]))
        ..addFile(ArchiveFile.bytes('members/other.txt', [10])),
    );
    await File(path).writeAsBytes(bytes);
    await left.refresh();
    await left.enterArchive(
      left.files!.firstWhere((file) => file.path == path),
    );
    await left.navigateInto(
      left.files!.firstWhere((file) => file.name == 'members'),
    );
    return (path, bytes);
  }

  Future<ArchiveWorkspace> openSourceWorkspace() async {
    final origin = left.captureArchiveOrigin();
    final location = left.captureArchiveWorkspaceLocation();
    return ArchiveWorkspace.openNested(
      fileOperationBackend(
        source: origin.source,
        local: container.read(localFileServiceProvider),
        isCurrent: () => origin.isCurrent,
      ),
      location.file,
      location.nestedMembers,
      expectedOuterFingerprint: location.fingerprint,
      journal: ArchivePublicationJournal(
        storage: MemoryFileCollectionStorage(),
      ),
    );
  }

  tearDown(() async {
    if (pendingClipboard case final pending? when !pending.isCompleted) {
      pending.complete();
    }
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    await directory.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester,
    Future<void> Function()? action,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                widgetRef = ref;
                return TextButton(
                  onPressed: action,
                  child: const Text('Transfer'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> until(WidgetTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      done(),
      isTrue,
      reason: [
        ...tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
        ...tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data),
      ].join('\n'),
    );
    // A workspace may keep its own progress animation running under the
    // transfer route. Settle the route/layout transition without waiting for
    // that deliberately active underlying indicator.
    await tester.pump(const Duration(milliseconds: 300));
  }

  bool canClose() => find
      .byWidgetPredicate(
        (widget) =>
            widget is TextButton &&
            widget.onPressed != null &&
            widget.child is Text &&
            (widget.child as Text).data == 'Close',
      )
      .evaluate()
      .isNotEmpty;

  for (final intent in ['copy', 'move', 'dirty']) {
    testWidgets(
      'workspace $intent uses copy review only for a clean copy and retains source ownership',
      (tester) async {
        await tester.runAsync(prepareFixture);
        final source = (await tester.runAsync(prepareArchiveSource))!;
        final workspace = (await tester.runAsync(openSourceWorkspace))!;
        addTearDown(workspace.close);
        if (intent == 'dirty') {
          workspace.replace('/members/new.txt', Uint8List.fromList([20, 21]));
        }
        final selected = (await workspace.backend.stat('/members/new.txt'))!;
        var finished = false;
        await mount(tester, () async {
          await showFileOperationDialog(
            widgetRef.context,
            widgetRef,
            PanelSide.local,
            [selected],
            kind: FileOperationKind.copy,
            sourceOrigin: left.captureArchiveOrigin(),
            sourceBackend: workspace.backend,
            archiveSourceMove: intent == 'move',
          );
          finished = true;
        });
        await tester.tap(find.text('Transfer'));
        if (intent == 'copy') {
          await until(tester, canClose);
          expect(find.text('Copy between archives'), findsOneWidget);
          await tester.ensureVisible(find.text('Prepare review'));
          await tester.runAsync(() => tester.tap(find.text('Prepare review')));
          await until(
            tester,
            () =>
                find.text('Review archive changes').evaluate().isNotEmpty &&
                canClose(),
          );
          await tester.ensureVisible(find.text('Publish verified archive'));
          await tester.runAsync(
            () => tester.tap(find.text('Publish verified archive')),
          );
          await until(
            tester,
            () =>
                find
                    .text('Archive published and verified.')
                    .evaluate()
                    .isNotEmpty &&
                canClose(),
          );
          await tester.tap(find.text('Close'));
          await until(tester, () => finished);
          final written = (await tester.runAsync(
            () => File(archivePath).readAsBytes(),
          ))!;
          expect(
            ZipDecoder()
                .decodeBytes(written)
                .findFile('folder/new.txt')
                ?.content,
            [7, 8, 9],
          );
        } else {
          await until(
            tester,
            () => finished && find.byType(SnackBar).evaluate().isNotEmpty,
          );
          expect(
            find.textContaining(
              archiveEndpointText(
                widgetRef.context,
                intent == 'move' ? 'archiveMoveUnsupported' : 'sourceDraft',
              ),
            ),
            findsOneWidget,
          );
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            await tester.runAsync(() => File(archivePath).readAsBytes()),
            original,
          );
        }
        expect(workspace.isCurrent, isTrue);
        expect(workspace.dirty, intent == 'dirty');
        expect(
          await workspace.read('/members/new.txt'),
          intent == 'dirty' ? [20, 21] : [7, 8, 9],
        );
        expect(
          await tester.runAsync(() => File(source.$1).readAsBytes()),
          source.$2,
        );
        expect(tester.takeException(), isNull);
      },
      variant: desktop,
    );
  }

  testWidgets(
    'workspace Move out returns its completed result through Escape and closes the stale source',
    (tester) async {
      await tester.runAsync(prepareFixture);
      final source = (await tester.runAsync(prepareArchiveSource))!;
      left.toggleSelection(sourceFile());
      await mount(tester, () async {
        await showCurrentArchiveWorkspaceDialog(
          widgetRef.context,
          widgetRef,
          PanelSide.local,
          action: ArchiveWorkspaceAction.moveOut,
        );
      });
      await tester.tap(find.text('Transfer'));
      await until(tester, canClose);
      expect(find.text('Move between archives'), findsOneWidget);
      expect(find.text('Move members out of this archive?'), findsNothing);
      await tester.ensureVisible(find.text('Prepare both reviews'));
      await tester.runAsync(
        () => tester.tap(find.text('Prepare both reviews')),
      );
      await until(
        tester,
        () =>
            find.text('Review both archives').evaluate().isNotEmpty &&
            canClose(),
      );
      expect(find.text('Destination archive: copied members'), findsOneWidget);
      expect(find.text('Source archive: member removals'), findsOneWidget);
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
      expect(
        await tester.runAsync(() => File(source.$1).readAsBytes()),
        source.$2,
      );
      await tester.ensureVisible(find.text('Publish reviewed move'));
      await tester.runAsync(
        () => tester.tap(find.text('Publish reviewed move')),
      );
      await until(
        tester,
        () =>
            find
                .text(
                  'Move completed. Both archives were published and verified.',
                )
                .evaluate()
                .isNotEmpty &&
            canClose(),
      );
      await tester.runAsync(
        () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
      );
      await until(
        tester,
        () =>
            find.byType(AlertDialog).evaluate().isEmpty &&
            !left.isLoading &&
            !right.isLoading,
      );
      expect(find.byTooltip('Close archive'), findsNothing);
      final sourceWritten = (await tester.runAsync(
        () => File(source.$1).readAsBytes(),
      ))!;
      final destinationWritten = (await tester.runAsync(
        () => File(archivePath).readAsBytes(),
      ))!;
      final sourceArchive = ZipDecoder().decodeBytes(sourceWritten);
      expect(sourceArchive.findFile('members/new.txt'), isNull);
      expect(sourceArchive.findFile('members/other.txt')?.content, [10]);
      final destinationArchive = ZipDecoder().decodeBytes(destinationWritten);
      expect(destinationArchive.findFile('folder/new.txt')?.content, [7, 8, 9]);
      expect(destinationArchive.findFile('folder/keep.txt')?.content, [
        1,
        2,
        3,
      ]);
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  for (final finishRecovery in [false, true]) {
    testWidgets(
      'pending source recovery closes a borrowed Move out host even without a new move receipt (finish: $finishRecovery)',
      (tester) async {
        await tester.runAsync(prepareFixture);
        final source = (await tester.runAsync(prepareArchiveSource))!;
        left.toggleSelection(sourceFile());
        final journal = ArchivePublicationJournal(
          storage: MemoryFileCollectionStorage(),
        );
        await mount(tester, () async {
          await showCurrentArchiveWorkspaceDialog(
            widgetRef.context,
            widgetRef,
            PanelSide.local,
            journal: journal,
          );
        });
        await tester.tap(find.text('Transfer'));
        await until(
          tester,
          () => find
              .ancestor(
                of: find.text('Move out with options…'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is TextButton && widget.onPressed != null,
                ),
              )
              .evaluate()
              .isNotEmpty,
        );
        final origin = left.captureArchiveOrigin();
        final location = left.captureArchiveWorkspaceLocation();
        final backend = fileOperationBackend(
          source: origin.source,
          local: container.read(localFileServiceProvider),
          isCurrent: () => origin.isCurrent,
        );
        final recovered = Uint8List.fromList(
          ZipEncoder().encode(
            Archive()
              ..addFile(ArchiveFile.bytes('members/recovered.txt', [22]))
              ..addFile(ArchiveFile.bytes('members/other.txt', [10])),
          ),
        );
        await tester.runAsync(() async {
          await expectLater(
            ArchiveContainerPublisher(backend, journal).publish(
              original: location.file,
              originalSha256: location.fingerprint,
              bytes: recovered,
              onPhase: (phase) {
                if (phase == ArchivePublicationPhase.candidateWritten) {
                  throw StateError(
                    'Another session stopped after preparing its candidate.',
                  );
                }
              },
            ),
            throwsA(isA<ArchivePublicationException>()),
          );
        });
        await tester.ensureVisible(find.text('Move out with options…'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => tester.tap(find.text('Move out with options…')),
        );
        await until(
          tester,
          () =>
              find.text('Archive publication recovery').evaluate().isNotEmpty &&
              canClose(),
        );
        if (finishRecovery) {
          await tester.ensureVisible(find.text('Finish publication'));
          await tester.runAsync(
            () => tester.tap(find.text('Finish publication')),
          );
          await until(
            tester,
            () => find
                .text('No unfinished archive publication for this account.')
                .evaluate()
                .isNotEmpty,
          );
        }
        // The first Close belongs to the disabled underlying workspace.
        await tester.runAsync(() => tester.tap(find.text('Close').last));
        await until(
          tester,
          () => find
              .textContaining(archiveEndpointText(widgetRef.context, 'reopen'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('Publish reviewed move'), findsNothing);
        await tester.runAsync(() => tester.tap(find.text('Close').last));
        await until(
          tester,
          () =>
              find.byTooltip('Close archive').evaluate().isEmpty &&
              !left.isLoading &&
              !right.isLoading,
        );
        await tester.runAsync(() async {
          expect(
            await File(source.$1).readAsBytes(),
            finishRecovery ? recovered : source.$2,
          );
          expect(await File(archivePath).readAsBytes(), original);
          if (!finishRecovery) {
            // Remove only this deliberately interrupted fixture's candidate.
            await journal.initialize();
            final record = journal.records.singleWhere(
              (record) =>
                  !record.isFinished && record.original.path == source.$1,
            );
            await ArchiveContainerPublisher(
              backend,
              journal,
            ).recover(record, ArchiveRecoveryAction.restoreOriginal);
          }
        });
        expect(
          left.files!.any((file) => file.name == 'recovered.txt'),
          finishRecovery,
        );
        expect(tester.takeException(), isNull);
      },
      variant: desktop,
    );
  }

  testWidgets(
    'F5 copies the captured archive selection through review and physical publication',
    (tester) async {
      await tester.runAsync(prepareFixture);
      final source = (await tester.runAsync(prepareArchiveSource))!;
      left.toggleSelection(sourceFile());
      await mount(tester, () async {
        showCopyDialogFromSelection(widgetRef.context, widgetRef);
      });
      await tester.tap(find.text('Transfer'));
      await until(tester, canClose);
      expect(find.text('Copy between archives'), findsOneWidget);
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(find.text('/members/new.txt → /folder/new.txt'), findsOneWidget);
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );

      await tester.ensureVisible(find.text('Prepare review'));
      await tester.runAsync(() => tester.tap(find.text('Prepare review')));
      await until(
        tester,
        () =>
            find.text('Review archive changes').evaluate().isNotEmpty &&
            canClose(),
      );
      await tester.ensureVisible(find.text('Publish verified archive'));
      await tester.runAsync(
        () => tester.tap(find.text('Publish verified archive')),
      );
      await until(
        tester,
        () =>
            find
                .text('Archive published and verified.')
                .evaluate()
                .isNotEmpty &&
            canClose(),
      );
      await tester.tap(find.text('Close'));
      await until(
        tester,
        () =>
            find.text('Copy between archives').evaluate().isEmpty &&
            !right.isLoading,
      );

      expect(
        await tester.runAsync(() => File(source.$1).readAsBytes()),
        source.$2,
      );
      final written = (await tester.runAsync(
        () => File(archivePath).readAsBytes(),
      ))!;
      final decoded = ZipDecoder().decodeBytes(written);
      expect(decoded.findFile('folder/new.txt')?.content, [7, 8, 9]);
      expect(decoded.findFile('folder/keep.txt')?.content, [1, 2, 3]);
      expect(decoded.findFile('folder/other.txt'), isNull);
      expect(left.isInArchive, isTrue);
      expect(left.selection.single.name, 'new.txt');
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'F6 between archive panes reviews and publishes the captured move',
    (tester) async {
      await tester.runAsync(prepareFixture);
      final source = (await tester.runAsync(prepareArchiveSource))!;
      left.toggleSelection(sourceFile());
      await mount(tester, () async {
        showMoveDialogFromSelection(widgetRef.context, widgetRef);
      });
      await tester.tap(find.text('Transfer'));
      await until(tester, canClose);
      expect(find.text('Move between archives'), findsOneWidget);
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(find.text('/members/new.txt → /folder/new.txt'), findsOneWidget);
      await tester.ensureVisible(find.text('Prepare both reviews'));
      await tester.runAsync(
        () => tester.tap(find.text('Prepare both reviews')),
      );
      await until(
        tester,
        () =>
            find.text('Review both archives').evaluate().isNotEmpty &&
            canClose(),
      );
      expect(find.text('Destination archive: copied members'), findsOneWidget);
      expect(find.text('Source archive: member removals'), findsOneWidget);
      expect(
        await tester.runAsync(() => File(source.$1).readAsBytes()),
        source.$2,
      );
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
      await tester.ensureVisible(find.text('Publish reviewed move'));
      await tester.runAsync(
        () => tester.tap(find.text('Publish reviewed move')),
      );
      await until(
        tester,
        () =>
            find
                .text(
                  'Move completed. Both archives were published and verified.',
                )
                .evaluate()
                .isNotEmpty &&
            canClose(),
      );
      await tester.runAsync(() => tester.tap(find.text('Close')));
      await until(
        tester,
        () =>
            find.byType(AlertDialog).evaluate().isEmpty &&
            !left.isLoading &&
            !right.isLoading,
      );
      expect(left.files!.any((file) => file.name == 'new.txt'), isFalse);
      expect(left.files!.any((file) => file.name == 'other.txt'), isTrue);
      expect(right.files!.any((file) => file.name == 'new.txt'), isTrue);
      final sourceWritten = (await tester.runAsync(
        () => File(source.$1).readAsBytes(),
      ))!;
      final destinationWritten = (await tester.runAsync(
        () => File(archivePath).readAsBytes(),
      ))!;
      expect(
        ZipDecoder().decodeBytes(sourceWritten).findFile('members/new.txt'),
        isNull,
      );
      expect(
        ZipDecoder()
            .decodeBytes(destinationWritten)
            .findFile('folder/new.txt')
            ?.content,
        [7, 8, 9],
      );
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  for (final move in [false, true]) {
    testWidgets(
      'archive context-menu ${move ? 'move' : 'copy'} keeps the original member selection while the popup is open',
      (tester) async {
        await tester.runAsync(prepareFixture);
        await tester.runAsync(prepareArchiveSource);
        final selected = sourceFile();
        left.toggleSelection(selected);
        await mount(tester, () async {
          showFileContextMenu(
            widgetRef.context,
            widgetRef,
            PanelSide.local,
            selected,
            const Offset(24, 24),
          );
        });
        await tester.tap(find.text('Transfer'));
        await tester.pumpAndSettle();
        final copy = find.text(
          move
              ? archiveTransferText(widgetRef.context, 'toArchive')
              : 'Copy to the other archive…',
        );
        expect(copy, findsOneWidget);
        left.clearSelection();
        left.toggleSelection(
          left.files!.firstWhere((file) => file.name == 'other.txt'),
        );
        await tester.tap(copy);
        await until(tester, canClose);
        expect(
          find.text(move ? 'Move between archives' : 'Copy between archives'),
          findsOneWidget,
        );
        expect(find.text('/members/new.txt → /folder/new.txt'), findsOneWidget);
        expect(find.textContaining('/folder/other.txt'), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(
          await tester.runAsync(() => File(archivePath).readAsBytes()),
          original,
        );
        expect(tester.takeException(), isNull);
      },
      variant: desktop,
    );

    testWidgets(
      'archive context-menu ${move ? 'move' : 'copy'} cannot revive a source after reopening the same archive',
      (tester) async {
        await tester.runAsync(prepareFixture);
        final source = (await tester.runAsync(prepareArchiveSource))!;
        final selected = sourceFile();
        left.toggleSelection(selected);
        await mount(tester, () async {
          showFileContextMenu(
            widgetRef.context,
            widgetRef,
            PanelSide.local,
            selected,
            const Offset(24, 24),
          );
        });
        await tester.tap(find.text('Transfer'));
        await tester.pumpAndSettle();
        final copy = find.text(
          move
              ? archiveTransferText(widgetRef.context, 'toArchive')
              : 'Copy to the other archive…',
        );
        expect(copy, findsOneWidget);
        await tester.runAsync(() async {
          await left.navigateToPath(
            input,
            origin: left.captureLocalClipboardOrigin(input),
          );
          await left.enterArchive(
            left.files!.firstWhere((file) => file.path == source.$1),
          );
          await left.navigateInto(
            left.files!.firstWhere((file) => file.name == 'members'),
          );
        });
        await tester.tap(copy);
        await until(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
        expect(
          find.textContaining(
            archiveEndpointText(widgetRef.context, 'sourceChanged'),
          ),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          await tester.runAsync(() => File(archivePath).readAsBytes()),
          original,
        );
        expect(
          await tester.runAsync(() => File(source.$1).readAsBytes()),
          source.$2,
        );
        expect(tester.takeException(), isNull);
      },
      variant: desktop,
    );
  }

  testWidgets(
    'ordinary copy routes into the captured member directory without a generic success plan',
    (tester) async {
      await tester.runAsync(prepareFixture);
      FileOperationPlan? result;
      var finished = false;
      await mount(tester, () async {
        result = await showFileOperationDialog(
          widgetRef.context,
          widgetRef,
          PanelSide.local,
          [sourceFile()],
          kind: FileOperationKind.copy,
        );
        finished = true;
      });
      await tester.tap(find.text('Transfer'));
      await until(tester, canClose);
      expect(find.text('Import into archive'), findsOneWidget);
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(find.textContaining('/folder/new.txt'), findsOneWidget);
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
      await tester.tap(find.text('Close'));
      await until(tester, () => finished);
      expect(result, isNull);
      expect(
        await tester.runAsync(
          () => File(p.join(input, 'new.txt')).readAsString(),
        ),
        'new contents',
      );
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'cut-paste cancelled inside an archive keeps its original clipboard references',
    (tester) async {
      await tester.runAsync(prepareFixture);
      await tester.runAsync(
        () => container
            .read(fileClipboardProvider)
            .capture(left, [sourceFile()], native, cut: true),
      );
      final captured = container.read(fileClipboardProvider).selection;
      expect(captured!.native, isTrue);
      expect(nativeClipboard, {
        'paths': [p.join(input, 'new.txt')],
        'cut': true,
      });
      var finished = false;
      await mount(tester, () async {
        await pasteFilesFromClipboard(
          widgetRef.context,
          widgetRef,
          PanelSide.remote,
        );
        finished = true;
      });
      await tester.tap(find.text('Transfer'));
      await until(tester, canClose);
      expect(find.text('Import into archive'), findsOneWidget);
      expect(find.textContaining('/folder/new.txt'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await until(tester, () => finished);
      expect(container.read(fileClipboardProvider).selection, same(captured));
      expect(
        await tester.runAsync(() => File(p.join(input, 'new.txt')).exists()),
        isTrue,
      );
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
    },
    variant: desktop,
  );

  testWidgets(
    'leaving and reopening an archive cannot revive a captured destination',
    (tester) async {
      await tester.runAsync(prepareFixture);
      await mount(tester, null);
      final captured = CapturedArchiveImportDestination.capture(
        widgetRef,
        PanelSide.remote,
      );
      expect(captured.directory, '/folder');
      expect(captured.location.file.path, archivePath);
      await tester.runAsync(() async {
        await right.navigateToPath(
          output,
          origin: right.captureLocalClipboardOrigin(output),
        );
        await right.enterArchive(
          right.files!.firstWhere((file) => file.path == archivePath),
        );
      });
      expect(captured.isCurrent, isFalse);
      expect(captured.backend.isCurrent, isFalse);
    },
    variant: desktop,
  );

  testWidgets(
    'clipboard await cannot retarget an archive paste after navigation',
    (tester) async {
      await tester.runAsync(prepareFixture);
      await tester.runAsync(
        () => container
            .read(fileClipboardProvider)
            .capture(left, [sourceFile()], native, cut: true),
      );
      final captured = container.read(fileClipboardProvider).selection;
      expect(captured!.native, isTrue);
      pendingClipboard = Completer<void>();
      var finished = false;
      await mount(tester, () async {
        await pasteFilesFromClipboard(
          widgetRef.context,
          widgetRef,
          PanelSide.remote,
        );
        finished = true;
      });
      await tester.tap(find.text('Transfer'));
      await until(tester, () => clipboardReads == 1);
      expect(finished, isFalse);
      await tester.runAsync(
        () => right.navigateToPath(
          output,
          origin: right.captureLocalClipboardOrigin(output),
        ),
      );
      pendingClipboard!.complete();
      await until(tester, () => finished);
      expect(find.text('Import into archive'), findsNothing);
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(container.read(fileClipboardProvider).selection, same(captured));
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
      expect(
        await tester.runAsync(() => File(p.join(output, 'new.txt')).exists()),
        isFalse,
      );
    },
    variant: desktop,
  );

  testWidgets(
    'new clipboard intent during an older read cancels the archive paste',
    (tester) async {
      await tester.runAsync(prepareFixture);
      final otherPath = p.join(input, 'other.txt');
      await tester.runAsync(() async {
        await File(otherPath).writeAsString('other contents');
        await left.refresh();
        await container
            .read(fileClipboardProvider)
            .capture(left, [sourceFile()], native, cut: true);
      });
      final originalSelection = container.read(fileClipboardProvider).selection;
      expect(originalSelection!.native, isTrue);
      expect(originalSelection.cut, isTrue);
      pendingClipboard = Completer<void>();
      var finished = false;
      await mount(tester, () async {
        await pasteFilesFromClipboard(
          widgetRef.context,
          widgetRef,
          PanelSide.remote,
        );
        finished = true;
      });
      await tester.tap(find.text('Transfer'));
      await until(tester, () => clipboardReads == 1);
      expect(finished, isFalse);

      await tester.runAsync(
        () => container
            .read(fileClipboardProvider)
            .capture(
              left,
              [left.files!.singleWhere((file) => file.path == otherPath)],
              native,
              cut: false,
            ),
      );
      final newerSelection = container.read(fileClipboardProvider).selection;
      expect(identical(newerSelection, originalSelection), isFalse);
      expect(newerSelection!.native, isTrue);
      expect(newerSelection.cut, isFalse);
      expect(nativeClipboard, {
        'paths': [otherPath],
        'cut': false,
      });

      pendingClipboard!.complete();
      await until(tester, () => finished);
      expect(find.text('Import into archive'), findsNothing);
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(
        container.read(fileClipboardProvider).selection,
        same(newerSelection),
      );
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
      expect(
        await tester.runAsync(
          () => File(p.join(input, 'new.txt')).readAsString(),
        ),
        'new contents',
      );
      expect(
        await tester.runAsync(() => File(otherPath).readAsString()),
        'other contents',
      );
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'cancelled archive paste retains cut references when source vanished externally',
    (tester) async {
      await tester.runAsync(prepareFixture);
      await tester.runAsync(
        () => container
            .read(fileClipboardProvider)
            .capture(left, [sourceFile()], native, cut: true),
      );
      final captured = container.read(fileClipboardProvider).selection;
      expect(captured!.native, isTrue);
      expect(captured.cut, isTrue);
      var finished = false;
      await mount(tester, () async {
        await pasteFilesFromClipboard(
          widgetRef.context,
          widgetRef,
          PanelSide.remote,
        );
        finished = true;
      });
      await tester.tap(find.text('Transfer'));
      await until(tester, canClose);
      expect(find.text('Import into archive'), findsOneWidget);
      expect(find.textContaining('/folder/new.txt'), findsOneWidget);

      await tester.runAsync(() => File(p.join(input, 'new.txt')).delete());
      await tester.tap(find.text('Close'));
      await until(tester, () => finished);
      expect(container.read(fileClipboardProvider).selection, same(captured));
      expect(nativeClipboard, {
        'paths': [p.join(input, 'new.txt')],
        'cut': true,
      });
      expect(
        await tester.runAsync(() => File(p.join(input, 'new.txt')).exists()),
        isFalse,
      );
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'context menu cannot revive its archive destination after reopening the same folder',
    (tester) async {
      await tester.runAsync(prepareFixture);
      await mount(tester, () async {
        showFileContextMenu(
          widgetRef.context,
          widgetRef,
          PanelSide.local,
          sourceFile(),
          const Offset(24, 24),
        );
      });
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();
      final copyAction = find.text('Copy to...');
      expect(copyAction, findsOneWidget);

      await tester.runAsync(() async {
        await right.navigateToPath(
          output,
          origin: right.captureLocalClipboardOrigin(output),
        );
        await right.enterArchive(
          right.files!.firstWhere((file) => file.path == archivePath),
        );
        await right.navigateInto(
          right.files!.firstWhere((file) => file.name == 'folder'),
        );
      });
      expect(right.captureArchiveWorkspaceLocation().file.path, archivePath);
      expect(right.archiveSource!.innerPath, 'folder/');
      await tester.ensureVisible(copyAction);
      await tester.pumpAndSettle();
      await tester.tap(copyAction);
      await until(
        tester,
        () =>
            find.byType(SnackBar).evaluate().isNotEmpty ||
            find.text('Import into archive').evaluate().isNotEmpty,
      );

      expect(find.text('Import into archive'), findsNothing);
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(
        find.textContaining(
          archiveEndpointText(widgetRef.context, 'unavailable'),
        ),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(() => File(archivePath).readAsBytes()),
        original,
      );
      expect(
        await tester.runAsync(
          () => File(p.join(input, 'new.txt')).readAsString(),
        ),
        'new contents',
      );
      expect(
        await tester.runAsync(() => File(p.join(output, 'new.txt')).exists()),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );
}
