import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/extensions/double_extension.dart';

void main() {
  group('DoubleExtension', () {
    group('safeMinClamp', () {
      test('returns lowerLimit when value is below lowerLimit', () {
        expect(1.0.safeMinClamp(2, 10), 2.0);
      });

      test('returns upperLimit when value is above upperLimit', () {
        expect(12.0.safeMinClamp(2, 10), 10.0);
      });

      test('returns value when within limits', () {
        expect(5.5.safeMinClamp(2, 10), 5.5);
      });

      test('swaps limits if lowerLimit > upperLimit', () {
        expect(3.5.safeMinClamp(8, 5), 5.0);
      });

      test('returns value when value equals lowerLimit', () {
        expect(2.0.safeMinClamp(2, 10), 2.0);
      });

      test('returns value when value equals upperLimit', () {
        expect(10.0.safeMinClamp(2, 10), 10.0);
      });
    });

    group('safeMaxClamp', () {
      test('returns upperLimit when value is above upperLimit', () {
        expect(12.0.safeMaxClamp(2, 10), 10.0);
      });

      test('returns lowerLimit when value is below lowerLimit', () {
        expect(1.5.safeMaxClamp(2, 10), 2.0);
      });

      test('returns value when within limits', () {
        expect(5.5.safeMaxClamp(2, 10), 5.5);
      });

      test('swaps limits if upperLimit < lowerLimit', () {
        expect(12.0.safeMaxClamp(8, 5), 8.0);
      });

      test('returns value when value equals lowerLimit', () {
        expect(2.0.safeMaxClamp(2, 10), 2.0);
      });

      test('returns value when value equals upperLimit', () {
        expect(10.0.safeMaxClamp(2, 10), 10.0);
      });
    });
  });
}
