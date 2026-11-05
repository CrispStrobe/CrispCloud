import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/mixins/extended_loop.dart';

class TestClass with ExtendedLoop {}

void main() {
  group('ExtendedLoop', () {
    late TestClass testClass;
    late List<double> curveTValues;
    late bool onDoneCalled;

    setUp(() {
      testClass = TestClass();
      curveTValues = [];
      onDoneCalled = false;
    });

    test(
      'calls function with curveT from 0.0 to 1.0 and calls onDone',
      () async {
        await testClass.loopWithTransitionTiming(
          (curveT) {
            curveTValues.add(curveT);
          },
          duration: const Duration(milliseconds: 50),
          mounted: true,
          onDone: () {
            onDoneCalled = true;
          },
        );

        expect(curveTValues.isNotEmpty, isTrue);
        expect(curveTValues.last, equals(1.0));
        expect(onDoneCalled, isTrue);
        expect(curveTValues.first, closeTo(0.0, 0.1));
      },
    );

    test('uses transitionFunction', () async {
      await testClass.loopWithTransitionTiming(
        (curveT) {
          curveTValues.add(curveT);
        },
        duration: const Duration(milliseconds: 30),
        mounted: true,
        transitionFunction: (t) => t * t,
      );

      // All values should be squared
      for (var i = 0; i < curveTValues.length - 1; i++) {
        expect(curveTValues[i] <= curveTValues[i + 1], isTrue);
      }
      expect(curveTValues.last, equals(1.0));
    });

    test('calls function once with 1.0 if duration is zero', () async {
      await testClass.loopWithTransitionTiming(
        (curveT) {
          curveTValues.add(curveT);
        },
        duration: Duration.zero,
        mounted: true,
      );

      expect(curveTValues, [1.0]);
    });

    test('stops loop if mounted becomes false', () async {
      var mounted = true;
      int callCount = 0;
      await testClass.loopWithTransitionTiming(
        (curveT) {
          callCount++;
          if (callCount == 2) mounted = false;
        },
        duration: const Duration(milliseconds: 100),
        mounted: mounted,
      );
      // Should call at least twice: once for t=0, once for t=1.0
      expect(callCount, greaterThanOrEqualTo(2));
    });
  });
}
