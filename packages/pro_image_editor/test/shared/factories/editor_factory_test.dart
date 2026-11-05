import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/core/models/editor_callbacks/standalone_editor_callbacks.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/factories/editor_factory.dart';

void main() {
  group('EditorFactory', () {
    test('returns correct StandaloneEditorCallbacks for each EditorMode', () {
      const modes = EditorMode.values;
      for (final mode in modes) {
        final callbacks = EditorFactory.getEditor(mode);
        expect(callbacks, isA<StandaloneEditorCallbacks>());
      }
    });

    test('throws UnimplementedError for unsupported EditorMode', () {
      expect(
        () => EditorFactory.getEditor(
          EditorMode.values.firstWhere(
            (mode) => false,
            orElse: () => throw UnimplementedError(),
          ),
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
