import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/file_editor_dialog.dart';
import 'package:crisp_cloud/widgets/csv_spreadsheet_import_dialog.dart';
import 'package:crisp_cloud/widgets/hex_editor_dialog.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madedit2_hex/madedit2_hex.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';
import '../support/workspace_fixture.dart' show WorkspaceTestAuth;

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
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

/// Uploads replace object IDs; moving a staged object preserves its ID.
class _Cloud extends WorkflowFakeClient {
  final ids = <String, String>{};
  int _nextId = 0;
  String account = 'account-a';
  Completer<void>? uploadStarted;
  Completer<void>? uploadGate;
  Completer<void>? downloadStarted;
  Completer<void>? downloadGate;

  @override
  String get userId => account;

  @override
  void put(String path, List<int> bytes, {DateTime? date}) {
    super.put(path, bytes, date: date);
    ids[path] = 'object-${++_nextId}';
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final result = await super.listPath(path);
    for (final item in result['files'] as List) {
      (item as Map)['uuid'] = ids[item['path']];
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    if (directories.contains(path)) return {'path': path, 'type': 'folder'};
    final bytes = files[path];
    return bytes == null
        ? null
        : {'path': path, 'uuid': ids[path], 'size': bytes.length};
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) async {
    if (downloadStarted?.isCompleted == false) downloadStarted!.complete();
    await downloadGate?.future;
    return super.downloadFileBytes(path, onProgress: onProgress);
  }

  @override
  Future<void> uploadFile(
    List<int> bytes,
    String name,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (uploadStarted?.isCompleted == false) uploadStarted!.complete();
    await uploadGate?.future;
    await super.uploadFile(bytes, name, targetPath, onProgress: onProgress);
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    files[targetPath] = files.remove(sourcePath)!;
    modified[targetPath] = modified.remove(sourcePath)!;
    ids[targetPath] = ids.remove(sourcePath)!;
  }
}

class _Fixture {
  _Fixture(this.container, this.cloud, this.original, this.closed);
  final ProviderContainer container;
  final _Cloud cloud;
  final FileItem original;
  final Completer<void> closed;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() complete, {
  bool settle = true,
}) async {
  final elapsed = Stopwatch()..start();
  do {
    await tester.pump(const Duration(milliseconds: 20));
    // Keep widget frames and their cursor timers in FakeAsync. Only let the
    // native spool's I/O callbacks progress outside that clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw TimeoutException('Editor transition did not finish.');
    }
  } while (!complete());
  if (settle) await tester.pumpAndSettle();
}

Future<T> _pumpUntilComplete<T>(WidgetTester tester, Future<T> future) async {
  var complete = false;
  late T result;
  Object? failure;
  StackTrace? failureStack;
  unawaited(
    future.then<void>(
      (value) {
        result = value;
        complete = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        complete = true;
      },
    ),
  );
  await _pumpUntil(tester, () => complete);
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return result;
}

Future<_Fixture> _open(
  WidgetTester tester, {
  bool hex = false,
  String filename = 'note.txt',
  bool waitForReady = true,
  _Cloud? cloud,
}) async {
  SharedPreferences.setMockInitialValues({});
  final client = cloud ?? (_Cloud()..put('/$filename', utf8.encode('one')));
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((_) => WorkspaceTestAuth(client)),
      localFileServiceProvider.overrideWithValue(_Local()),
    ],
  );
  addTearDown(container.dispose);
  final panel = container.read(panelProvider(PanelSide.remote));
  // Browser tab restoration is asynchronous and refreshes the initial listing.
  // Let it finish before capturing the exact row that authorizes the editor.
  await _pumpUntil(
    tester,
    () => panel.tabs.isNotEmpty && !panel.isLoading,
    settle: false,
  );
  await panel.refresh();
  final file = panel.files!.singleWhere((file) => file.name == filename);
  final closed = Completer<void>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () async {
                if (hex) {
                  await showHexEditorDialog(
                    context,
                    ref,
                    file,
                    PanelSide.remote,
                  );
                } else {
                  await showFileEditorDialog(
                    context,
                    ref,
                    file,
                    PanelSide.remote,
                  );
                }
                closed.complete();
              },
              child: const Text('Open fixture'),
            ),
          ),
        ),
      ),
    ),
  );
  expect(
    panel.originForOperation(file),
    isNotNull,
    reason: 'Open the verified row after initial tab restoration has settled.',
  );
  await tester.tap(find.text('Open fixture'));
  if (waitForReady) {
    await _pumpUntil(
      tester,
      () => find.byType(hex ? HexEditor : CodeEditor).evaluate().isNotEmpty,
    );
  } else {
    await tester.pump();
  }
  return _Fixture(container, client, file, closed);
}

CodeLineEditingController _textController(WidgetTester tester) =>
    tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;

HexEditorController _hexController(WidgetTester tester) =>
    tester.widget<HexEditor>(find.byType(HexEditor)).controller;

void main() {
  if (kIsWeb) {
    final originalReporter = reportTestException;
    reportTestException = (details, description) {
      debugPrintSynchronously(
        'EDITOR_HANDOFF_BROWSER_FAILURE: $description\n'
        '${details.exceptionAsString()}\n${details.stack ?? ''}',
      );
      originalReporter(details, description);
    };
  }

  testWidgets(
    'CSV editor imports current unsaved text and cancel preserves edits',
    (tester) async {
      final fixture = await _open(tester, filename: 'table.csv');
      const current = 'id,name\n001,current';
      _textController(tester).text = current;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('editor-import-spreadsheet')));
      await _pumpUntil(
        tester,
        () => find.text('2 rows · 2 columns').evaluate().isNotEmpty,
      );
      expect(find.byType(CsvSpreadsheetImportDialog), findsOneWidget);
      expect(find.text('current'), findsOneWidget);
      expect(utf8.decode(fixture.cloud.files['/table.csv']!), 'one');
      expect(fixture.cloud.writes, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_textController(tester).text, current);
      // Remove the route without committing the still-unsaved CSV buffer.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 150));
    },
  );

  testWidgets(
    'text and hex handoffs retain storage after saves replace IDs and rows refresh',
    (tester) async {
      final fixture = await _open(tester);
      final panel = fixture.container.read(panelProvider(PanelSide.remote));
      final originalId = fixture.original.uuid;
      _textController(tester).text = 'two';
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open in Hex Editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and switch'));
      await _pumpUntil(
        tester,
        () => find.byType(HexEditor).evaluate().isNotEmpty,
      );
      expect(utf8.decode(fixture.cloud.files['/note.txt']!), 'two');
      expect(fixture.cloud.ids['/note.txt'], isNot(originalId));
      expect(panel.originForOperation(fixture.original), isNotNull);

      // External refresh replaces rows; the original row remains forbidden
      // for a new capture, while this already captured session stays valid.
      await panel.refresh();
      expect(panel.originForOperation(fixture.original), isNull);
      expect(() => panel.captureFileTarget(fixture.original), throwsStateError);

      await _hexController(tester).writeBytes([0x54]);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open in Text Editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and switch'));
      await _pumpUntil(
        tester,
        () => find.byType(CodeEditor).evaluate().isNotEmpty,
      );
      expect(_textController(tester).text, 'Two');
      expect(utf8.decode(fixture.cloud.files['/note.txt']!), 'Two');
      expect(find.text('Modified'), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await _pumpUntil(tester, () => fixture.closed.isCompleted);
      expect(find.byType(HexEditor), findsNothing);
      expect(find.byType(CodeEditor), findsNothing);
      expect(
        panel.files!.singleWhere((file) => file.name == 'note.txt').uuid,
        fixture.cloud.ids['/note.txt'],
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a changed account cannot receive the editor handoff', (
    tester,
  ) async {
    final fixture = await _open(tester, hex: true);
    fixture.cloud.account = 'account-b';
    await tester.tap(find.byTooltip('Open in Text Editor'));
    await _pumpUntil(tester, () => fixture.closed.isCompleted);
    expect(find.byType(CodeEditor), findsNothing);
    expect(find.textContaining('storage account changed'), findsOneWidget);
    expect(fixture.cloud.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hex handoff waits for pending clipboard edits before prompting',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final clipboardStarted = Completer<void>();
      final clipboard = Completer<Map<String, dynamic>?>();
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          clipboardStarted.complete();
          return clipboard.future;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final fixture = await _open(tester, hex: true);
      final controller = _hexController(tester);
      final paste = controller.paste();
      await _pumpUntil(tester, () => clipboardStarted.isCompleted);
      await tester.tap(find.byTooltip('Open in Text Editor'));
      await tester.pump();
      expect(controller.isDirty, isFalse);
      expect(fixture.closed.isCompleted, isFalse);
      expect(find.byType(HexEditor), findsOneWidget);
      expect(find.text('Unsaved binary changes'), findsNothing);
      // Accepted edits finish, but new input cannot append a destructive
      // command behind the handoff's captured idle future.
      await tester.tap(find.byTooltip('Cut bytes'), warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');

      clipboard.complete({'text': '54'});
      await paste.timeout(const Duration(seconds: 10));
      await controller.idle.timeout(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(controller.isDirty, isTrue);
      expect(await _pumpUntilComplete(tester, controller.document.read(0, 3)), [
        0x54,
        0x6e,
        0x65,
      ]);
      expect(find.text('Unsaved binary changes'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(HexEditor), findsOneWidget);
      expect(fixture.cloud.writes, isEmpty);
      await tester.tap(find.byTooltip('Close hex editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await _pumpUntil(tester, () => fixture.closed.isCompleted);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('text close waits for an active upload to settle', (
    tester,
  ) async {
    final fixture = await _open(tester);
    fixture.cloud.uploadStarted = Completer<void>();
    fixture.cloud.uploadGate = Completer<void>();
    _textController(tester).text = 'saved';
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save (Ctrl+S)'));
    await _pumpUntil(
      tester,
      () => fixture.cloud.uploadStarted!.isCompleted,
      settle: false,
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(fixture.closed.isCompleted, isFalse);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.text('You have unsaved changes. Discard them?'), findsNothing);
    fixture.cloud.uploadGate!.complete();
    await _pumpUntil(tester, () => fixture.closed.isCompleted);
    expect(utf8.decode(fixture.cloud.files['/note.txt']!), 'saved');
    expect(find.byType(CodeEditor), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late text load cannot focus or rebuild a closing editor', (
    tester,
  ) async {
    final cloud = _Cloud()
      ..put('/note.txt', utf8.encode('one'))
      ..downloadStarted = Completer<void>()
      ..downloadGate = Completer<void>();
    final fixture = await _open(tester, cloud: cloud, waitForReady: false);
    expect(cloud.downloadStarted!.isCompleted, isTrue);
    final close = find.byTooltip('Close');
    // Loading starts during the route's first frame, before its toolbar is
    // necessarily visible. Wait for the actual close control without settling
    // the loading spinner or releasing the pending download.
    await _pumpUntil(
      tester,
      () => close.hitTestable().evaluate().isNotEmpty,
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(cloud.downloadGate!.isCompleted, isFalse);
    await tester.tap(close);
    await tester.pump();
    // Complete the download while the departing route is still mounted.
    expect(close, findsOneWidget);
    cloud.downloadGate!.complete();
    await tester.pump();
    expect(find.byType(CodeEditor), findsNothing);
    await _pumpUntil(tester, () => fixture.closed.isCompleted);
    await tester.pump(const Duration(milliseconds: 150));
    expect(cloud.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
