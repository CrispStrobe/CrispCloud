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
  if (key == null) return null;
  final primary =
      macOS && !service.isCustomized(action) && binding.ctrl && !binding.meta;
  return SingleActivator(
    key,
    control: primary ? false : binding.ctrl,
    meta: primary ? true : binding.meta,
    shift: binding.shift,
    alt: binding.alt,
  );
}

bool browserTextInputHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      (context.widget is EditableText ||
          context.findAncestorWidgetOfExactType<EditableText>() != null ||
          context.findAncestorStateOfType<EditableTextState>() != null);
}
