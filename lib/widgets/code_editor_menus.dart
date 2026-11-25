import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/code_editor_menu.dart';

/// Native File/Edit/View/Go menus for the active code editor.
///
/// Like the Office and image editors, the code editor owns a small provider
/// snapshot while it is open. The browser screen turns that snapshot into
/// real [PlatformMenuBar] entries instead of leaving the commands only in the
/// editor's local overflow button.
List<PlatformMenuItem> buildCodeEditorPlatformMenus(
  CodeEditorMenuActions editor,
) {
  PlatformMenuItem item(
    String label,
    CodeEditorMenuAction action, {
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
          CodeEditorMenuAction.save,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
        ),
        item(
          'Reload from Disk',
          CodeEditorMenuAction.reload,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            item(
              'Close Editor',
              CodeEditorMenuAction.close,
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
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            item(
              'Undo',
              CodeEditorMenuAction.undo,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
            ),
            item(
              'Redo',
              CodeEditorMenuAction.redo,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            item(
              'Cut',
              CodeEditorMenuAction.cut,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyX,
                meta: true,
              ),
            ),
            item(
              'Copy',
              CodeEditorMenuAction.copy,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyC,
                meta: true,
              ),
            ),
            item(
              'Paste',
              CodeEditorMenuAction.paste,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyV,
                meta: true,
              ),
            ),
            item(
              'Select All',
              CodeEditorMenuAction.selectAll,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyA,
                meta: true,
              ),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            item(
              'Find...',
              CodeEditorMenuAction.find,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
              ),
            ),
            item(
              'Find Next',
              CodeEditorMenuAction.findNext,
              shortcut: const SingleActivator(LogicalKeyboardKey.f3),
            ),
            item(
              'Find Previous',
              CodeEditorMenuAction.findPrevious,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.f3,
                shift: true,
              ),
            ),
            item(
              'Find and Replace...',
              CodeEditorMenuAction.replace,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
                alt: true,
              ),
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'View',
      menus: <PlatformMenuItem>[
        item(
          'Toggle Word Wrap',
          CodeEditorMenuAction.toggleWordWrap,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, alt: true),
        ),
        item(
          'Toggle Syntax Highlighting',
          CodeEditorMenuAction.toggleHighlighting,
        ),
      ],
    ),
    PlatformMenu(
      label: 'Go',
      menus: <PlatformMenuItem>[
        item(
          'Go to Line...',
          CodeEditorMenuAction.goToLine,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyG, meta: true),
        ),
      ],
    ),
  ];
}
