import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Commands shared by the PDF editor and the app menu bar.
enum PdfEditorMenuAction { save, saveCopy, exportCopy, close, undo, redo }

/// A snapshot of the active PDF editor's command availability.
class PdfEditorMenuActions {
  const PdfEditorMenuActions({
    required this.perform,
    required this.canSave,
    required this.canSaveCopy,
    required this.canExport,
    required this.canClose,
    required this.canUndo,
    required this.canRedo,
  });

  final void Function(PdfEditorMenuAction action) perform;
  final bool canSave;
  final bool canSaveCopy;
  final bool canExport;
  final bool canClose;
  final bool canUndo;
  final bool canRedo;

  bool isEnabled(PdfEditorMenuAction action) {
    return switch (action) {
      PdfEditorMenuAction.save => canSave,
      PdfEditorMenuAction.saveCopy => canSaveCopy,
      PdfEditorMenuAction.exportCopy => canExport,
      PdfEditorMenuAction.close => canClose,
      PdfEditorMenuAction.undo => canUndo,
      PdfEditorMenuAction.redo => canRedo,
    };
  }

  void dispatch(PdfEditorMenuAction action) {
    if (isEnabled(action)) perform(action);
  }
}

/// Null while no PDF editor is open.
final StateProvider<PdfEditorMenuActions?> pdfEditorMenuProvider =
    StateProvider<PdfEditorMenuActions?>((Ref ref) => null);
