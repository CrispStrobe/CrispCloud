import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/utils/unique_id_generator.dart';

void main() {
  group('generateUniqueId', () {
    test('should return a non-empty string', () {
      final id = generateUniqueId();
      expect(id, isNotEmpty);
    });

    test('should return a string of expected length (timestamp + 20)', () {
      final id = generateUniqueId();
      // timestamp is 8 chars, randomPart is 20 chars
      expect(id.length, equals(28));
    });

    test('should generate unique values on multiple calls', () {
      final ids = <String>{};
      for (int i = 0; i < 100; i++) {
        ids.add(generateUniqueId());
      }
      expect(ids.length, equals(100));
    });

    test('should contain only allowed characters', () {
      final id = generateUniqueId();
      final allowed = RegExp(r'^[A-Za-z0-9]+$');
      expect(allowed.hasMatch(id), isTrue);
    });

    test('timestamp part should be base36 and 8 chars', () {
      final id = generateUniqueId();
      final timestampPart = id.substring(0, 8);
      final base36 = RegExp(r'^[a-z0-9]{8}$');
      expect(base36.hasMatch(timestampPart), isTrue);
    });
  });
}
