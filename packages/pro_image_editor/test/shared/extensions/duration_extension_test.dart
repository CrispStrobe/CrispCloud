import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/extensions/duration_extension.dart';

void main() {
  group('DurationFormatter.toTimeString', () {
    test('formats 0 seconds as 00:00', () {
      expect(const Duration(seconds: 0).toTimeString(), '00:00');
    });

    test('formats less than a minute', () {
      expect(const Duration(seconds: 5).toTimeString(), '00:05');
      expect(const Duration(seconds: 59).toTimeString(), '00:59');
    });

    test('formats exactly one minute', () {
      expect(const Duration(seconds: 60).toTimeString(), '01:00');
    });

    test('formats minutes and seconds', () {
      expect(const Duration(seconds: 75).toTimeString(), '01:15');
      expect(const Duration(seconds: 125).toTimeString(), '02:05');
    });

    test('formats multiple minutes', () {
      expect(const Duration(minutes: 12, seconds: 34).toTimeString(), '12:34');
    });

    test('formats hours as total minutes', () {
      expect(
        const Duration(hours: 1, minutes: 2, seconds: 3).toTimeString(),
        '62:03',
      );
    });

    test('pads single digit minutes and seconds', () {
      expect(const Duration(minutes: 3, seconds: 7).toTimeString(), '03:07');
    });
  });
}
