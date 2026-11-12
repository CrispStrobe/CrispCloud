import 'package:flutter/services.dart';

import '../models/file_item.dart';

/// Double-click recognition can delay a tap until after its modifiers have
/// been released. Retain each row's actual pointer-down state across rebuilds.
class FilePointerModifiers {
  const FilePointerModifiers({required this.shift, required this.toggle});

  final bool shift;
  final bool toggle;
  static final _snapshots = Expando<FilePointerModifiers>();

  static FilePointerModifiers _current() => FilePointerModifiers(
    shift: HardwareKeyboard.instance.isShiftPressed,
    toggle:
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed,
  );

  static void capture(FileItem file) => _snapshots[file] = _current();
  static FilePointerModifiers forFile(FileItem file) =>
      _snapshots[file] ?? _current();
}
