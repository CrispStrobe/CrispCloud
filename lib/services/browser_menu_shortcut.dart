import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'keyboard_shortcut_service.dart';

/// Convert the actual browser binding into a native menu accelerator. Defaults
/// use Command on macOS; user-recorded modifiers remain exact.
SingleActivator? browserMenuShortcut(
  KeyboardShortcutService service,
  ShortcutAction action, {
  bool macOS = true,
}) {
  final binding = service.getBinding(action);
  String normalize(String value) =>
      value == ' ' ? 'space' : value.trim().toLowerCase();
  final key = LogicalKeyboardKey.knownLogicalKeys
      .where((key) => normalize(key.keyLabel) == normalize(binding.key))
      .firstOrNull;
  if (key == null ||
      {
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.altRight,
        LogicalKeyboardKey.meta,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.metaRight,
      }.contains(key))
    return null;
  final primary =
      macOS && !service.isCustomized(action) && binding.ctrl && !binding.meta;
  final control = primary ? false : binding.ctrl;
  final meta = primary ? true : binding.meta;
  // Imported collisions must follow the same custom-binding priority as
  // Flutter dispatch; a native accelerator must never claim another action.
  final resolved = service.resolveBrowser(
    KeyDownEvent(
      physicalKey: const PhysicalKeyboardKey(0),
      logicalKey: key,
      timeStamp: Duration.zero,
    ),
    isCtrl: control,
    isMeta: meta,
    isShift: binding.shift,
    isAlt: binding.alt,
  );
  if (resolved != action) return null;
  return SingleActivator(
    key,
    control: control,
    meta: meta,
    shift: binding.shift,
    alt: binding.alt,
    includeRepeats: false,
  );
}

bool browserTextInputHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      (context.widget is EditableText ||
          context.findAncestorWidgetOfExactType<EditableText>() != null ||
          context.findAncestorStateOfType<EditableTextState>() != null);
}
