// Flutter imports:
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A manager class responsible for handling desktop interactions in the
/// crop-rotate editor.
///
/// The `PaintDesktopInteractionManager` class provides methods for responding
/// to keyboard
/// and mouse events on desktop platforms.
class PaintDesktopInteractionManager {
  /// Manages desktop interactions for paint functionality.
  /// Creates an instance of [PaintDesktopInteractionManager].
  ///
  /// [context] is the build context used for interactions.
  PaintDesktopInteractionManager({required this.context});

  /// The build context used for interactions.
  final BuildContext context;

  /// Handles keyboard events.
  ///
  /// This method responds to key events and performs actions based on the
  /// pressed keys.
  /// Modifier state comes from the hardware keyboard because an embedding
  /// host can suppress events while another route covers the editor.
  bool onKey(KeyEvent event, {required Function(bool) onUndoRedo}) {
    final key = event.logicalKey.keyLabel;
    if (context.mounted) {
      if (event is KeyDownEvent) {
        switch (key) {
          case 'Z':
            final keyboard = HardwareKeyboard.instance;
            if ((keyboard.isControlPressed || keyboard.isMetaPressed) &&
                !keyboard.isAltPressed) {
              onUndoRedo(!keyboard.isShiftPressed);
            }
            break;
        }
      }
    }

    return false;
  }
}
