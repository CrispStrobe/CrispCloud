import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n/image_editor_strings.dart';
import '../services/image_editor_menu.dart';

/// Native File/Edit/Image menus for the active image editor.
///
/// Keeping these separate from the browser menu construction prevents browser
/// file operations and shortcuts from acting on the selected file underneath
/// an image editing dialog.
List<PlatformMenuItem> buildImageEditorPlatformMenus(
  BuildContext context,
  ImageEditorMenuActions editor,
) {
  PlatformMenuItem item(
    String label,
    ImageEditorAction action, {
    SingleActivator? shortcut,
  }) => PlatformMenuItem(
    label: context.imageTr(label),
    shortcut: shortcut,
    onSelected: editor.isEnabled(action) ? () => editor.dispatch(action) : null,
  );

  return <PlatformMenuItem>[
    PlatformMenu(
      label: context.imageTr('File'),
      menus: <PlatformMenuItem>[
        item(
          'Save',
          ImageEditorAction.save,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
        ),
        item(
          'Close editor',
          ImageEditorAction.close,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
        ),
      ],
    ),
    PlatformMenu(
      label: context.imageTr('Edit'),
      menus: <PlatformMenuItem>[
        item(
          'Undo',
          ImageEditorAction.undo,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
        ),
        item(
          'Redo',
          ImageEditorAction.redo,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ),
        ),
      ],
    ),
    PlatformMenu(
      label: context.imageTr('Image'),
      menus: <PlatformMenuItem>[
        item('Crop and rotate', ImageEditorAction.cropRotate),
        item('Draw', ImageEditorAction.paint),
        item('Text', ImageEditorAction.text),
        item('Filters', ImageEditorAction.filter),
        item('Blur', ImageEditorAction.blur),
        item('Adjust', ImageEditorAction.tune),
      ],
    ),
  ];
}
