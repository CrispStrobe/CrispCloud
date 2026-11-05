import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Commands shared by the image editor's host toolbar and native menu bar.
enum ImageEditorAction {
  save,
  exportCopy,
  saveProjectCopy,
  close,
  undo,
  redo,
  zoomIn,
  zoomOut,
  zoomReset,
  layers,
  cropRotate,
  paint,
  text,
  filter,
  blur,
  tune,
}

/// A snapshot of the active image editor's command availability.
///
/// CrispCloud owns the commands and persistence. The editor publishes a new
/// snapshot when history, save state, or the active tool changes so macOS can
/// update the real menu items as well as the Flutter toolbar.
class ImageEditorMenuActions {
  const ImageEditorMenuActions({
    required this.perform,
    required this.canSave,
    required this.canUndo,
    required this.canRedo,
    this.busy = false,
    this.canEdit = true,
  });

  final void Function(ImageEditorAction action) perform;
  final bool canSave;
  final bool canUndo;
  final bool canRedo;
  final bool busy;

  /// False while a tool's subeditor is open. History and save commands must not
  /// target the main image until that tool is applied or cancelled.
  final bool canEdit;

  bool isEnabled(ImageEditorAction action) {
    if (busy) return false;
    if (action == ImageEditorAction.close) return true;
    if (!canEdit) return false;
    return switch (action) {
      ImageEditorAction.save => canSave,
      ImageEditorAction.undo => canUndo,
      ImageEditorAction.redo => canRedo,
      _ => true,
    };
  }

  /// The dialog also guards the operation itself, because a native event may
  /// already be queued when this snapshot is replaced.
  void dispatch(ImageEditorAction action) {
    if (isEnabled(action)) perform(action);
  }
}

/// Null while no image editor is open.
final StateProvider<ImageEditorMenuActions?> imageEditorMenuProvider =
    StateProvider<ImageEditorMenuActions?>((Ref ref) => null);
