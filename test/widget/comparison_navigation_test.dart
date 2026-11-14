import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/diff_viewer_dialog.dart';

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedClient extends WorkflowFakeClient {
  Future<void> Function(String path)? beforeDownload;
  Future<void> Function(String path)? beforeList;

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) async {
    await beforeDownload?.call(path);
    return super.downloadFileBytes(path, onProgress: onProgress);
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await beforeList?.call(path);
    return super.listPath(path);
  }
}

void main() {
  late _ObservedClient cloud;
  late ProviderContainer container;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = _ObservedClient();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
  });
  tearDown(() => container.dispose());

  // Captured comparisons use private native files. Drive the real I/O event
  // loop inside runAsync, without turning native futures into fake timers.
  Future<void> pumpUntil(
    WidgetTester tester,
    FutureOr<bool> Function() complete, {
    required String reason,
  }) async {
    final elapsed = Stopwatch()..start();
    do {
      await tester.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (elapsed.elapsed > const Duration(seconds: 10)) {
        throw TimeoutException(reason);
      }
    } while (!await complete());
    // Stalled-source cases intentionally keep an indeterminate progress
    // indicator alive. Only settle finite route transitions here.
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> finishComparison(WidgetTester tester) => pumpUntil(
    tester,
    () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    reason: 'The comparison did not finish its current operation.',
  );

  Future<void> toggleBinary(WidgetTester tester) async {
    final chip = find.widgetWithText(FilterChip, 'Binary');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
  }

  Future<Set<String>> capturedCopies(String marker) async {
    final copies = <String>{};
    await for (final entry in Directory.systemTemp.list(followLinks: false)) {
      if (entry is! Directory ||
          !entry.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('crisp-transfer-spool-')) {
        continue;
      }
      final payload = File('${entry.path}${Platform.pathSeparator}payload');
      try {
        final size = await payload.length();
        if (size <= 256 && (await payload.readAsString()).startsWith(marker)) {
          copies.add(entry.path);
        }
      } on FileSystemException {
        // Another operation may finish its independent cleanup while listed.
      } on FormatException {
        // Other suites can hold unrelated binary spools in the same temp root.
      }
    }
    return copies;
  }

  Future<void> expectReleased(WidgetTester tester, Set<String> copies) =>
      pumpUntil(tester, () async {
        for (final path in copies) {
          if (await Directory(path).exists()) return false;
        }
        return true;
      }, reason: 'The comparison retained a closed private copy.');

  Future<void> open(WidgetTester tester, {bool narrow = false}) async {
    if (narrow) {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 1.8 : 1)),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () => showDiffViewerDialog(
                  context,
                  ref,
                  panel.files!.firstWhere((file) => file.name == 'left.txt'),
                  panel.files!.firstWhere((file) => file.name == 'right.txt'),
                  leftSide: PanelSide.remote,
                  rightSide: PanelSide.remote,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'right encoding selection controls verified merge bytes and follows file swapping',
    (tester) async {
      cloud.put('/left.txt', utf8.encode('left\n'));
      const right = EditorDocument(
        text: 'right\n',
        encoding: EditorEncoding.utf16le,
        lineEnding: EditorLineEnding.crlf,
        writeBom: false,
      );
      cloud.put('/right.txt', right.encode());
      await open(tester);
      final picker = find.byKey(const ValueKey('diff-right-auto'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('UTF-16 LE').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use left block'));
      await tester.tap(find.text('Use left block'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved merge'), findsOneWidget);
      await tester.ensureVisible(find.text('Save merge to right'));
      await tester.tap(find.text('Save merge to right'));
      await tester.pumpAndSettle();
      expect(cloud.files['/right.txt'], right.encode('left\n'));
      expect(find.text('Unsaved merge'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Swap files and merge target'));
      await tester.tap(find.byTooltip('Swap files and merge target'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diff-left-utf16le')), findsOneWidget);
      expect(find.byKey(const ValueKey('diff-right-auto')), findsOneWidget);
      expect(find.text('No differences'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final narrow in [false, true]) {
    testWidgets(
      'binary ranges and hex jumps work${narrow ? " with large narrow text" : ""}',
      (tester) async {
        await tester.runAsync(() async {
          cloud.put('/left.txt', [1, 2, 3, 4, 5, 6, 7, 8, 9]);
          cloud.put('/right.txt', [1, 99, 3, 4, 77, 66, 7, 8, 9, 0]);
          await open(tester, narrow: narrow);
          await toggleBinary(tester);
          await finishComparison(tester);
          expect(
            find.text('Verified captured copies • up to 8 GiB per file'),
            findsOneWidget,
          );
          expect(find.text('4 differing bytes in 3 ranges'), findsOneWidget);
          expect(find.text('Difference 1 / 3: bytes 1–1'), findsOneWidget);
          await tester.ensureVisible(find.byTooltip('Next difference'));
          await tester.tap(find.byTooltip('Next difference'));
          await finishComparison(tester);
          expect(find.text('Difference 2 / 3: bytes 4–5'), findsOneWidget);
          await tester.ensureVisible(find.byTooltip('Last difference'));
          await tester.tap(find.byTooltip('Last difference'));
          await finishComparison(tester);
          expect(find.text('Difference 3 / 3: bytes 9–9'), findsOneWidget);
          final address = find.byType(TextField);
          await tester.ensureVisible(address);
          await tester.enterText(address, '0x7');
          await tester.testTextInput.receiveAction(TextInputAction.go);
          await finishComparison(tester);
          expect(find.byKey(const ValueKey('binary-row-7')), findsOneWidget);
          expect(find.text('Bytes 7–10 of 10'), findsOneWidget);
          expect(cloud.writes, isEmpty);
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'captured copies are released on mode switch, swap, and dialog close',
    (tester) async {
      await tester.runAsync(() async {
        final marker =
            'comparison-lifecycle-${DateTime.now().microsecondsSinceEpoch}';
        cloud.put('/left.txt', utf8.encode('$marker left'));
        cloud.put('/right.txt', utf8.encode('$marker right'));
        await open(tester);
        await toggleBinary(tester);
        await finishComparison(tester);
        final firstCopies = await capturedCopies(marker);
        expect(firstCopies, hasLength(2));

        await toggleBinary(tester);
        await finishComparison(tester);
        await expectReleased(tester, firstCopies);
        expect(find.byKey(const ValueKey('diff-left-auto')), findsOneWidget);

        await toggleBinary(tester);
        await finishComparison(tester);
        final beforeSwap = await capturedCopies(marker);
        expect(beforeSwap, hasLength(2));
        await tester.tap(find.byTooltip('Swap files and merge target'));
        await finishComparison(tester);
        expect(find.text('right.txt ↔ left.txt'), findsOneWidget);
        await expectReleased(tester, beforeSwap);
        final swappedCopies = await capturedCopies(marker);
        expect(swappedCopies, hasLength(2));

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await expectReleased(tester, swappedCopies);
        expect(find.byType(Dialog), findsNothing);
        expect(cloud.writes, isEmpty);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Stop cancels stalled metadata and late completion cannot replace text mode',
    (tester) async {
      await tester.runAsync(() async {
        cloud.put('/left.txt', utf8.encode('left\n'));
        cloud.put('/right.txt', utf8.encode('right\n'));
        await open(tester);
        final entered = Completer<void>();
        final release = Completer<void>();
        cloud.beforeList = (_) async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        };
        try {
          await toggleBinary(tester);
          await pumpUntil(
            tester,
            () => entered.isCompleted,
            reason: 'The comparison did not request metadata.',
          );
          expect(
            find.text('Preparing and comparing captured copies…'),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('Stop comparison'));
          await finishComparison(tester);
          expect(find.text('No comparison result.'), findsOneWidget);

          cloud.beforeList = null;
          await toggleBinary(tester);
          await finishComparison(tester);
          expect(find.byKey(const ValueKey('diff-left-auto')), findsOneWidget);
          release.complete();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
          expect(find.textContaining('differing bytes in'), findsNothing);
          expect(find.byKey(const ValueKey('diff-left-auto')), findsOneWidget);
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
        } finally {
          cloud.beforeList = null;
          if (!release.isCompleted) release.complete();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposing during the second source capture releases the first copy',
    (tester) async {
      await tester.runAsync(() async {
        final marker =
            'comparison-dispose-${DateTime.now().microsecondsSinceEpoch}';
        cloud.put('/left.txt', utf8.encode('$marker left'));
        cloud.put('/right.txt', utf8.encode('$marker right'));
        await open(tester);
        final entered = Completer<void>();
        final release = Completer<void>();
        cloud.beforeDownload = (path) async {
          if (path != '/right.txt') return;
          if (!entered.isCompleted) entered.complete();
          await release.future;
        };
        try {
          await toggleBinary(tester);
          await pumpUntil(
            tester,
            () => entered.isCompleted,
            reason: 'The comparison did not start its second capture.',
          );
          final completedCopies = await capturedCopies(marker);
          expect(completedCopies, hasLength(1));
          await tester.pumpWidget(const SizedBox.shrink());
          await expectReleased(tester, completedCopies);
          release.complete();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
          expect(await capturedCopies(marker), isEmpty);
          expect(find.byType(Dialog), findsNothing);
          expect(cloud.writes, isEmpty);
        } finally {
          cloud.beforeDownload = null;
          if (!release.isCompleted) release.complete();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'captured comparison notices translate every locale and retain limits',
    () {
      const captured = 'Verified captured copies • up to {0} per file';
      const preparing = 'Preparing and comparing captured copies…';
      for (final language in CommanderStrings.supportedLanguageCodes.skip(1)) {
        final text = CommanderStrings.forLanguage(language, captured, [
          '8 GiB',
        ]);
        expect(text, contains('8 GiB'));
        expect(text, isNot(contains('{0}')));
        expect(text, isNot('Verified captured copies • up to 8 GiB per file'));
        expect(
          CommanderStrings.forLanguage(language, preparing),
          isNot(preparing),
        );
      }
    },
  );
}
