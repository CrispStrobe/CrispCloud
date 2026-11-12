import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n/ebook_strings.dart';
import '../services/ebook_editor_menu.dart';

List<PlatformMenuItem> buildEbookEditorPlatformMenus(
  BuildContext context,
  EbookEditorMenuActions editor,
) {
  PlatformMenuItem item(
    String label,
    EbookEditorMenuAction action, {
    LogicalKeyboardKey? key,
    bool shift = false,
  }) => PlatformMenuItem(
    label: context.ebookTr(label),
    shortcut: key == null
        ? null
        : SingleActivator(key, meta: true, shift: shift),
    onSelected: editor.isEnabled(action) ? () => editor.dispatch(action) : null,
  );
  return [
    PlatformMenu(
      label: context.ebookTr('File'),
      menus: [
        item('Save', EbookEditorMenuAction.save, key: LogicalKeyboardKey.keyS),
        item(
          'Save a copy',
          EbookEditorMenuAction.saveCopy,
          key: LogicalKeyboardKey.keyS,
          shift: true,
        ),
        item('Export a copy', EbookEditorMenuAction.exportCopy),
        item(
          'Close',
          EbookEditorMenuAction.close,
          key: LogicalKeyboardKey.keyW,
        ),
      ],
    ),
    PlatformMenu(
      label: context.ebookTr('Edit'),
      menus: [
        item('Undo', EbookEditorMenuAction.undo, key: LogicalKeyboardKey.keyZ),
        item(
          'Redo',
          EbookEditorMenuAction.redo,
          key: LogicalKeyboardKey.keyZ,
          shift: true,
        ),
      ],
    ),
  ];
}
