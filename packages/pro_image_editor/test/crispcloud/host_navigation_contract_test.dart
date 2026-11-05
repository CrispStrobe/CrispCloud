import 'dart:async';

import 'package:flutter/gestures.dart' as gestures;
import 'package:flutter/material.dart' as host;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as engine;
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/widgets/layer/services/layer_widget_context_menu.dart';

import '../mock/mock_image.dart';

void main() {
  const configs = ProImageEditorConfigs(
    mainEditor: MainEditorConfigs(
      hostOwnsNavigation: true,
      enableSubEditorPage: true,
    ),
    progressIndicatorConfigs: ProgressIndicatorConfigs(
      widgets: ProgressIndicatorWidgets(
        circularProgressIndicator: host.SizedBox.shrink(),
      ),
    ),
    imageGeneration: ImageGenerationConfigs(
      enableIsolateGeneration: false,
      enableBackgroundGeneration: false,
    ),
  );

  Future<ProImageEditorState> pushHostOwnedEditor(
    WidgetTester tester, {
    required void Function() onHostPop,
    required void Function() onEnginePop,
    required void Function(EditorMode) onClose,
    required void Function() onWarning,
  }) async {
    final key = host.GlobalKey<ProImageEditorState>();
    await tester.pumpWidget(
      engine.MaterialApp(
        home: host.Builder(
          builder: (context) => engine.Scaffold(
            body: engine.TextButton(
              onPressed: () => host.Navigator.of(context).push<void>(
                engine.MaterialPageRoute(
                  builder: (_) => host.PopScope<void>(
                    canPop: false,
                    onPopInvokedWithResult: (_, _) => onHostPop(),
                    child: ProImageEditor.memory(
                      mockMemoryImage,
                      key: key,
                      configs: configs.copyWith(
                        mainEditor: configs.mainEditor.copyWith(
                          widgets: MainEditorWidgets(
                            closeWarningDialog: (_) async {
                              onWarning();
                              return false;
                            },
                          ),
                        ),
                      ),
                      callbacks: ProImageEditorCallbacks(
                        onCloseEditor: onClose,
                        mainEditorCallbacks: MainEditorCallbacks(
                          onPopInvoked: (_, _) => onEnginePop(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const host.Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final editor = key.currentState!;
    await tester.runAsync(editor.decodeImage);
    await tester.pumpAndSettle();
    editor.addLayer(TextLayer(text: 'Unsaved edit'));
    await tester.pumpAndSettle();
    expect(editor.canUndo, isTrue);
    return editor;
  }

  testWidgets('host alone handles back navigation for a dirty editor',
      (tester) async {
    var hostPops = 0;
    var enginePops = 0;
    var warnings = 0;
    final closeCalls = <EditorMode>[];
    final editor = await pushHostOwnedEditor(
      tester,
      onHostPop: () => hostPops++,
      onEnginePop: () => enginePops++,
      onClose: closeCalls.add,
      onWarning: () => warnings++,
    );

    await host.Navigator.of(editor.context).maybePop();
    await tester.pumpAndSettle();

    expect(hostPops, 1);
    expect(enginePops, 0);
    expect(warnings, 0);
    expect(closeCalls, isEmpty);
    expect(editor.mounted, isTrue);
    expect(find.byType(ProImageEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close APIs delegate to the host without their own warning',
      (tester) async {
    var hostPops = 0;
    var warnings = 0;
    final closeCalls = <EditorMode>[];
    final editor = await pushHostOwnedEditor(
      tester,
      onHostPop: () => hostPops++,
      onEnginePop: () => fail('Engine registered its own pop handler'),
      onClose: closeCalls.add,
      onWarning: () => warnings++,
    );

    editor.closeEditor();
    editor.closeWarning();
    await tester.pumpAndSettle();

    expect(closeCalls, [EditorMode.main, EditorMode.main]);
    expect(warnings, 0);
    expect(hostPops, 0);
    expect(editor.mounted, isTrue);
    expect(tester.takeException(), isNull);
  });

  Future<host.BuildContext> pumpHostContext(WidgetTester tester) async {
    late host.BuildContext hostContext;
    // Intentionally no material_ui localization delegates: popup routes
    // belong to CrispCloud's Flutter MaterialApp, outside the engine scope.
    await tester.pumpWidget(
      host.MaterialApp(
        home: host.Builder(
          builder: (context) {
            hostContext = context;
            return const host.Scaffold(body: host.Text('Host'));
          },
        ),
      ),
    );
    return hostContext;
  }

  LayerWidgetContextMenu makeMenu({
    required LayerContextMenuBuilder builder,
    required void Function(bool) onToggle,
    void Function()? onEdit,
    void Function()? onRemove,
  }) => LayerWidgetContextMenu(
    onEditTap: onEdit,
    onRemoveTap: onRemove,
    onContextMenuToggled: onToggle,
    i18nLayerInteraction: const I18nLayerInteraction(),
    layerInteractionIcons: const LayerInteractionIcons(),
    contextMenuBuilder: builder,
  );

  Future<void> openMenu(
    LayerWidgetContextMenu menu,
    host.BuildContext context, {
    bool canEdit = true,
    bool canRemove = true,
  }) => menu.open(
    context: context,
    details: gestures.TapUpDetails(
      globalPosition: const host.Offset(20, 30),
      kind: gestures.PointerDeviceKind.mouse,
    ),
    enableEditButton: canEdit,
    enableRemoveButton: canRemove,
  );

  testWidgets('host menu works outside the engine localization scope',
      (tester) async {
    final context = await pumpHostContext(tester);
    final toggles = <bool>[];
    var edits = 0;
    var removals = 0;
    final menu = makeMenu(
      onToggle: toggles.add,
      onEdit: () => edits++,
      onRemove: () => removals++,
      builder: (context, position, {required canEdit, required canRemove}) {
        expect(position, const host.Offset(20, 30));
        expect(canEdit, isTrue);
        expect(canRemove, isFalse);
        return host.showMenu<LayerContextMenuAction>(
          context: context,
          position: host.RelativeRect.fromLTRB(
            position.dx, position.dy, position.dx + 1, position.dy + 1,
          ),
          items: const [
            host.PopupMenuItem(
              value: LayerContextMenuAction.edit,
              child: host.Text('Host edit'),
            ),
          ],
        );
      },
    );

    final opened = openMenu(menu, context, canRemove: false);
    await tester.pumpAndSettle();
    expect(toggles, [true]);
    await tester.tap(find.text('Host edit'));
    await tester.pumpAndSettle();
    await opened;

    expect(edits, 1);
    expect(removals, 0);
    expect(toggles, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host menu rejects overlapping opens and disabled actions',
      (tester) async {
    final context = await pumpHostContext(tester);
    final completion = Completer<LayerContextMenuAction?>();
    final toggles = <bool>[];
    var calls = 0;
    var edits = 0;
    final menu = makeMenu(
      onToggle: toggles.add,
      onEdit: () => edits++,
      builder: (_, _, {required canEdit, required canRemove}) {
        calls++;
        return completion.future;
      },
    );

    final opened = openMenu(menu, context, canEdit: false);
    await openMenu(menu, context);
    expect(calls, 1);
    expect(toggles, [true]);
    completion.complete(LayerContextMenuAction.edit);
    await opened;

    expect(edits, 0);
    expect(toggles, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host menu clears its open state after a builder failure',
      (tester) async {
    final context = await pumpHostContext(tester);
    final toggles = <bool>[];
    var calls = 0;
    var removals = 0;
    final menu = makeMenu(
      onToggle: toggles.add,
      onRemove: () => removals++,
      builder: (_, _, {required canEdit, required canRemove}) async {
        calls++;
        if (calls == 1) throw StateError('Host menu failed');
        return LayerContextMenuAction.remove;
      },
    );

    await expectLater(openMenu(menu, context), throwsStateError);
    await openMenu(menu, context);

    expect(calls, 2);
    expect(removals, 1);
    expect(toggles, [true, false, true, false]);
    expect(tester.takeException(), isNull);
  });
}
