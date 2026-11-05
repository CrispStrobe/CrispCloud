import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/pdf_editor_menu.dart';

/// Native File/Edit menus for the active PDF editor.
List<PlatformMenuItem> buildPdfEditorPlatformMenus(
  PdfEditorMenuActions editor,
) {
  PlatformMenuItem item(
    String label,
    PdfEditorMenuAction action, {
    SingleActivator? shortcut,
  }) => PlatformMenuItem(
    label: label,
    shortcut: shortcut,
    onSelected: editor.isEnabled(action) ? () => editor.dispatch(action) : null,
  );

  return <PlatformMenuItem>[
    PlatformMenu(
      label: 'File',
      menus: <PlatformMenuItem>[
        item(
          'Save',
          PdfEditorMenuAction.save,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
        ),
        item(
          'Save a Copy...',
          PdfEditorMenuAction.saveCopy,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          ),
        ),
        item('Export a Copy...', PdfEditorMenuAction.exportCopy),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            item(
              'Close Editor',
              PdfEditorMenuAction.close,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyW,
                meta: true,
              ),
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Edit',
      menus: <PlatformMenuItem>[
        item(
          'Undo',
          PdfEditorMenuAction.undo,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
        ),
        item(
          'Redo',
          PdfEditorMenuAction.redo,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ),
        ),
      ],
    ),
  ];
}
