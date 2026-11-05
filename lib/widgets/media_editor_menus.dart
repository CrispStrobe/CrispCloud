import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n/media_editor_strings.dart';
import '../services/media_editor_menu.dart';

List<PlatformMenuItem> buildMediaEditorPlatformMenus(
  BuildContext context,
  MediaEditorMenuActions editor,
) {
  PlatformMenuItem item(
    String label,
    MediaEditorAction action,
    SingleActivator shortcut,
  ) => PlatformMenuItem(
    label: context.mediaTr(label),
    shortcut: shortcut,
    onSelected: editor.isEnabled(action) ? () => editor.dispatch(action) : null,
  );
  return [
    PlatformMenu(
      label: context.mediaTr('File'),
      menus: [
        item(
          'Export copy',
          MediaEditorAction.exportCopy,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
        ),
        item(
          'Close editor',
          MediaEditorAction.close,
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
        ),
      ],
    ),
    PlatformMenu(
      label: context.mediaTr('Edit'),
      menus: [
        item(
          'Undo',
          MediaEditorAction.undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
        ),
        item(
          'Redo',
          MediaEditorAction.redo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ),
        ),
      ],
    ),
  ];
}
