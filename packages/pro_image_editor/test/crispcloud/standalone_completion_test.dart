import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/widgets/overlays/loading_dialog/loading_dialog.dart';

import '../mock/mock_image.dart';

void main() {
  testWidgets('awaiting tool completion propagates write failure and unlocks retry', (tester) async {
    final key = GlobalKey<BlurEditorState>();
    var failWrite = true;
    var writes = 0;
    var doneCallbacks = 0;
    var closeCallbacks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BlurEditor.memory(
          mockMemoryImage,
          key: key,
          initConfigs: BlurEditorInitConfigs(
            theme: ThemeData(),
            convertToUint8List: true,
            configs: const ProImageEditorConfigs(
              imageGeneration: ImageGenerationConfigs(
                outputFormat: OutputFormat.png,
                enableBackgroundGeneration: false,
                enableIsolateGeneration: false,
              ),
            ),
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (bytes) async {
                writes++;
                expect(bytes, orderedEquals(mockMemoryImage));
                if (failWrite) throw StateError('Storage rejected the image');
              },
              onCloseEditor: (_) => closeCallbacks++,
              blurEditorCallbacks: BlurEditorCallbacks(
                onDone: () => doneCallbacks++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = key.currentState!;
    await tester.runAsync(() async {
      await expectLater(state.done(), throwsStateError);
    });
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(doneCallbacks, 0);
    expect(closeCallbacks, 0);
    expect(state.isGenerationActive, isFalse);
    expect(LoadingDialog.instance.hasActiveOverlay, isFalse);
    expect(state.mounted, isTrue);

    failWrite = false;
    await tester.runAsync(state.done);
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(doneCallbacks, 1);
    expect(closeCallbacks, 1);
    expect(state.isGenerationActive, isFalse);
    expect(LoadingDialog.instance.hasActiveOverlay, isFalse);
    expect(tester.takeException(), isNull);
  });
}
