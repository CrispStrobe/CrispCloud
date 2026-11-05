import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/utils/parser/double_parser.dart';

void main() {
  group('safeParseDouble', () {
    test('parses valid double string', () {
      expect(safeParseDouble('3.14'), equals(3.14));
    });

    test('parses valid int string', () {
      expect(safeParseDouble('42'), equals(42.0));
    });

    test('parses int value', () {
      expect(safeParseDouble(10), equals(10.0));
    });

    test('returns fallback for null', () {
      expect(safeParseDouble(null), equals(0));
      expect(safeParseDouble(null, fallback: 1.5), equals(1.5));
    });

    test('returns fallback for invalid string', () {
      expect(safeParseDouble('abc'), equals(0));
      expect(safeParseDouble('abc', fallback: 2.2), equals(2.2));
    });

    test('parses already double value', () {
      expect(safeParseDouble(5.5), equals(5.5));
    });

    test('parses string with spaces', () {
      expect(safeParseDouble('  7.7  '), equals(7.7));
    });
  });

  group('tryParseDouble', () {
    test('parses valid double string', () {
      expect(tryParseDouble('3.14'), equals(3.14));
    });

    test('parses valid int string', () {
      expect(tryParseDouble('42'), equals(42.0));
    });

    test('parses int value', () {
      expect(tryParseDouble(10), equals(10.0));
    });

    test('returns null for invalid string', () {
      expect(tryParseDouble('abc'), isNull);
    });

    test('parses already double value', () {
      expect(tryParseDouble(5.5), equals(5.5));
    });

    test('parses string with spaces', () {
      expect(tryParseDouble('  7.7  '), equals(7.7));
    });

    test('returns null when value is null', () {
      expect(tryParseDouble(null), isNull);
    });
  });
}
