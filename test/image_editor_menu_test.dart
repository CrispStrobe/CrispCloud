import 'package:crisp_cloud/services/image_editor_menu.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('save and history commands reflect the editor state', () {
    final calls = <ImageEditorAction>[];
    final editor = ImageEditorMenuActions(
      perform: calls.add,
      canSave: true,
      canUndo: true,
      canRedo: false,
    );

    editor.dispatch(ImageEditorAction.save);
    editor.dispatch(ImageEditorAction.undo);
    editor.dispatch(ImageEditorAction.redo);
    editor.dispatch(ImageEditorAction.cropRotate);

    expect(calls, <ImageEditorAction>[
      ImageEditorAction.save,
      ImageEditorAction.undo,
      ImageEditorAction.cropRotate,
    ]);
    expect(editor.isEnabled(ImageEditorAction.close), isTrue);
  });

  test('a clean image cannot be saved again without an edit', () {
    final calls = <ImageEditorAction>[];
    final editor = ImageEditorMenuActions(
      perform: calls.add,
      canSave: false,
      canUndo: false,
      canRedo: true,
    );

    editor.dispatch(ImageEditorAction.save);
    editor.dispatch(ImageEditorAction.undo);
    editor.dispatch(ImageEditorAction.redo);

    expect(calls, <ImageEditorAction>[ImageEditorAction.redo]);
  });

  test('saving blocks every native command, including close', () {
    final calls = <ImageEditorAction>[];
    final editor = ImageEditorMenuActions(
      perform: calls.add,
      canSave: true,
      canUndo: true,
      canRedo: true,
      busy: true,
    );

    for (final action in ImageEditorAction.values) {
      expect(editor.isEnabled(action), isFalse, reason: action.name);
      editor.dispatch(action);
    }
    expect(calls, isEmpty);
  });

  test('a tool subeditor blocks main commands but can be closed safely', () {
    final calls = <ImageEditorAction>[];
    final editor = ImageEditorMenuActions(
      perform: calls.add,
      canSave: true,
      canUndo: true,
      canRedo: true,
      canEdit: false,
    );

    for (final action in ImageEditorAction.values) {
      expect(
        editor.isEnabled(action),
        action == ImageEditorAction.close,
        reason: action.name,
      );
      editor.dispatch(action);
    }
    expect(calls, <ImageEditorAction>[ImageEditorAction.close]);
  });

  test('each provider container owns its active image editor', () {
    final first = ProviderContainer();
    final second = ProviderContainer();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final editor = ImageEditorMenuActions(
      perform: (_) {},
      canSave: false,
      canUndo: false,
      canRedo: false,
    );

    expect(first.read(imageEditorMenuProvider), isNull);
    first.read(imageEditorMenuProvider.notifier).state = editor;
    expect(first.read(imageEditorMenuProvider), same(editor));
    expect(second.read(imageEditorMenuProvider), isNull);
    first.read(imageEditorMenuProvider.notifier).state = null;
    expect(first.read(imageEditorMenuProvider), isNull);
  });
}
