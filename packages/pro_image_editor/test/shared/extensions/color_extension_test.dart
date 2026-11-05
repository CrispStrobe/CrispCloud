import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/extensions/color_extension.dart';

void main() {
  group('ColorToHex extension', () {
    test('toHex returns correct hex for opaque color', () {
      const color = Color.fromARGB(255, 18, 52, 86);
      final hex = color.toHex();
      expect(hex, equals(0xFF123456));
    });

    test('toHex returns correct hex for transparent color', () {
      const color = Color.fromARGB(0, 255, 255, 255);
      final hex = color.toHex();
      expect(hex, equals(0x00FFFFFF));
    });

    test('toHex returns correct hex for semi-transparent color', () {
      const color = Color.fromARGB(128, 10, 20, 30);
      final hex = color.toHex();
      expect(hex, equals(0x800A141E));
    });

    test('toHex returns correct hex for black', () {
      const color = Color.fromARGB(255, 0, 0, 0);
      final hex = color.toHex();
      expect(hex, equals(0xFF000000));
    });

    test('toHex returns correct hex for white', () {
      const color = Color.fromARGB(255, 255, 255, 255);
      final hex = color.toHex();
      expect(hex, equals(0xFFFFFFFF));
    });
  });
}
