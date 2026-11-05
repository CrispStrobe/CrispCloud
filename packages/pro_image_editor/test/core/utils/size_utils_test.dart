import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/core/utils/size_utils.dart';

void main() {
  group('getValidSizeOrDefault', () {
    test('returns a when a is non-null and not empty', () {
      const a = Size(10, 20);
      const b = Size(5, 5);

      final result = getValidSizeOrDefault(a, b);

      expect(result, a);
    });

    test('returns b when a is null and b is not empty', () {
      const Size? a = null;
      const b = Size(7, 8);

      final result = getValidSizeOrDefault(a, b);

      expect(result, b);
    });

    test('returns b when a is empty and b is not empty', () {
      const a = Size.zero;
      const b = Size(3, 4);

      final result = getValidSizeOrDefault(a, b);

      expect(result, b);
    });

    test('returns Size(1,1) when both a is null and b is empty', () {
      const Size? a = null;
      const b = Size.zero;

      final result = getValidSizeOrDefault(a, b);

      expect(result, const Size(1, 1));
    });

    test('returns Size(1,1) when a is empty and b is empty', () {
      const a = Size.zero;
      const b = Size.zero;

      final result = getValidSizeOrDefault(a, b);

      expect(result, const Size(1, 1));
    });
  });
}
