import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/operations_strings.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/provider_workflow_failure.dart';
import 'package:crisp_cloud/models/transfer_queue_summary.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/widgets/operations_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transfers extends ChangeNotifier implements TransferNotifier {
  _Transfers(this.operation);
  final OperationProgress operation;
  @override
  List<OperationProgress> get operations => List.unmodifiable([operation]);
  @override
  List<TransferJobRecord> get savedJobs => const [];
  @override
  TransferJobRecord? savedJob(String id) => null;
  @override
  String? get recoveryError => null;
  @override
  TransferQueueSummary get queueSummary =>
      const TransferQueueSummary(running: 1, totalBytes: 100);
  @override
  bool get queuePaused => false;
  @override
  int get maxConcurrent => 3;
  @override
  List<String> get queuedIds => const [];
  @override
  bool isQueued(String id) => false;
  @override
  bool isRunning(String id) => true;
  @override
  bool isJobLive(String id) => true;
  @override
  int priorityOf(String id) => 0;
  @override
  String? queueBlockedReason(String id) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('operation translations preserve keys and parameters', () {
    final translations = OperationsStrings.translations;
    expect(translations.keys.toSet(), {
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    });
    final keys = translations['de']!.keys.toSet();
    for (final locale in translations.entries) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      for (final entry in locale.value.entries) {
        expect(entry.value, isNotEmpty, reason: '${locale.key}: ${entry.key}');
        for (final match in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(match.group(0)), reason: locale.key);
        }
      }
    }
    final de = OperationsStrings.forLanguage('de');
    expect(de.eta(15), 'Noch 15 Sek.');
    expect(de.eta(125), 'Noch 2 Min. 5 Sek.');
    expect(de.eta(3660), 'Noch 1 Std. 1 Min.');
    expect(OperationsStrings.forLanguage('ja').eta(15), '残り 15 秒');
  });

  testWidgets('operation panel displays translated controls', (tester) async {
    final operation = OperationProgress(
      id: 'example',
      type: OperationType.upload,
      sourcePath: '/a',
      targetPath: '/b',
      fileName: 'test.txt',
      totalBytes: 100,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferProvider.overrideWith((ref) => _Transfers(operation)),
        ],
        child: const MaterialApp(
          locale: Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: OperationsPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Transferwarteschlange · 1 Aufträge'), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-pause')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('queue-menu-example')),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('queue-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('queue-menu-example')));
    await tester.pumpAndSettle();
    expect(find.text('Pausieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('new queue displays localized batch and typed file errors', (
    tester,
  ) async {
    final failed =
        FileProgress(name: 'missing.txt', path: 'missing.txt', size: 0)
          ..error = 'No path'
          ..errorCause = const TransferFileException(
            TransferFileCode.noPath,
            'No path',
          );
    final operation =
        OperationProgress(
          id: 'failed',
          type: OperationType.upload,
          sourcePath: '/a',
          targetPath: '/b',
          fileName: '2 files',
          files: [
            failed,
            FileProgress(name: 'good.txt', path: '/a/good.txt', size: 5)
              ..isComplete = true,
          ],
        )..fail(
          '1 of 2 files failed',
          code: TransferErrorCode.someFilesFailed,
          arguments: {'failed': 1, 'total': 2},
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferProvider.overrideWith((_) => _Transfers(operation)),
        ],
        child: const MaterialApp(
          locale: Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: OperationsPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('queue-menu-failed')),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('queue-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('2 Dateien'), findsOneWidget);
    expect(find.text('1 von 2 Dateien fehlgeschlagen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('queue-menu-failed')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'files',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Diese Datei hat keinen lokalen Pfad.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
