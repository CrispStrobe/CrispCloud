import 'package:flutter/foundation.dart';

import '/core/models/editor_callbacks/standalone_editor_callbacks.dart';
import '/pro_image_editor.dart';

/// A factory class for creating [StandaloneEditorCallbacks] instances
/// for each supported [EditorMode].
class EditorFactory {
  /// A private map that links each [EditorMode] to its corresponding
  /// [StandaloneEditorCallbacks] implementation.
  ///
  /// This map is initialized with constant instances of each editor's
  /// callbacks.
  @visibleForTesting
  static final Map<EditorMode, StandaloneEditorCallbacks> editorMap = {
    EditorMode.paint: const PaintEditorCallbacks(),
    EditorMode.cropRotate: const CropRotateEditorCallbacks(),
    EditorMode.filter: const FilterEditorCallbacks(),
    EditorMode.tune: const TuneEditorCallbacks(),
    EditorMode.blur: const BlurEditorCallbacks(),
    EditorMode.emoji: const EmojiEditorCallbacks(),
    EditorMode.sticker: const StickerEditorCallbacks(),
    EditorMode.text: const TextEditorCallbacks(),
    EditorMode.main: const MainEditorCallbacks(),
  };

  /// Retrieves the [StandaloneEditorCallbacks] instance associated with
  /// the specified [EditorMode].
  ///
  /// If no editor callbacks are found for the given [EditorMode], an
  /// [UnimplementedError] is thrown.
  ///
  /// - [mode]: The [EditorMode] for which the editor callbacks are required.
  ///
  /// Returns:
  /// - A [StandaloneEditorCallbacks] instance corresponding to the [mode].
  ///
  /// Throws:
  /// - [UnimplementedError] if the provided [mode] is not supported.
  static StandaloneEditorCallbacks getEditor(EditorMode mode) {
    final callback = editorMap[mode];
    if (callback != null) {
      return callback;
    } else {
      throw UnimplementedError('No editor found for $mode');
    }
  }
}
