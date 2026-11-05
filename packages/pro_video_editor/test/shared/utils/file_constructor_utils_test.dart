import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:pro_video_editor/shared/utils/file_constructor_utils.dart';

class MockFile extends Mock implements File {}

void main() {
  group('ensureFileInstance', () {
    test('returns File when given a String path', () {
      const filePath = 'test.txt';
      final file = ensureFileInstance(filePath);
      expect(file, isA<File>());
      expect(file.path, filePath);
    });

    test('returns the same File instance when given a File', () {
      final mockFile = MockFile();
      final result = ensureFileInstance(mockFile);
      expect(result, same(mockFile));
    });

    test('throws ArgumentError when given an int', () {
      expect(() => ensureFileInstance(123), throwsArgumentError);
    });

    test('throws ArgumentError when given null', () {
      expect(() => ensureFileInstance(null), throwsArgumentError);
    });

    test('throws ArgumentError when given an unsupported type', () {
      expect(() => ensureFileInstance([]), throwsArgumentError);
      expect(() => ensureFileInstance({}), throwsArgumentError);
      expect(() => ensureFileInstance(3.14), throwsArgumentError);
    });
  });
}
