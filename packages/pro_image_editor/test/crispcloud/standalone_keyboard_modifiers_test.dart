import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/features/crop_rotate_editor/services/crop_desktop_interaction_manager.dart';
import 'package:pro_image_editor/features/paint_editor/services/paint_desktop_interaction_manager.dart';

class _KeyboardHarness {
  _KeyboardHarness({required this.dispatch, required this.actions});

  final bool Function(KeyEvent) dispatch;
  final List<bool> actions;
  bool blocked = false;

  // Models the standalone host callback: covered/busy editors do not receive
  // events, but Flutter still updates the real hardware keyboard state.
  bool onKey(KeyEvent event) => blocked ? true : dispatch(event);
}

Future<_KeyboardHarness> _mountManager(
  WidgetTester tester, {
  required bool crop,
}) async {
  late BuildContext context;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(
        builder: (value) {
          context = value;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  final actions = <bool>[];
  final bool Function(KeyEvent) dispatch;
  if (crop) {
    final manager = CropDesktopInteractionManager(context: context);
    dispatch = (event) => manager.onKey(
      event,
      onTranslate: (_) {},
      onScale: (_) {},
      onUndoRedo: actions.add,
      onFlip: () {},
      onRotate: () {},
    );
  } else {
    final manager = PaintDesktopInteractionManager(context: context);
    dispatch = (event) => manager.onKey(event, onUndoRedo: actions.add);
  }
  final harness = _KeyboardHarness(dispatch: dispatch, actions: actions);
  final handler = harness.onKey;
  HardwareKeyboard.instance.addHandler(handler);
  addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));
  return harness;
}

Future<void> _withPressed(
  WidgetTester tester,
  List<LogicalKeyboardKey> keys,
  Future<void> Function() body,
) async {
  try {
    for (final key in keys) {
      await tester.sendKeyDownEvent(key);
    }
    await body();
  } finally {
    for (final key in keys.reversed) {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(key)) {
        await tester.sendKeyUpEvent(key);
      }
    }
  }
}

void main() {
  for (final crop in [false, true]) {
    final name = crop ? 'crop' : 'paint';

    testWidgets('$name forgets modifiers released while the host blocks events',
        (tester) async {
      final harness = await _mountManager(tester, crop: crop);
      await _withPressed(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftRight,
      ], () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        expect(harness.actions, [false]);

        harness.blocked = true;
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        harness.blocked = false;
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);

        expect(harness.actions, [false], reason: 'Bare Z must not undo or redo');
      });
      await _withPressed(tester, [LogicalKeyboardKey.controlRight], () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        expect(harness.actions, [false, true]);
      });
    });

    testWidgets('$name uses released Shift state while Control stays held',
        (tester) async {
      final harness = await _mountManager(tester, crop: crop);
      await _withPressed(tester, [
        LogicalKeyboardKey.controlRight,
        LogicalKeyboardKey.shiftLeft,
      ], () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        expect(harness.actions, [false]);
        harness.blocked = true;
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        harness.blocked = false;
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        expect(harness.actions, [false, true]);
      });
    });

    testWidgets('$name recognizes modifiers pressed while the host was covered',
        (tester) async {
      final harness = await _mountManager(tester, crop: crop);
      harness.blocked = true;
      await _withPressed(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftRight,
      ], () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        expect(harness.actions, isEmpty);
        harness.blocked = false;
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        expect(harness.actions, [false]);
      });
    });

    for (final command in [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    ]) {
      testWidgets('$name ${command.keyLabel} supports undo and Shift redo',
          (tester) async {
        final harness = await _mountManager(tester, crop: crop);
        await _withPressed(tester, [command], () async {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
          expect(harness.actions, [true]);
          await _withPressed(tester, [LogicalKeyboardKey.shiftLeft], () async {
            await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
            expect(harness.actions, [true, false]);
            await _withPressed(tester, [LogicalKeyboardKey.altLeft], () async {
              await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
              expect(harness.actions, [true, false],
                  reason: 'Alt combinations must not trigger undo or redo');
            });
          });
        });
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        expect(harness.actions, [true, false]);
      });
    }
  }
}
