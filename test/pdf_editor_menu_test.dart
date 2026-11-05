import 'package:crisp_cloud/services/pdf_editor_menu.dart';
import 'package:flutter_test/flutter_test.dart';

PdfEditorMenuActions actions({
  bool canSave = false,
  bool canSaveCopy = true,
  bool canExport = true,
  bool canClose = true,
  bool canUndo = false,
  bool canRedo = false,
  void Function(PdfEditorMenuAction action)? perform,
}) {
  return PdfEditorMenuActions(
    perform: perform ?? (_) {},
    canSave: canSave,
    canSaveCopy: canSaveCopy,
    canExport: canExport,
    canClose: canClose,
    canUndo: canUndo,
    canRedo: canRedo,
  );
}

void main() {
  group('PdfEditorMenuActions', () {
    test('reflects save and history state', () {
      final menu = actions(canSave: true, canUndo: true);
      expect(menu.isEnabled(PdfEditorMenuAction.save), isTrue);
      expect(menu.isEnabled(PdfEditorMenuAction.undo), isTrue);
      expect(menu.isEnabled(PdfEditorMenuAction.redo), isFalse);
      expect(menu.isEnabled(PdfEditorMenuAction.saveCopy), isTrue);
      expect(menu.isEnabled(PdfEditorMenuAction.exportCopy), isTrue);
      expect(menu.isEnabled(PdfEditorMenuAction.close), isTrue);
    });

    test('disables write commands while busy', () {
      final menu = actions(
        canSave: false,
        canSaveCopy: false,
        canExport: false,
        canClose: false,
      );
      expect(menu.isEnabled(PdfEditorMenuAction.save), isFalse);
      expect(menu.isEnabled(PdfEditorMenuAction.saveCopy), isFalse);
      expect(menu.isEnabled(PdfEditorMenuAction.exportCopy), isFalse);
      expect(menu.isEnabled(PdfEditorMenuAction.close), isFalse);
    });

    test('dispatch re-checks the snapshot', () {
      var calls = 0;
      final menu = actions(canSave: false, perform: (_) => calls++);
      menu.dispatch(PdfEditorMenuAction.save);
      expect(calls, 0);

      final enabled = actions(canSave: true, perform: (_) => calls++);
      enabled.dispatch(PdfEditorMenuAction.save);
      expect(calls, 1);
    });
  });
}
