import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Commands shared by the code editor chrome and the app menu bar.
enum CodeEditorMenuAction {
  save,
  close,
  reload,
  undo,
  redo,
  cut,
  copy,
  paste,
  selectAll,
  find,
  replace,
  goToLine,
  toggleWordWrap,
  toggleHighlighting,
}

/// A snapshot of the active code editor's command availability.
///
/// The dialog publishes a new snapshot whenever the save state, selection or
/// history changes so the native menu can enable and disable items without
/// reaching into the editor's private state.
class CodeEditorMenuActions {
  const CodeEditorMenuActions({
    required this.perform,
    required this.canSave,
    required this.canUndo,
    required this.canRedo,
    required this.hasSelection,
    required this.canReload,
    required this.canHighlight,
    this.busy = false,
  });

  final void Function(CodeEditorMenuAction action) perform;
  final bool canSave;
  final bool canUndo;
  final bool canRedo;
  final bool hasSelection;
  final bool canReload;
  final bool canHighlight;
  final bool busy;

  bool isEnabled(CodeEditorMenuAction action) {
    if (action == CodeEditorMenuAction.close) return true;
    if (busy) return false;
    return switch (action) {
      CodeEditorMenuAction.save => canSave,
      CodeEditorMenuAction.close => true,
      CodeEditorMenuAction.reload => canReload,
      CodeEditorMenuAction.undo => canUndo,
      CodeEditorMenuAction.redo => canRedo,
      CodeEditorMenuAction.cut || CodeEditorMenuAction.copy => hasSelection,
      CodeEditorMenuAction.paste => true,
      CodeEditorMenuAction.selectAll => true,
      CodeEditorMenuAction.find || CodeEditorMenuAction.replace => true,
      CodeEditorMenuAction.goToLine => true,
      CodeEditorMenuAction.toggleWordWrap => true,
      CodeEditorMenuAction.toggleHighlighting => canHighlight,
    };
  }

  /// Native menu events can already be queued when this snapshot is replaced.
  /// Re-check the capability before dispatching.
  void dispatch(CodeEditorMenuAction action) {
    if (isEnabled(action)) perform(action);
  }
}

/// Null while no code editor is open.
final StateProvider<CodeEditorMenuActions?> codeEditorMenuProvider =
    StateProvider<CodeEditorMenuActions?>((Ref ref) => null);
