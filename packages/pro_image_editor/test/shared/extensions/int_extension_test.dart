import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/extensions/int_extension.dart';

void main() {
  group('IntFormatter.toBytesString', () {
    test('returns "0 B" for zero', () {
      expect(0.toBytesString(), '0 B');
    });

    test('returns "0 B" for negative values', () {
      expect((-100).toBytesString(), '0 B');
    });

    test('formats bytes correctly', () {
      expect(1.toBytesString(), '1.00 B');
      expect(512.toBytesString(), '512.00 B');
      expect(1023.toBytesString(), '1023.00 B');
    });

    test('formats kilobytes correctly', () {
      expect(1024.toBytesString(), '1.00 KB');
      expect(1536.toBytesString(), '1.50 KB');
      expect(2048.toBytesString(), '2.00 KB');
    });

    test('formats megabytes correctly', () {
      expect(1048576.toBytesString(), '1.00 MB');
      expect(2097152.toBytesString(), '2.00 MB');
    });

    test('formats gigabytes correctly', () {
      expect(1073741824.toBytesString(), '1.00 GB');
    });

    test('formats terabytes correctly', () {
      expect(1099511627776.toBytesString(), '1.00 TB');
    });

    test('respects decimals argument', () {
      expect(1048576.toBytesString(1), '1.0 MB');
      expect(1536.toBytesString(3), '1.500 KB');
    });
  });
}
