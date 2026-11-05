import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../mock/mock_image.dart';

void main() {
  const configs = ProImageEditorConfigs(
    mainEditor: MainEditorConfigs(enableSubEditorPage: true),
    progressIndicatorConfigs: ProgressIndicatorConfigs(
      widgets: ProgressIndicatorWidgets(
        circularProgressIndicator: SizedBox.shrink(),
      ),
    ),
    imageGeneration: ImageGenerationConfigs(
      outputFormat: OutputFormat.png,
      enableIsolateGeneration: false,
      enableBackgroundGeneration: false,
    ),
  );

  Future<ProImageEditorState> pushEditor(
    WidgetTester tester, {
    void Function(EditorMode)? onCloseEditor,
    void Function()? onBlurDone,
  }) async {
    final key = GlobalKey<ProImageEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ProImageEditor.memory(
                    mockMemoryImage,
                    key: key,
                    configs: configs,
                    callbacks: ProImageEditorCallbacks(
                      onCloseEditor: onCloseEditor,
                      blurEditorCallbacks: BlurEditorCallbacks(onDone: onBlurDone),
                    ),
                  ),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    final editor = key.currentState!;
    await tester.runAsync(editor.decodeImage);
    await tester.pumpAndSettle();
    return editor;
  }

  void expectHostOpen(ProImageEditorState editor) {
    expect(editor.mounted, isTrue);
    expect(find.byType(ProImageEditor), findsOneWidget);
    expect(editor.isSubEditorOpen, isFalse);
  }

  testWidgets('Escape dismisses a nested tool without popping its host', (
    tester,
  ) async {
    final editor = await pushEditor(tester);
    editor.openBlurEditor();
    await tester.pumpAndSettle();
    expect(find.byType(BlurEditor), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(BlurEditor), findsNothing);
    expectHostOpen(editor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested Cancel does not call the host close callback', (
    tester,
  ) async {
    var hostCloseCalls = 0;
    final editor = await pushEditor(
      tester,
      onCloseEditor: (_) => hostCloseCalls++,
    );
    editor.openBlurEditor();
    await tester.pumpAndSettle();

    editor.blurEditor.currentState!.setBlurFactor(5);
    editor.blurEditor.currentState!.close();
    await tester.pumpAndSettle();

    expect(hostCloseCalls, 0);
    expect(editor.stateManager.activeBlur, 0);
    expect(editor.canUndo, isFalse);
    expectHostOpen(editor);
  });

  testWidgets('host can cancel blur and repeated close leaves host open', (
    tester,
  ) async {
    final editor = await pushEditor(tester);
    editor.openBlurEditor();
    await tester.pumpAndSettle();

    editor.closeSubEditor();
    editor.closeSubEditor();
    await tester.pumpAndSettle();
    editor.closeSubEditor();

    expectHostOpen(editor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capturing a nested editor closes only the pending tool', (
    tester,
  ) async {
    final editor = await pushEditor(tester);
    editor.openBlurEditor();
    await tester.pumpAndSettle();
    editor.blurEditor.currentState!.setBlurFactor(5);

    final capture = editor.captureEditorImage();
    await tester.pumpAndSettle();
    final bytes = await tester.runAsync(() => capture);

    expect(bytes, orderedEquals(mockMemoryImage));
    expect(editor.stateManager.activeBlur, 0);
    expectHostOpen(editor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capturing layers also preserves the host route', (tester) async {
    final editor = await pushEditor(tester);
    editor.openBlurEditor();
    await tester.pumpAndSettle();

    final capture = editor.captureAllLayersWithMeta();
    await tester.pumpAndSettle();
    // Layer capture intentionally waits for a frame after the route closes.
    await tester.pump();
    final layers = await capture;

    expect(layers, isEmpty);
    expectHostOpen(editor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated embedded Apply completes only once and preserves host', (tester) async {
    var doneCalls = 0;
    final editor = await pushEditor(tester, onBlurDone: () => doneCalls++);
    editor.openBlurEditor();
    await tester.pumpAndSettle();
    final blur = editor.blurEditor.currentState!..setBlurFactor(5);
    await Future.wait([blur.done(), blur.done()]);
    await tester.pumpAndSettle();
    expectHostOpen(editor);
    expect(doneCalls, 1);
    expect(editor.stateManager.historyPointer, 1);
    expect(editor.stateManager.activeBlur, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applying a nested tool updates host undo and redo history', (
    tester,
  ) async {
    final editor = await pushEditor(tester);
    editor.openBlurEditor();
    await tester.pumpAndSettle();
    editor.blurEditor.currentState!
      ..setBlurFactor(5)
      ..done();
    await tester.pumpAndSettle();

    expectHostOpen(editor);
    expect(editor.stateManager.activeBlur, 5);
    expect(editor.canUndo, isTrue);
    editor.undoAction();
    await tester.pumpAndSettle();
    expect(editor.stateManager.activeBlur, 0);
    expect(editor.canRedo, isTrue);
    editor.redoAction();
    await tester.pumpAndSettle();
    expect(editor.stateManager.activeBlur, 5);
  });
}
