import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/utils/parser/int_parser.dart';

void main() {
  group('safeParseInt', () {
    test('parses valid int string', () {
      expect(safeParseInt('123'), 123);
    });

    test('returns fallback for null', () {
      expect(safeParseInt(null), 0);
      expect(safeParseInt(null, fallback: 7), 7);
    });

    test('returns fallback for invalid string', () {
      expect(safeParseInt('abc'), 0);
      expect(safeParseInt('abc', fallback: 5), 5);
    });

    test('returns int for int input', () {
      expect(safeParseInt(15), 15);
      expect(safeParseInt(-42), -42);
    });

    test('parses double string by truncating', () {
      expect(safeParseInt('12.7'), 12);
      expect(safeParseInt('99.99', fallback: 1), 99);
    });

    test('parses double input by truncating', () {
      expect(safeParseInt(7.8), 7);
      expect(safeParseInt(-3.2), -3);
    });

    test('returns fallback for completely invalid input', () {
      expect(safeParseInt({}, fallback: 11), 11);
      expect(safeParseInt([], fallback: 22), 22);
    });
  });

  group('tryParseInt', () {
    test('parses valid int string', () {
      expect(tryParseInt('123'), 123);
    });

    test('returns null for null', () {
      expect(tryParseInt(null), null);
    });

    test('returns null for invalid string', () {
      expect(tryParseInt('abc'), null);
    });

    test('returns int for int input', () {
      expect(tryParseInt(42), 42);
      expect(tryParseInt(-7), -7);
    });

    test('returns null for double string', () {
      expect(tryParseInt('12.7'), null);
    });

    test('returns null for double input', () {
      expect(tryParseInt(7.8), null);
    });

    test('returns null for non-number input', () {
      expect(tryParseInt({}), null);
      expect(tryParseInt([]), null);
    });
  });
}
