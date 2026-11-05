// Flutter imports:
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A manager class responsible for handling desktop interactions in the
/// crop-rotate editor.
///
/// The `DesktopInteractionManager` class provides methods for responding to
/// keyboard
/// and mouse events on desktop platforms.
class CropDesktopInteractionManager {
  /// Manages user interactions for the crop desktop interface.
  CropDesktopInteractionManager({required this.context});

  /// Build context for the interaction manager.
  final BuildContext context;

  /// Handles keyboard events.
  ///
  /// This method responds to key events and performs actions based on the
  /// pressed keys.
  /// Modifier state comes from the hardware keyboard because an embedding
  /// host can suppress events while another route covers the editor.
  bool onKey(
    KeyEvent event, {
    required Function(Offset) onTranslate,
    required Function(double) onScale,
    required Function(bool) onUndoRedo,
    required Function() onFlip,
    required Function() onRotate,
  }) {
    final key = event.logicalKey.keyLabel;
    if (context.mounted) {
      if (event is KeyDownEvent) {
        double scaleFactor = 0.2;
        double translateFactor = 20;
        switch (key) {
          case 'R':
            onRotate();
            break;
          case 'F':
            onFlip();
            break;
          case 'Subtract':
          case 'Numpad Subtract':
          case 'Page Down':
            onScale(-scaleFactor);
            break;
          case 'Add':
          case 'Numpad Add':
          case 'Page Up':
            onScale(scaleFactor);
            break;
          case 'Arrow Up':
            onTranslate(Offset(0, translateFactor));
            break;
          case 'Arrow Down':
            onTranslate(Offset(0, -translateFactor));
            break;
          case 'Arrow Left':
            onTranslate(Offset(translateFactor, 0));
            break;
          case 'Arrow Right':
            onTranslate(Offset(-translateFactor, 0));
            break;
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
