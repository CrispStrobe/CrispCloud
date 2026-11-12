import 'dart:async';

import 'package:crisp_cloud/services/quick_open_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  QuickOpenEntry action(
    String id,
    Future<void> Function(QuickOpenRun) open, {
    QuickOpenUnavailable? unavailable,
  }) => QuickOpenEntry(
    id: id,
    name: 'Same name',
    kind: QuickOpenKind.favorite,
    detail: '/',
    open: open,
    unavailable: unavailable,
  );

  test(
    'a newer action cancels an older asynchronous action before its handoff',
    () async {
      final service = QuickOpenService();
      final gate = Completer<void>();
      final opened = <String>[];
      final first = service.open(
        action('first', (run) async {
          await gate.future;
          run.check();
          opened.add('first');
        }),
        isCurrent: () => true,
      );
      final rejected = expectLater(first, throwsA(isA<QuickOpenException>()));
      await service.open(
        action('second', (run) async {
          run.check();
          opened.add('second');
        }),
        isCurrent: () => true,
      );
      gate.complete();
      await rejected;
      expect(opened, ['second']);
      service.dispose();
    },
  );

  test(
    'unavailable entries cannot execute even when invoked outside the widget',
    () async {
      final service = QuickOpenService();
      var called = false;
      await expectLater(
        service.open(
          action('disabled', (_) async {
            called = true;
          }, unavailable: QuickOpenUnavailable.sourceUnavailable),
          isCurrent: () => true,
        ),
        throwsA(isA<QuickOpenException>()),
      );
      expect(called, isFalse);
      service.dispose();
    },
  );

  test(
    'closing the owning context or disposing the service cancels pending work',
    () async {
      for (final dispose in [false, true]) {
        final service = QuickOpenService();
        var current = true;
        final gate = Completer<void>();
        var called = false;
        final pending = service.open(
          action('pending', (run) async {
            await gate.future;
            run.check();
            called = true;
          }),
          isCurrent: () => current,
        );
        final rejected = expectLater(
          pending,
          throwsA(isA<QuickOpenException>()),
        );
        if (dispose) {
          service.dispose();
        } else {
          current = false;
        }
        gate.complete();
        await rejected;
        expect(called, isFalse);
      }
    },
  );
}
