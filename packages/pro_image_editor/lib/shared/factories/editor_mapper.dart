import '/core/models/init_configs/editor_init_configs.dart';
import '/pro_image_editor.dart';

/// A utility class that maps [EditorInitConfigs] instances to their
/// corresponding [EditorMode].
class EditorMapper {
  /// Returns the corresponding [EditorMode] for the given [EditorInitConfigs].
  ///
  /// This method performs a type check on the provided [configs] and
  /// maps it to the appropriate [EditorMode]. If the configuration type
  /// is not recognized, an [UnimplementedError] is thrown.
  ///
  /// - [configs]: An instance of [EditorInitConfigs] that specifies
  ///   the configuration for a specific editor mode.
  ///
  /// Returns:
  /// - The [EditorMode] associated with the given [configs].
  ///
  /// Throws:
  /// - [UnimplementedError] if the [configs] type does not match any known
  ///   editor mode.
  static EditorMode getEditorModeFromConfigs(EditorInitConfigs configs) {
    switch (configs) {
      case PaintEditorInitConfigs():
        return EditorMode.paint;
      case TextEditorConfigs():
        return EditorMode.text;
      case CropRotateEditorInitConfigs():
        return EditorMode.cropRotate;
      case TuneEditorInitConfigs():
        return EditorMode.tune;
      case FilterEditorInitConfigs():
        return EditorMode.filter;
      case BlurEditorInitConfigs():
        return EditorMode.blur;
      case EmojiEditorConfigs():
        return EditorMode.emoji;
      case StickerEditorConfigs():
        return EditorMode.sticker;
      case MainEditorConfigs():
        return EditorMode.main;
      default:
        throw UnimplementedError(
          'No matching editor mode found for ${configs.runtimeType}',
        );
    }
  }
}
