import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/utils/interpolation_utils.dart';

void main() {
  group('easeInOut', () {
    test('returns 0.0 for t=0.0', () {
      expect(easeInOut(0.0), closeTo(0.0, 1e-10));
    });

    test('returns 1.0 for t=1.0', () {
      expect(easeInOut(1.0), closeTo(1.0, 1e-10));
    });

    test('returns 0.5 for t=0.5', () {
      expect(easeInOut(0.5), closeTo(0.5, 1e-10));
    });

    test('is symmetric around t=0.5', () {
      expect(easeInOut(0.25), closeTo(1 - easeInOut(0.75), 1e-10));
    });

    test('is monotonic increasing', () {
      expect(easeInOut(0.3) < easeInOut(0.4), isTrue);
      expect(easeInOut(0.6) < easeInOut(0.7), isTrue);
    });
  });

  group('decelerate', () {
    test('returns 0.0 for t=0.0', () {
      expect(decelerate(0.0), closeTo(0.0, 1e-10));
    });

    test('returns 1.0 for t=1.0', () {
      expect(decelerate(1.0), closeTo(1.0, 1e-10));
    });

    test('returns correct value for t=0.5', () {
      expect(decelerate(0.5), closeTo(0.75, 1e-10));
    });

    test('is monotonic increasing', () {
      expect(decelerate(0.3) < decelerate(0.4), isTrue);
      expect(decelerate(0.6) < decelerate(0.7), isTrue);
    });
  });

  group('linear', () {
    test('returns 0.0 for t=0.0', () {
      expect(linear(0.0), closeTo(0.0, 1e-10));
    });

    test('returns 1.0 for t=1.0', () {
      expect(linear(1.0), closeTo(1.0, 1e-10));
    });

    test('returns t for any value', () {
      expect(linear(0.25), closeTo(0.25, 1e-10));
      expect(linear(0.75), closeTo(0.75, 1e-10));
    });
  });
}
