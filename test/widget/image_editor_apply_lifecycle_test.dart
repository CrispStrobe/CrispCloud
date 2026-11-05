import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_editor_menu.dart';
import 'package:crisp_cloud/services/image_file_store.dart';
import 'package:crisp_cloud/widgets/image_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/features/crop_rotate_editor/widgets/outside_gestures/crop_rotate_gesture_detector.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/image_editor_fixture.dart';
import '../support/image_editor_test_diagnostics.dart';

class _ReadOnlyFixtureStore implements ImageFileStore {
  final _bytes = buildImageEditorFixture();

  @override
  String get displayName => 'gesture.png';
  @override
  String get documentId => 'test:gesture.png';
  @override
  String get path => '/gesture.png';
  @override
  bool get isRemote => false;

  @override
  Future<Uint8List> load() async => Uint8List.fromList(_bytes);

  @override
  Future<ImageSaveOutcome> save(Uint8List output) async =>
      throw StateError('Applying a tool must not write to the source.');
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready, {
  required String reason,
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 25)) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    final error = tester.takeException();
    if (error != null) throw error;
    if (ready()) {
      // Menu state is published after the frame that schedules the matching
      // header rebuild. Paint that rebuild before inspecting its controls.
      await tester.pump();
      return;
    }
  }
  fail('Timed out waiting for $reason.');
}

ImageEditorMenuActions _actions(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(ImageEditorDialog)),
      listen: false,
    ).read(imageEditorMenuProvider)!;

bool _cropMotionComplete(CropRotateEditorState crop) {
  final painter = crop.cropPainter;
  // Rotation controllers use Flutter's frame clock; the crop painter's fade
  // and fit loops also use wall time. Wait for both clocks' visible result.
  return painter != null &&
      painter.fadeInOpacity == 1 &&
      painter.rotationScaleFactor == crop.oldScaleFactor &&
      !crop.rotateCtrl.isAnimating &&
      !crop.scaleCtrl.isAnimating;
}

Future<GlobalKey<ProImageEditorState>> _openCrop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  final editorKey = GlobalKey<ProImageEditorState>();
  final store = _ReadOnlyFixtureStore();
  final cropCommand = find.byKey(const ValueKey('image-cropRotate'));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => Dialog.fullscreen(
                  child: ImageEditorDialog(
                    file: FileItem(name: store.displayName, isFolder: false),
                    side: PanelSide.local,
                    storeOverride: store,
                    editorKey: editorKey,
                    enableIsolateGeneration: false,
                  ),
                ),
              ),
              child: const Text('Open image'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open image'));
  await _until(
    tester,
    () =>
        cropCommand.evaluate().isNotEmpty &&
        tester.widget<TextButton>(cropCommand).onPressed != null,
    reason: 'decoded image and host commands',
  );
  await tester.tap(cropCommand);
  await _until(
    tester,
    () => editorKey.currentState!.cropRotateEditor.currentState != null,
    reason: 'embedded crop tool',
  );
  await tester.pump(const Duration(milliseconds: 400));
  await _until(
    tester,
    () => _cropMotionComplete(
      editorKey.currentState!.cropRotateEditor.currentState!,
    ),
    reason: 'crop entrance fade and fit complete',
  );
  return editorKey;
}

// The engine chooses pointer behavior from foundation's platform, not the
// Material theme. Flutter web tests default that platform to Android, so set
// the desktop variant before the engine caches its platform capabilities.
void _desktopTestWidgets(
  String description,
  WidgetTesterCallback callback, {
  bool? skip,
}) => testWidgets(
  description,
  callback,
  skip: skip,
  variant: TargetPlatformVariant.only(TargetPlatform.linux),
);

void main() {
  installImageEditorBrowserDiagnostics();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _desktopTestWidgets(
    'Apply during a crop gesture remains retryable and a real Apply locks its transition',
    (tester) async {
      final editorKey = await _openCrop(tester);
      final apply = find.byKey(const ValueKey('image-apply-tool'));
      final close = find.byKey(const ValueKey('image-close'));

      // Keep a real crop pointer down while activating the host button. An
      // accessibility activation or a second input device can do the same.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CropRotateGestureDetector)),
      );
      await gesture.moveBy(const Offset(40, 24));
      await tester.pump(const Duration(milliseconds: 30));
      tester.widget<FilledButton>(apply).onPressed!();
      await tester.pump();
      await tester.pump();

      expect(editorKey.currentState!.isSubEditorOpen, isTrue);
      expect(editorKey.currentState!.isSubEditorClosing, isFalse);
      expect(_actions(tester).busy, isFalse);
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      expect(tester.widget<IconButton>(close).onPressed, isNotNull);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(apply);
      await tester.pump();
      expect(editorKey.currentState!.isSubEditorClosing, isTrue);
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      expect(tester.widget<IconButton>(close).onPressed, isNull);

      await _until(
        tester,
        () =>
            !editorKey.currentState!.isSubEditorOpen && !_actions(tester).busy,
        reason: 'completed crop route transition',
      );
      expect(find.byType(ImageEditorDialog), findsOneWidget);
      expect(tester.widget<IconButton>(close).onPressed, isNotNull);
    },
  );

  _desktopTestWidgets(
    'a host modal blocks crop keyboard edits until it is dismissed',
    (tester) async {
      final editorKey = await _openCrop(tester);
      final crop = editorKey.currentState!.cropRotateEditor.currentState!;
      final initialRotation = crop.rotationCount;
      final overlay = showDialog<void>(
        context: tester.element(find.byType(ImageEditorDialog)),
        useRootNavigator: true,
        builder: (context) => AlertDialog(
          title: const Text('Host settings'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close overlay'),
            ),
          ],
        ),
      );
      await _until(
        tester,
        () => _actions(tester).busy,
        reason: 'host overlay takes command focus',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump(const Duration(milliseconds: 400));
      expect(crop.rotationCount, initialRotation);
      expect(crop.canUndo, isFalse);

      await tester.tap(find.text('Close overlay'));
      await overlay;
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await _until(
        tester,
        () =>
            crop.rotationCount != initialRotation &&
            crop.canUndo &&
            _cropMotionComplete(crop),
        reason: 'crop shortcut resumes on the visible route',
      );
      expect(crop.canUndo, isTrue);
      expect(find.byType(ImageEditorDialog), findsOneWidget);
    },
  );
}
