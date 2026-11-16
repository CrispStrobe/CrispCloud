import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Reads left/right Ctrl+Shift from the hardware keyboard.
///
/// Right Ctrl+Right Shift → `true` (RTL). Left Ctrl+Left Shift → `false` (LTR).
bool? officeDirectionFromKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent) {
    return null;
  }
  if (!_isCtrlOrShift(event.logicalKey, event.physicalKey)) {
    return null;
  }
  return officeParagraphDirectionFromSides(
    leftCtrl: _sideDown(
      physical: PhysicalKeyboardKey.controlLeft,
      logical: LogicalKeyboardKey.controlLeft,
    ),
    rightCtrl: _sideDown(
      physical: PhysicalKeyboardKey.controlRight,
      logical: LogicalKeyboardKey.controlRight,
    ),
    leftShift: _sideDown(
      physical: PhysicalKeyboardKey.shiftLeft,
      logical: LogicalKeyboardKey.shiftLeft,
    ),
    rightShift: _sideDown(
      physical: PhysicalKeyboardKey.shiftRight,
      logical: LogicalKeyboardKey.shiftRight,
    ),
    extraKeys: _hasNonDirectionKey(),
  );
}

/// Recognizes a bare direction chord on release. Pressing Ctrl+Shift is also
/// the prefix of redo, Save As and many other shortcuts, so it cannot mutate
/// document history until we know that no other key participated.
class OfficeDirectionKeyChord {
  bool? _pending;
  bool _cancelled = false;

  void reset() {
    _pending = null;
    _cancelled = false;
  }

  bool? handle(KeyEvent event) {
    final modifier = _isCtrlOrShift(event.logicalKey, event.physicalKey);
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (!modifier ||
          HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        _pending = null;
        _cancelled = true;
      } else if (!_cancelled) {
        _pending = officeDirectionFromKeyEvent(event) ?? _pending;
      }
    }
    if (event is KeyUpEvent) {
      final result = modifier && !_cancelled ? _pending : null;
      _pending = null;
      final keyboard = HardwareKeyboard.instance;
      if (!keyboard.isControlPressed && !keyboard.isShiftPressed) {
        reset();
      } else if (result != null) {
        _cancelled = true;
      }
      return result;
    }
    return null;
  }
}

bool _isCtrlOrShift(LogicalKeyboardKey logical, PhysicalKeyboardKey physical) {
  return logical == LogicalKeyboardKey.control ||
      logical == LogicalKeyboardKey.controlLeft ||
      logical == LogicalKeyboardKey.controlRight ||
      logical == LogicalKeyboardKey.shift ||
      logical == LogicalKeyboardKey.shiftLeft ||
      logical == LogicalKeyboardKey.shiftRight ||
      physical == PhysicalKeyboardKey.controlLeft ||
      physical == PhysicalKeyboardKey.controlRight ||
      physical == PhysicalKeyboardKey.shiftLeft ||
      physical == PhysicalKeyboardKey.shiftRight;
}

bool _sideDown({
  required PhysicalKeyboardKey physical,
  required LogicalKeyboardKey logical,
}) {
  return HardwareKeyboard.instance.physicalKeysPressed.contains(physical) ||
      HardwareKeyboard.instance.logicalKeysPressed.contains(logical);
}

bool _hasNonDirectionKey() {
  for (final LogicalKeyboardKey key
      in HardwareKeyboard.instance.logicalKeysPressed) {
    if (_isModifier(key)) {
      continue;
    }
    return true;
  }
  return HardwareKeyboard.instance.isAltPressed;
}

bool _isModifier(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight ||
      key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight;
}
