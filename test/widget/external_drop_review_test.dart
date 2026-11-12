import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/external_drop_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:crisp_cloud/widgets/external_drop_review.dart';
import 'package:crisp_cloud/widgets/file_operation_dialog.dart';
import 'package:crisp_cloud/widgets/file_panel.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_drop_fixture.dart';

class _ObservedDropService extends ExternalDropService {
  _ObservedDropService({super.browser = true, super.access});
  bool preparationFinished = false;
  int preparations = 0;

  @override
  Future<PreparedExternalDrop> prepare(
    PanelNotifier panel,
    CapturedExternalDropDestination destination,
    List<DropItem> items, {
    bool Function()? isMounted,
  }) async {
    preparations++;
    try {
      return await super.prepare(
        panel,
        destination,
        items,
        isMounted: isMounted,
      );
    } finally {
      preparationFinished = true;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DropTestLocal local;
  late DropTestCloud primary;
  late DropTestCloud secondary;
  late ProviderContainer container;
  late _ObservedDropService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('drop-review-');
    local = DropTestLocal(directory.path);
    primary = DropTestCloud('primary');
    secondary = DropTestCloud('secondary')
      ..directories.addAll(['/target', '/elsewhere']);
    service = _ObservedDropService();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => DropTestAuth(primary)),
        localFileServiceProvider.overrideWithValue(local),
        drivesProvider.overrideWith((_) async => const <DriveEntry>[]),
        transferJournalProvider.overrideWithValue(
          TransferJournal(MemoryTransferJournalStorage()),
        ),
        externalDropServiceProvider.overrideWith((_) => service),
      ],
    );
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'secondary',
          label: 'Secondary account',
          provider: CloudProvider.s3,
          client: secondary,
        );
  });

  tearDown(() async {
    container.dispose();
    await directory.delete(recursive: true);
  });

  Future<PanelNotifier> mount(
    WidgetTester tester, {
    PanelSide side = PanelSide.local,
    bool remoteDestination = true,
  }) async {
    final panel = container.read(panelProvider(side));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      if (remoteDestination) {
        await panel.navigateToPath(
          '/target',
          origin: panel.resolveStorageReference(
            storageReferenceForClient(secondary),
            '/target',
          ),
        );
      } else {
        await panel.navigateToPath(
          directory.path,
          origin: panel.captureLocalClipboardOrigin(directory.path),
        );
      }
    });
    tester.view.physicalSize = const Size(1150, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FilePanel(side: side, isActive: true, onTap: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(panel.hasVerifiedDirectoryListing, isTrue);
    expect(panel.isLoading, isFalse);
    return panel;
  }

  DropDoneDetails details(List<DropItem> files) => DropDoneDetails(
    files: files,
    localPosition: Offset.zero,
    globalPosition: Offset.zero,
  );

  Future<void> drop(WidgetTester tester, List<DropItem> files) async {
    await tester.runAsync(() async {
      tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
        details(files),
      );
    });
    await pumpUntil(
      tester,
      () => service.preparationFinished,
      'The captured drop did not finish preparing.',
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeReview(
    WidgetTester tester,
    FileOperationDialog dialog,
    String label,
  ) async {
    await tester.tap(find.widgetWithText(TextButton, label));
    await tester.pumpAndSettle();
    await pumpUntil(
      tester,
      () => !dialog.sourceBackend!.isCurrent,
      'Closing the review did not release its temporary source.',
    );
    await tester.pumpAndSettle();
  }

  Future<void> runCopy(WidgetTester tester) async {
    final transfers = await tester.runAsync(() async {
      final value = container.read(transferProvider);
      await value.ready;
      return value;
    });
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(OutlinedButton, 'Preview')),
    );
    // Native filesystem preview work needs the real async zone. Wait for the
    // rendered Start action rather than assuming that settled animations mean
    // the I/O-backed plan has completed.
    final start = find.widgetWithText(FilledButton, 'Start Copy');
    for (var attempt = 0; attempt < 250; attempt++) {
      await tester.pump();
      if (start.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(start).onPressed != null)
        break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Start Copy')),
    );
    await pumpUntil(
      tester,
      () =>
          transfers!.operations.isNotEmpty &&
          transfers.operations.every((operation) => operation.isComplete) &&
          find.widgetWithText(TextButton, 'Close').evaluate().isNotEmpty,
      'The foreground copy or its post-copy directory refresh did not finish.',
    );
    await tester.pumpAndSettle();
    expect(transfers!.hasActiveOperations, isFalse);
  }

  testWidgets(
    'native files use the actual secondary account on the visually local pane',
    (tester) async {
      final access = RecordingDropAccess();
      service = _ObservedDropService(browser: false, access: access);
      final input = (await tester.runAsync(
        () =>
            File(p.join(directory.path, 'input.txt'))
                .writeAsString('dropped content'),
      ))!;
      final panel = await mount(tester);
      await drop(tester, [
        DropItemFile(input.path, extraAppleBookmark: Uint8List.fromList([7])),
      ]);
      final dialog = tester.widget<FileOperationDialog>(
        find.byType(FileOperationDialog),
      );
      expect(dialog.externalDestinationSide, PanelSide.local);
      expect(dialog.destinationPath, '/target');
      expect(
        (dialog.destinationOrigin!.source as RemotePanelSource).client,
        same(secondary),
      );
      expect(
        find.byKey(const ValueKey('transfer-schedule-background')),
        findsNothing,
      );
      expect(find.text('Start in background'), findsNothing);
      expect(primary.writes, isEmpty);
      expect(secondary.writes, isEmpty);
      expect(access.stopped, isEmpty);
      // Browsing after review does not retarget the captured operation.
      await tester.runAsync(() => panel.navigateToPath('/elsewhere'));
      await runCopy(tester);
      expect(secondary.files['/target/input.txt'], 'dropped content'.codeUnits);
      expect(secondary.files['/elsewhere/input.txt'], isNull);
      expect(primary.writes, isEmpty);
      expect(access.stopped, isEmpty);
      await closeReview(tester, dialog, 'Close');
      expect(access.stopped, [
        [7],
      ]);
      expect(dialog.sourceBackend!.isCurrent, isFalse);
    },
  );

  testWidgets(
    'browser handles copy through review to an actual local folder on the visually remote pane',
    (tester) async {
      await mount(tester, side: PanelSide.remote, remoteDestination: false);
      final file = DropTestFile('browser.txt', [1, 2, 3]);
      await drop(tester, [file]);
      final dialog = tester.widget<FileOperationDialog>(
        find.byType(FileOperationDialog),
      );
      expect(dialog.externalDestinationSide, PanelSide.remote);
      expect(dialog.destinationOrigin!.source, isA<LocalPanelSource>());
      expect(dialog.destinationPath, directory.path);
      expect(file.streamReads, 0);
      expect(
        await tester.runAsync(
          () => File(p.join(directory.path, 'browser.txt')).exists(),
        ),
        isFalse,
      );
      await runCopy(tester);
      expect(
        await tester.runAsync(
          () => File(p.join(directory.path, 'browser.txt')).readAsBytes(),
        ),
        [1, 2, 3],
      );
      expect(file.byteReads, 0);
      // The copy engine may reopen the captured source for content
      // verification. Both passes must use streaming, never readAsBytes.
      expect(file.streamReads, inInclusiveRange(1, 2));
      expect(primary.writes, isEmpty);
      expect(secondary.writes, isEmpty);
      await closeReview(tester, dialog, 'Close');
      expect(dialog.sourceBackend!.isCurrent, isFalse);
    },
  );

  testWidgets(
    'existing target bytes survive a cancelled preview and another drop cannot replace its source',
    (tester) async {
      secondary.put('/target/same.txt', [9, 8, 7]);
      await mount(tester);
      final callback = tester
          .widget<DropTarget>(find.byType(DropTarget))
          .onDragDone!;
      final file = DropTestFile('same.txt', [1]);
      await drop(tester, [file]);
      final dialog = tester.widget<FileOperationDialog>(
        find.byType(FileOperationDialog),
      );
      expect(
        tester.widget<DropTarget>(find.byType(DropTarget)).enable,
        isFalse,
      );
      callback(
        details([
          DropTestFile('second.txt', [2]),
        ]),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
      await tester.pumpAndSettle();
      expect(service.preparations, 1);
      expect(secondary.files['/target/same.txt'], [9, 8, 7]);
      expect(secondary.writes, isEmpty);
      expect(file.streamReads, 0);
      await closeReview(tester, dialog, 'Cancel');
      expect(dialog.sourceBackend!.isCurrent, isFalse);
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(secondary.writes, isEmpty);
    },
  );

  testWidgets(
    'navigation during browser metadata capture cannot redirect the drop',
    (tester) async {
      final panel = await mount(tester);
      final file = DropTestFile('late.txt', [1])
        ..pendingLength = Completer<int>();
      await tester.runAsync(() async {
        tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
          details([file]),
        );
      });
      await pumpUntil(
        tester,
        () => file.lengthRequested,
        'The captured source metadata read did not start.',
      );
      await tester.runAsync(() async {
        await panel.navigateToPath('/elsewhere');
        file.pendingLength!.complete(1);
      });
      await pumpUntil(
        tester,
        () => service.preparationFinished,
        'The stale drop did not stop preparing.',
      );
      await tester.pumpAndSettle();
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(primary.writes, isEmpty);
      expect(secondary.writes, isEmpty);
      expect(file.streamReads, 0);
    },
  );
}

/// Alternate real I/O and widget microtasks; futures created by a widget's
/// fake zone cannot be awaited while that clock is suspended by runAsync.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String reason,
) async {
  for (var attempt = 0; attempt < 250; attempt++) {
    await tester.pump();
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail(reason);
}
