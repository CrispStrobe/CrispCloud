import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/mixins/extended_loop.dart';

class _LoopOwner with ExtendedLoop {}

void main() {
  testWidgets('disposal cancels all pending transition frame waits', (
    tester,
  ) async {
    final owner = _LoopOwner();
    var updates = 0;
    var done = 0;
    var returned = 0;
    for (var i = 0; i < 2; i++) {
      unawaited(
        owner
            .loopWithTransitionTiming(
              (_) => updates++,
              duration: const Duration(seconds: 10),
              mounted: true,
              onDone: () => done++,
            )
            .then((_) {
              returned++;
            }),
      );
    }
    expect(updates, 2);
    owner.disposeTransitionLoops();
    await tester.pump();
    expect(returned, 2);
    expect(updates, 2);
    expect(done, 0);
    // The normal widget-test timer invariant remains active. No extra timed
    // pump or timer suppression hides a callback left alive after disposal.
  });

  testWidgets('zero duration completes once and a disposed owner stays idle', (
    tester,
  ) async {
    final owner = _LoopOwner();
    final values = <double>[];
    var done = 0;
    await owner.loopWithTransitionTiming(
      values.add,
      duration: Duration.zero,
      mounted: true,
      onDone: () => done++,
    );
    expect(values, [1.0]);
    expect(done, 1);
    owner.disposeTransitionLoops();
    await owner.loopWithTransitionTiming(
      values.add,
      duration: const Duration(seconds: 1),
      mounted: true,
      onDone: () => done++,
    );
    expect(values, [1.0]);
    expect(done, 1);
  });
}
