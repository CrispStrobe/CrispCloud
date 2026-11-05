import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/utils/file_constructor_utils.dart';

void main() {
  group('ensureFileInstance', () {
    test('returns File when given a String path', () {
      const filePath = 'test.png';
      final file = ensureFileInstance(filePath);
      expect(file, isA<File>());
      expect(file.path, filePath);
    });

    test('returns the same File instance when given a File', () {
      final file = File('test.png');
      final result = ensureFileInstance(file);
      expect(result, same(file));
    });

    test('throws ArgumentError when given an invalid type', () {
      expect(() => ensureFileInstance(123), throwsA(isA<ArgumentError>()));
      expect(() => ensureFileInstance(1.1), throwsA(isA<ArgumentError>()));
      expect(() => ensureFileInstance(null), throwsA(isA<ArgumentError>()));
      expect(() => ensureFileInstance(true), throwsA(isA<ArgumentError>()));
      expect(() => ensureFileInstance([]), throwsA(isA<ArgumentError>()));
      expect(() => ensureFileInstance({}), throwsA(isA<ArgumentError>()));
    });
  });
}
