import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/provider_workflow_failure.dart';
import 'package:crisp_cloud/widgets/transfer_file_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

FileProgress _file(
  String name, {
  bool complete = false,
  String? status,
  String? error,
}) => FileProgress(
  name: name,
  path: '/source/$name',
  size: 100,
  isComplete: complete,
  statusLabel: status,
  error: error,
);

OperationProgress _batch(List<FileProgress> files, {String id = 'batch'}) =>
    OperationProgress(
      id: id,
      type: OperationType.copy,
      sourcePath: '/source',
      targetPath: '/target',
      fileName: '${files.length} files',
      files: files,
    );

void main() {
  Future<void> show(
    WidgetTester tester,
    OperationProgress operation, {
    List<TransferEntryRecord> entries = const [],
    String query = '',
    String language = 'en',
    Size size = const Size(800, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: SingleChildScrollView(
                child: TransferFileDetails(
                  operation: operation,
                  savedEntries: entries,
                  initialQuery: query,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder member(int index, {String id = 'batch'}) =>
      find.byKey(ValueKey('queue-file-$id-$index'));
  Finder filter(String value, {String id = 'batch'}) =>
      find.byKey(ValueKey('queue-file-filter-$id-$value'));
  Finder search({String id = 'batch'}) =>
      find.byKey(ValueKey('queue-file-search-$id'));

  Future<void> select(WidgetTester tester, String value) async {
    await tester.ensureVisible(filter(value));
    await tester.tap(filter(value));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'member filters distinguish attention, unfinished, completed and skipped work',
    (tester) async {
      final operation = _batch([
        _file('pending.txt'),
        _file('copied.txt', complete: true, status: 'copied'),
        _file('moved.txt', status: 'moved'),
        _file('skipped.txt', complete: true, status: 'skipped'),
        _file('filtered.txt', status: 'filtered'),
        _file('failed.txt', error: 'Permission denied'),
        _file('metadata.txt', complete: true, status: 'metadataFailed'),
        _file('conflict.txt', status: 'needsDecision'),
        _file('cancelled.txt', status: 'cancelled'),
      ]);
      await show(tester, operation);
      for (final label in [
        'All (9)',
        'Attention (3)',
        'Unfinished (5)',
        'Completed (2)',
        'Skipped (2)',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await select(tester, 'attention');
      expect(find.text('3 of 9 items'), findsOneWidget);
      expect(member(5), findsOneWidget);
      expect(member(6), findsOneWidget);
      expect(member(0), findsNothing);
      expect(member(1), findsNothing);
      expect(find.text('Permission denied'), findsOneWidget);

      await select(tester, 'completed');
      expect(member(1), findsOneWidget);
      expect(member(2), findsOneWidget);
      expect(member(6), findsNothing);
      await select(tester, 'skipped');
      expect(member(3), findsOneWidget);
      expect(member(4), findsOneWidget);
      expect(find.text('2 of 9 items'), findsOneWidget);
      expect(operation.files, hasLength(9));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live and restored conflict labels stay visible in attention and unfinished views',
    (tester) async {
      final operation = _batch([
        _file('conflict.txt', status: 'Waiting for a conflict decision'),
        _file('later.txt', status: 'Not started (awaiting conflict decision)'),
      ])..status = OperationStatus.waitingForDecision;
      await show(tester, operation);
      expect(find.text('Attention (1)'), findsOneWidget);
      expect(find.text('Unfinished (2)'), findsOneWidget);
      expect(
        find.textContaining('Not started (awaiting conflict decision)'),
        findsOneWidget,
      );
      await select(tester, 'attention');
      expect(member(0), findsOneWidget);
      expect(member(1), findsNothing);
      expect(
        find.textContaining('Waiting for a conflict decision'),
        findsOneWidget,
      );
      await select(tester, 'unfinished');
      expect(member(0), findsOneWidget);
      expect(member(1), findsOneWidget);
      expect(
        operation.files![1].statusLabel,
        'Not started (awaiting conflict decision)',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search includes literal member paths and saved renamed destinations',
    (tester) async {
      final operation = _batch([_file('report.csv'), _file('other.csv')]);
      final entries = [
        TransferEntryRecord(
          index: 0,
          source: FileItem(
            name: 'report.csv',
            path: '/source/report.csv',
            isFolder: false,
          ),
          destination: '/archive/{0}/renamed.csv',
        ),
      ];
      await show(tester, operation, entries: entries, query: 'RENAMED.csv');
      expect(
        tester.widget<TextField>(search()).controller!.text,
        'RENAMED.csv',
      );
      expect(member(0), findsOneWidget);
      expect(member(1), findsNothing);
      expect(
        find.text('/source/report.csv → /archive/{0}/renamed.csv'),
        findsOneWidget,
      );
      expect(find.text('1 of 2 items'), findsOneWidget);
      await tester.enterText(search(), '/SOURCE/OTHER');
      await tester.pumpAndSettle();
      expect(member(0), findsNothing);
      expect(member(1), findsOneWidget);
      expect(entries.single.destination, '/archive/{0}/renamed.csv');
    },
  );

  testWidgets(
    'empty filters can be cleared without changing the batch or queue query',
    (tester) async {
      final operation = _batch([_file('done.txt', complete: true)]);
      await show(tester, operation, query: 'done');
      await select(tester, 'attention');
      expect(find.text('No files match this view'), findsOneWidget);
      expect(find.text('0 of 1 items'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search()).controller!.text, isEmpty);
      expect(tester.widget<ChoiceChip>(filter('all')).selected, isTrue);
      expect(member(0), findsOneWidget);
      expect(operation.files!.single.isComplete, isTrue);
    },
  );

  testWidgets(
    'progress updates refresh filter counts and preserve local search',
    (tester) async {
      final failed = _file('report.csv', error: 'Temporary failure');
      final operation = _batch([failed, _file('other.csv')]);
      await show(tester, operation, query: 'source');
      await tester.enterText(search(), 'report');
      await select(tester, 'attention');
      expect(member(0), findsOneWidget);
      failed
        ..error = null
        ..isComplete = true
        ..statusLabel = 'copied';
      await show(tester, operation, query: 'other');
      expect(tester.widget<TextField>(search()).controller!.text, 'report');
      expect(find.text('Attention (0)'), findsOneWidget);
      expect(find.text('Completed (1)'), findsOneWidget);
      expect(find.text('No files match this view'), findsOneWidget);
      await select(tester, 'completed');
      expect(member(0), findsOneWidget);
      expect(member(1), findsNothing);
    },
  );

  testWidgets(
    'queue-only search leaves members visible and file search follows later changes',
    (tester) async {
      final operation = _batch([_file('one.txt'), _file('two.txt')]);
      await show(tester, operation, query: 'Cloud account');
      expect(tester.widget<TextField>(search()).controller!.text, isEmpty);
      expect(find.text('2 of 2 items'), findsOneWidget);
      await show(tester, operation, query: 'two.txt');
      expect(tester.widget<TextField>(search()).controller!.text, 'two.txt');
      expect(member(0), findsNothing);
      expect(member(1), findsOneWidget);
    },
  );

  testWidgets('row has full screen-reader diagnostics and opens by keyboard', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      const message =
          'Cannot read /source/{0}/a very long member name.txt: access was denied';
      final operation = _batch([_file('{0}.txt', error: message)]);
      await show(tester, operation);
      final data = tester.getSemantics(member(0)).getSemanticsData();
      expect(data.label, contains('/source/{0}.txt'));
      expect(data.label, contains(message));
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      final element = tester.element(member(0));
      bool rowHasFocus() {
        var found = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          ancestor,
        ) {
          if (identical(ancestor, element)) found = true;
          return !found;
        });
        return found;
      }

      for (var index = 0; index < 12 && !rowHasFocus(); index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(rowHasFocus(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == message,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText && widget.data == '/source/{0}.txt',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'full diagnostics copy preserves literal paths and reports clipboard failures',
    (tester) async {
      String? copied;
      var shouldFail = true;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          if (shouldFail) {
            throw PlatformException(
              code: 'unavailable',
              message: 'Clipboard unavailable',
            );
          }
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await show(tester, _batch([_file('{0}.txt', error: 'Denied at {1}')]));
      await tester.tap(member(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not copy details:'), findsOneWidget);
      expect(copied, isNull);
      shouldFail = false;
      await tester.tap(find.text('Copy details'));
      await tester.pumpAndSettle();
      expect(copied, contains('Path: /source/{0}.txt'));
      expect(copied, contains('Error: Denied at {1}'));
      expect(find.text('Copied'), findsOneWidget);
      expect(find.textContaining('Could not copy details:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing details while clipboard work is pending does not update disposed state',
    (tester) async {
      final copied = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') await copied.future;
        return null;
      });
      addTearDown(() {
        if (!copied.isCompleted) copied.complete();
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await show(tester, _batch([_file('report.csv')]));
      await tester.tap(member(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy details'));
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      copied.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('typed errors and controls localize without changing file data', (
    tester,
  ) async {
    final file = _file('Status {0}.txt', error: 'No path')
      ..errorCause = const TransferFileException(
        TransferFileCode.noPath,
        'No path',
      );
    await show(tester, _batch([file]), language: 'de');
    expect(find.text('Dateien oder Pfade suchen'), findsOneWidget);
    expect(find.text('1 von 1 Einträgen'), findsOneWidget);
    expect(find.text('Diese Datei hat keinen lokalen Pfad.'), findsOneWidget);
    expect(find.text('Status {0}.txt'), findsOneWidget);
    await tester.tap(member(0));
    await tester.pumpAndSettle();
    expect(find.text('Dateidetails'), findsOneWidget);
    expect(find.text('Details kopieren'), findsOneWidget);
    expect(file.error, 'No path');
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow large-text and right-to-left details remain usable', (
    tester,
  ) async {
    for (final language in ['de', 'ar']) {
      await show(
        tester,
        _batch([
          _file(
            'a very long filename with {0} and spaces.txt',
            error: 'A long diagnostic that must wrap without overflowing the transfer panel',
          ),
        ]),
        language: language,
        size: const Size(320, 720),
        textScale: 1.4,
      );
      await tester.ensureVisible(member(0));
      await tester.tap(member(0));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.text(CommanderStrings.forLanguage(language, 'Close')),
      );
      await tester.pumpAndSettle();
    }
  });
}
