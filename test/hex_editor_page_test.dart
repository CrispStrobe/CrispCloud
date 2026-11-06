import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madedit2_hex/madedit2_hex.dart';
import 'package:crisp_cloud/widgets/hex_editor_dialog.dart';

import 'hex_file_session_test.dart' show MemoryBackend;

// Opening and editing use real asynchronous file I/O on native platforms.
// Keep that work in runAsync, yielding to the I/O event loop between frames.
// Chrome runs the same lifecycle assertions through the bounded memory source.
void main() {
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() complete, {
    required String reason,
  }) async {
    final elapsed = Stopwatch()..start();
    do {
      await tester.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (elapsed.elapsed > const Duration(seconds: 10)) {
        throw TimeoutException(reason);
      }
    } while (!complete());
    await tester.pumpAndSettle();
  }

  Future<HexEditorController> open(
    WidgetTester tester,
    MemoryBackend backend,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => HexFileEditorPage(
                    file: backend.item('/a.bin'),
                    backend: backend,
                  ),
                ),
              ),
              child: const Text('Open fixture'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open fixture'));
    await pumpUntil(
      tester,
      () =>
          find.byType(HexEditor).evaluate().isNotEmpty ||
          find
              .text('The original file has not been modified.')
              .evaluate()
              .isNotEmpty,
      reason: 'The host did not finish opening its source.',
    );
    expect(
      find.byType(HexEditor),
      findsOneWidget,
      reason: tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data ?? '')
          .join('\n'),
    );
    return tester.widget<HexEditor>(find.byType(HexEditor)).controller;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Save original (Ctrl/Cmd+S)'));
    await pumpUntil(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      reason: 'The host did not finish saving.',
    );
  }

  testWidgets(
    'host saves verified bytes and closes without a false dirty prompt',
    (tester) async {
      await tester.runAsync(() async {
        final backend = MemoryBackend();
        final controller = await open(tester, backend);
        await controller.typeDigit(0xa);
        await controller.typeDigit(0xb);
        await tester.pumpAndSettle();
        await save(tester);
        expect(backend.files['/a.bin'], [0xab, 2, 3, 4]);
        expect(controller.isDirty, isFalse);
        await tester.tap(find.byTooltip('Close hex editor'));
        await tester.pumpAndSettle();
        expect(find.text('Open fixture'), findsOneWidget);
        expect(find.text('Unsaved binary changes'), findsNothing);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'host keeps edits on external conflict and requires explicit discard',
    (tester) async {
      await tester.runAsync(() async {
        final backend = MemoryBackend();
        final controller = await open(tester, backend);
        await controller.writeBytes([9]);
        backend.files['/a.bin'] = [8, 2, 3, 4];
        await tester.pumpAndSettle();
        await save(tester);
        expect(controller.isDirty, isTrue);
        expect(backend.commits, 0);
        expect(backend.files['/a.bin'], [8, 2, 3, 4]);
        expect(find.textContaining('outside this editor'), findsWidgets);
        await tester.tap(find.byTooltip('Close hex editor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(find.byType(HexEditor), findsOneWidget);
        expect(await controller.document.read(0, 4), [9, 2, 3, 4]);
        await tester.tap(find.byTooltip('Close hex editor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.text('Open fixture'), findsOneWidget);
        expect(backend.files['/a.bin'], [8, 2, 3, 4]);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unsafe backend opens read-only rather than risking an unverified write',
    (tester) async {
      await tester.runAsync(() async {
        final backend = MemoryBackend()..staged = false;
        final controller = await open(tester, backend);
        expect(controller.readOnly, isTrue);
        expect(await controller.typeDigit(15), isFalse);
        expect(controller.isDirty, isFalse);
        expect(backend.commits, 0);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close hex editor'));
        await tester.pumpAndSettle();
      });
      expect(tester.takeException(), isNull);
    },
  );
}
