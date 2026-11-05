import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MediaEditorAction { exportCopy, close, undo, redo, preview }

class MediaEditorMenuActions {
  const MediaEditorMenuActions({required this.perform, required this.ready, required this.busy,
    required this.canUndo, required this.canRedo, required this.canPreview});
  final void Function(MediaEditorAction) perform;
  final bool ready, busy, canUndo, canRedo, canPreview;
  bool isEnabled(MediaEditorAction action) {
    if (busy) return false;
    if (action == MediaEditorAction.close) return true;
    if (!ready) return false;
    return switch (action) {
      MediaEditorAction.exportCopy => true,
      MediaEditorAction.close => true,
      MediaEditorAction.undo => canUndo,
      MediaEditorAction.redo => canRedo,
      MediaEditorAction.preview => canPreview,
    };
  }
  void dispatch(MediaEditorAction action) { if (isEnabled(action)) perform(action); }
}

final mediaEditorMenuProvider = StateProvider<MediaEditorMenuActions?>((ref) => null);
