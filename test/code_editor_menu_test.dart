import 'package:crisp_cloud/services/code_editor_menu.dart';
import 'package:flutter_test/flutter_test.dart';

CodeEditorMenuActions actions({
  bool canSave = false,
  bool canUndo = false,
  bool canRedo = false,
  bool hasSelection = false,
  bool canReload = true,
  bool canHighlight = true,
  bool busy = false,
  void Function(CodeEditorMenuAction action)? perform,
}) {
  return CodeEditorMenuActions(
    perform: perform ?? (_) {},
    canSave: canSave,
    canUndo: canUndo,
    canRedo: canRedo,
    hasSelection: hasSelection,
    canReload: canReload,
    canHighlight: canHighlight,
    busy: busy,
  );
}

void main() {
  group('CodeEditorMenuActions', () {
    test('reflects dirty, history and selection state', () {
      final menu = actions(canSave: true, canUndo: true, hasSelection: true);

      expect(menu.isEnabled(CodeEditorMenuAction.save), isTrue);
      expect(menu.isEnabled(CodeEditorMenuAction.undo), isTrue);
      expect(menu.isEnabled(CodeEditorMenuAction.cut), isTrue);
      expect(menu.isEnabled(CodeEditorMenuAction.copy), isTrue);
      expect(menu.isEnabled(CodeEditorMenuAction.redo), isFalse);
      expect(menu.isEnabled(CodeEditorMenuAction.paste), isTrue);
      expect(menu.isEnabled(CodeEditorMenuAction.selectAll), isTrue);
    });

    test('disables editing while the document is loading', () {
      final menu = actions(canSave: true, canUndo: true, busy: true);

      expect(menu.isEnabled(CodeEditorMenuAction.save), isFalse);
      expect(menu.isEnabled(CodeEditorMenuAction.undo), isFalse);
      expect(menu.isEnabled(CodeEditorMenuAction.find), isFalse);
      // The user can still leave a slow or broken load.
      expect(menu.isEnabled(CodeEditorMenuAction.close), isTrue);
    });

    test('hides highlighting when the file has no language', () {
      final menu = actions(canHighlight: false);
      expect(menu.isEnabled(CodeEditorMenuAction.toggleHighlighting), isFalse);
    });

    test('dispatch re-checks the snapshot before calling the editor', () {
      var calls = 0;
      final menu = actions(canSave: false, perform: (_) => calls++);

      menu.dispatch(CodeEditorMenuAction.save);
      expect(calls, 0);

      final enabled = actions(canSave: true, perform: (_) => calls++);
      enabled.dispatch(CodeEditorMenuAction.save);
      expect(calls, 1);
    });
  });
}
