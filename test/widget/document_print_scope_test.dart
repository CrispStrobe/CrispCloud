import 'dart:async';

import 'package:crisp_cloud/widgets/document_print_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'File Print and keyboard share one guarded command; errors recover',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var calls = 0;
      Completer<void>? job;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: DocumentPrintScope(
              onPrint: () async {
                calls++;
                if (job != null) await job.future;
              },
              child: const Scaffold(
                appBar: null,
                body: Focus(
                  autofocus: true,
                  child: Column(
                    children: [
                      SizedBox(height: 40, child: DocumentPrintMenu()),
                      Text('Document'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document-print-file-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document-print-command')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      job = Completer<void>();
      final action = container.read(documentPrintProvider)!;
      final first = action.run();
      await tester.pump();
      await tester.pump();
      await action.run();
      expect(calls, 2);
      job.completeError(StateError('printer unavailable'));
      await first;
      await tester.pumpAndSettle();
      expect(find.textContaining('printer unavailable'), findsOneWidget);
      expect(container.read(documentPrintProvider)!.isEnabled(), isTrue);
      job = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(calls, 3);
    },
  );

  testWidgets('queued print cannot reach a covered or disposed document', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var calls = 0;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          home: DocumentPrintScope(
            onPrint: () async => calls++,
            child: const Scaffold(body: Text('First')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final stale = container.read(documentPrintProvider)!;
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Modal')),
      ),
    );
    await tester.pumpAndSettle();
    await stale.run();
    expect(calls, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    final printed = stale.run();
    await tester.pumpAndSettle();
    await printed;
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await stale.run();
    expect(calls, 1);
    expect(container.read(documentPrintProvider), isNull);
  });
}
