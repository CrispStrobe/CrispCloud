import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_endpoint_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/file_clipboard_provider.dart';
import 'package:crisp_cloud/providers/native_file_operations_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/native_file_operations.dart';
import 'package:crisp_cloud/widgets/archive_endpoint_actions.dart';
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
    for (var index = 0; index < 250 && !done(); index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
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
