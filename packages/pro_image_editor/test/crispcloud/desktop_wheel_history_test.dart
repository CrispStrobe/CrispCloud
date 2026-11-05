import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../mock/mock_image.dart';

void main() {
  const configs = ProImageEditorConfigs(
    mainEditor: MainEditorConfigs(
      enableKeyboardShortcuts: false,
      canZoomWhenLayerSelected: false,
    ),
    progressIndicatorConfigs: ProgressIndicatorConfigs(
      widgets: ProgressIndicatorWidgets(
        circularProgressIndicator: SizedBox.shrink(),
      ),
    ),
    imageGeneration: ImageGenerationConfigs(
      enableIsolateGeneration: false,
      enableBackgroundGeneration: false,
    ),
    helperLines: HelperLineConfigs(showRotateLine: false),
  );

  Future<(ProImageEditorState, String)> pumpSelectedLayer(
    WidgetTester tester, {
    void Function()? onHistoryChange,
    bool enableWheelScaling = false,
  }) async {
    final key = GlobalKey<ProImageEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ProImageEditor.memory(
          mockMemoryImage,
          key: key,
          configs: configs.copyWith(
            mainEditor: configs.mainEditor.copyWith(
              canZoomWhenLayerSelected: enableWheelScaling,
            ),
          ),
          callbacks: ProImageEditorCallbacks(
            mainEditorCallbacks: MainEditorCallbacks(
              onStateHistoryChange: (_, _) => onHistoryChange?.call(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = key.currentState!;
    await tester.runAsync(state.decodeImage);
    await tester.pumpAndSettle();
    final layer = TextLayer(text: 'Wheel history', scale: 2);
    state.addLayer(
      layer,
      autoCorrectZoomOffset: false,
      autoCorrectZoomScale: false,
    );
    state.layerInteractionManager
      ..clearSelectedLayers()
      ..addSelectedLayer(layer.id);
    await tester.pumpAndSettle();
    return (state, layer.id);
  }

  Layer liveLayer(ProImageEditorState state, String id) =>
      state.activeLayers.singleWhere((layer) => layer.id == id);

  Future<void> scroll(
    WidgetTester tester, {
    required Offset delta,
    bool shift = false,
  }) async {
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final center = tester.getCenter(find.byType(ProImageEditor));
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.sendEventToBinding(mouse.scroll(delta));
      await tester.pumpAndSettle();
    } finally {
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
  }

  testWidgets('wheel rotation creates a revision without mutating saved history',
      (tester) async {
    var historyChanges = 0;
    final (state, id) = await pumpSelectedLayer(
      tester,
      onHistoryChange: () => historyChanges++,
    );
    final before = state.stateHistory[state.stateManager.historyPointer];
    final beforeLayer = liveLayer(state, id);
    final beforeRotation = beforeLayer.rotation;
    final beforeCount = state.stateHistory.length;
    final callbackCount = historyChanges;

    await scroll(tester, delta: const Offset(0, -20), shift: true);

    expect(state.stateHistory, hasLength(beforeCount + 1));
    expect(historyChanges, callbackCount + 1);
    expect(
      identical(state.stateHistory[state.stateManager.historyPointer], before),
      isFalse,
    );
    expect(identical(liveLayer(state, id), beforeLayer), isFalse);
    expect(beforeLayer.rotation, beforeRotation);
    expect(liveLayer(state, id).rotation, closeTo(beforeRotation + 0.087266, 1e-9));

    state.undoAction();
    await tester.pumpAndSettle();
    expect(
      identical(state.stateHistory[state.stateManager.historyPointer], before),
      isTrue,
    );
    expect(liveLayer(state, id).rotation, beforeRotation);
    state.redoAction();
    await tester.pumpAndSettle();
    expect(liveLayer(state, id).rotation, closeTo(beforeRotation + 0.087266, 1e-9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel edit after undo creates a distinct history branch',
      (tester) async {
    final (state, id) = await pumpSelectedLayer(tester);
    await scroll(tester, delta: const Offset(0, -20), shift: true);
    final oldBranch = state.stateHistory[state.stateManager.historyPointer];
    final branchPointer = state.stateManager.historyPointer;
    state.undoAction();
    await tester.pumpAndSettle();
    state.layerInteractionManager.addSelectedLayer(id);
    await tester.pumpAndSettle();

    await scroll(tester, delta: const Offset(0, 20), shift: true);

    expect(state.stateManager.historyPointer, branchPointer);
    expect(
      identical(state.stateHistory[state.stateManager.historyPointer], oldBranch),
      isFalse,
    );
    expect(oldBranch.layers.single.rotation, closeTo(0.087266, 1e-9));
    expect(liveLayer(state, id).rotation, closeTo(-0.087266, 1e-9));
    expect(state.canRedo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel scaling can undo to the exact previous layer scale',
      (tester) async {
    final (state, id) = await pumpSelectedLayer(
      tester,
      enableWheelScaling: true,
    );
    final beforeLayer = liveLayer(state, id);
    final beforeScale = beforeLayer.scale;
    final beforeCount = state.stateHistory.length;

    await scroll(tester, delta: const Offset(0, -20));

    expect(state.stateHistory, hasLength(beforeCount + 1));
    expect(beforeLayer.scale, beforeScale);
    expect(liveLayer(state, id).scale, closeTo(beforeScale * 1.1, 1e-9));
    state.undoAction();
    await tester.pumpAndSettle();
    expect(liveLayer(state, id).scale, beforeScale);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sideways and inactive zoom wheels create no history entries',
      (tester) async {
    var historyChanges = 0;
    final (state, id) = await pumpSelectedLayer(
      tester,
      onHistoryChange: () => historyChanges++,
    );
    final before = state.stateHistory[state.stateManager.historyPointer];
    final placement = liveLayer(state, id).restPlacement;
    final beforeCount = state.stateHistory.length;
    final callbackCount = historyChanges;

    await scroll(tester, delta: const Offset(20, 0), shift: true);
    await scroll(tester, delta: const Offset(0, -20));

    expect(state.stateHistory, hasLength(beforeCount));
    expect(historyChanges, callbackCount);
    expect(
      identical(state.stateHistory[state.stateManager.historyPointer], before),
      isTrue,
    );
    expect(liveLayer(state, id).restPlacement, placement);
    expect(tester.takeException(), isNull);
  });
}
