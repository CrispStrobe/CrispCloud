import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/utils/parser/size_parser.dart';

void main() {
  group('safeParseSize', () {
    test('parses valid width and height', () {
      final map = {'width': 200, 'height': 100};
      final result = safeParseSize(map);
      expect(result, const Size(200.0, 100.0));
    });

    test('returns fallback for null map', () {
      const fallback = Size(10, 20);
      final result = safeParseSize(null, fallback: fallback);
      expect(result, fallback);
    });

    test('returns Size.zero for null map if no fallback', () {
      final result = safeParseSize(null);
      expect(result, Size.zero);
    });

    test('parses width and height as strings', () {
      final map = {'width': '50.5', 'height': '25.2'};
      final result = safeParseSize(map);
      expect(result, const Size(50.5, 25.2));
    });

    test('uses fallback if width is invalid', () {
      const fallback = Size(1, 2);
      final map = {'width': 'abc', 'height': 10};
      final result = safeParseSize(map, fallback: fallback);
      expect(result.width, fallback.width);
      expect(result.height, 10);
    });

    test('uses fallback if height is invalid', () {
      const fallback = Size(3, 4);
      final map = {'width': 10, 'height': 'xyz'};
      final result = safeParseSize(map, fallback: fallback);
      expect(result.width, 10);
      expect(result.height, fallback.height);
    });

    test('uses fallback if both width and height are missing', () {
      const fallback = Size(5, 6);
      Map<String, dynamic>? map = {};
      final result = safeParseSize(map, fallback: fallback);
      expect(result, fallback);
    });

    test('parses using "w" and "h" keys', () {
      final map = {'w': 12, 'h': 34};
      final result = safeParseSize(map);
      expect(result, const Size(12.0, 34.0));
    });

    test('uses fallback width if width is missing', () {
      const fallback = Size(7, 8);
      final map = {'height': 20};
      final result = safeParseSize(map, fallback: fallback);
      expect(result.width, fallback.width);
      expect(result.height, 20.0);
    });

    test('uses fallback height if height is missing', () {
      const fallback = Size(9, 10);
      final map = {'width': 30};
      final result = safeParseSize(map, fallback: fallback);
      expect(result.width, 30.0);
      expect(result.height, fallback.height);
    });
  });
}
