import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/office_direction_keys.dart';

void main() {
  for (final rtl in [false, true]) {
    testWidgets('bare Ctrl Shift direction chord $rtl runs once on release', (
      tester,
    ) async {
      final recognizer = OfficeDirectionKeyChord();
      final directions = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              final direction = recognizer.handle(event);
              if (direction != null) directions.add(direction);
              return KeyEventResult.handled;
            },
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      final ctrl = rtl
          ? LogicalKeyboardKey.controlRight
          : LogicalKeyboardKey.controlLeft;
      final shift = rtl
          ? LogicalKeyboardKey.shiftRight
          : LogicalKeyboardKey.shiftLeft;
      await tester.sendKeyDownEvent(ctrl);
      await tester.sendKeyDownEvent(shift);
      expect(directions, isEmpty);
      await tester.sendKeyUpEvent(shift);
      await tester.sendKeyUpEvent(ctrl);
      expect(directions, [rtl]);
    });
  }
  testWidgets('Ctrl Shift Z and S never emit a direction change', (
    tester,
  ) async {
    final recognizer = OfficeDirectionKeyChord();
    final directions = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            final direction = recognizer.handle(event);
            if (direction != null) directions.add(direction);
            return KeyEventResult.handled;
          },
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();
    for (final key in [LogicalKeyboardKey.keyZ, LogicalKeyboardKey.keyS]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    expect(directions, isEmpty);
  });
}
