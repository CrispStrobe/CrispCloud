import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/core/services/keyboard_service.dart';

void main() {
  for (final key in <LogicalKeyboardKey>[
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  ]) {
    testWidgets('recognizes ${key.debugName} as an edit shortcut modifier', (
      tester,
    ) async {
      final keyboard = KeyboardService();
      expect(keyboard.isCtrlPressed, isFalse);

      await tester.sendKeyDownEvent(key);
      expect(keyboard.isCtrlPressed, isTrue);
      await tester.sendKeyUpEvent(key);
      expect(keyboard.isCtrlPressed, isFalse);
    });
  }
}
