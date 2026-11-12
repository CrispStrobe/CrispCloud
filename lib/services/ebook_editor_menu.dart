import 'package:flutter_riverpod/flutter_riverpod.dart';

enum EbookEditorMenuAction { save, saveCopy, exportCopy, close, undo, redo }

class EbookEditorMenuActions {
  const EbookEditorMenuActions({required this.perform, required this.enabled});
  final void Function(EbookEditorMenuAction action) perform;
  final Set<EbookEditorMenuAction> enabled;
  bool isEnabled(EbookEditorMenuAction action) => enabled.contains(action);
  void dispatch(EbookEditorMenuAction action) {
    if (isEnabled(action)) perform(action);
  }
}

final ebookEditorMenuProvider = StateProvider<EbookEditorMenuActions?>(
  (ref) => null,
);
