// ignore_for_file: invalid_use_of_protected_member
import 'dart:ui' show PointerDeviceKind;

import 'package:pro_image_editor/features/crop_rotate_editor/widgets/outside_gestures/crop_rotate_gesture_detector.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/image_file_store.dart';
import 'package:crisp_cloud/widgets/image_editor_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements ImageFileStore {
  _Store() {
    final canvas = image.Image(width: 320, height: 240);
    image.fill(canvas, color: image.ColorRgb8(255, 255, 255));
    bytes = Uint8List.fromList(image.encodePng(canvas));
  }
  late Uint8List bytes;
  int writes = 0;
  @override
  String get path => '/text-test.png';
  @override
  String get documentId => 'test:image-text';
  @override
  String get displayName => 'text-test.png';
  @override
  bool get isRemote => false;
  @override
  Future<Uint8List> load() async => Uint8List.fromList(bytes);
  @override
  Future<ImageSaveOutcome> save(Uint8List next) async {
    writes++;
    bytes = Uint8List.fromList(next);
    return ImageSaveOutcome.savedOriginal;
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 50)) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    final error = tester.takeException();
    if (error != null) throw error;
    if (ready()) {
      await tester.pump();
      return;
    }
  }
  fail('Image text lifecycle timed out');
}

void registerImageTextLifecycleTests({bool live = false}) {
  testWidgets(
    'actual image Text tool opens, cancels, reopens, applies and saves',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = _Store();
      final before = Uint8List.fromList(store.bytes);
      final key = GlobalKey<ProImageEditorState>();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImageEditorDialog(
              file: FileItem(
                name: store.displayName,
                path: store.path,
                isFolder: false,
              ),
              side: PanelSide.local,
              storeOverride: store,
              editorKey: key,
              enableIsolateGeneration: false,
            ),
          ),
        ),
      );
      final text = find.byKey(const ValueKey('image-text'));
      await _until(
        tester,
        () =>
            text.evaluate().isNotEmpty &&
            tester.widget<TextButton>(text).onPressed != null,
      );
      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(text);
        await tester.tap(text);
        await _until(
          tester,
          () => key.currentState!.textEditor.currentState != null,
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(ImageEditorDialog), findsOneWidget);
        final input = find
            .descendant(
              of: find.byType(TextEditor),
              matching: find.byType(EditableText),
            )
            .first;
        await tester.enterText(input, 'Text cycle $i');
        await tester.pump();
        final command = find.byKey(
          ValueKey(i < 2 ? 'image-cancel-tool' : 'image-apply-tool'),
        );
        await tester.ensureVisible(command);
        await tester.tap(command);
        await _until(tester, () => !key.currentState!.isSubEditorOpen);
        expect(store.writes, 0);
        expect(store.bytes, orderedEquals(before));
      }
      expect(
        key.currentState!.activeLayers.whereType<TextLayer>().single.text,
        'Text cycle 2',
      );
      await tester.tap(find.byKey(const ValueKey('image-save')));
      await _until(tester, () => store.writes == 1);
      expect(store.bytes, isNot(orderedEquals(before)));
      expect(image.decodePng(store.bytes)!.width, 320);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: live
        ? const TargetPlatformVariant({TargetPlatform.macOS})
        : TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'failed async image Text launch remains usable and can retry',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = _Store();
      final key = GlobalKey<ProImageEditorState>();
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImageEditorDialog(
              file: FileItem(
                name: store.displayName,
                path: store.path,
                isFolder: false,
              ),
              side: PanelSide.local,
              storeOverride: store,
              editorKey: key,
              enableIsolateGeneration: false,
              textToolOpenerOverride: (editor) async {
                if (++attempts == 1) {
                  await Future<void>.delayed(Duration.zero);
                  throw StateError('injected text-launch failure');
                }
                await editor.openTextEditor();
              },
            ),
          ),
        ),
      );
      final text = find.byKey(const ValueKey('image-text'));
      await _until(
        tester,
        () =>
            text.evaluate().isNotEmpty &&
            tester.widget<TextButton>(text).onPressed != null,
      );
      await tester.ensureVisible(text);
      await tester.tap(text);
      await _until(
        tester,
        () => find
            .textContaining('injected text-launch failure')
            .evaluate()
            .isNotEmpty,
      );
      expect(store.writes, 0);
      await tester.tap(text);
      await _until(
        tester,
        () => key.currentState!.textEditor.currentState != null,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('image-cancel-tool')));
      await _until(tester, () => !key.currentState!.isSubEditorOpen);
      expect(attempts, 2);
      expect(store.writes, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: live
        ? const TargetPlatformVariant({TargetPlatform.macOS})
        : TargetPlatformVariant.desktop(),
  );
  testWidgets(
    'visible crop corner target resizes both axes without selecting an edge',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = _Store();
      final key = GlobalKey<ProImageEditorState>();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImageEditorDialog(
              file: FileItem(
                name: store.displayName,
                path: store.path,
                isFolder: false,
              ),
              side: PanelSide.local,
              storeOverride: store,
              editorKey: key,
              enableIsolateGeneration: false,
            ),
          ),
        ),
      );
      final cropButton = find.byKey(const ValueKey('image-cropRotate'));
      await _until(
        tester,
        () =>
            cropButton.evaluate().isNotEmpty &&
            tester.widget<TextButton>(cropButton).onPressed != null,
      );
      await tester.ensureVisible(cropButton);
      await tester.tap(cropButton);
      await _until(
        tester,
        () => key.currentState!.cropRotateEditor.currentState != null,
      );
      await tester.pump(const Duration(milliseconds: 500));
      final crop = key.currentState!.cropRotateEditor.currentState!;
      final before = crop.cropRect;
      final box = tester.renderObject<RenderBox>(
        find.byType(CropRotateGestureDetector),
      );
      final center = box.size.center(Offset.zero);
      final target = before.bottomRight - const Offset(12, 12);
      final local =
          center + (target - center) / crop.userScaleFactor - crop.translate;
      final point = box.localToGlobal(local);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: point);
      await gesture.moveTo(point);
      await tester.pump();
      await gesture.down(point);
      await gesture.moveBy(const Offset(-48, -19));
      await tester.pump();
      expect(crop.cropRect.width, lessThan(before.width));
      expect(crop.cropRect.height, lessThan(before.height));
      await gesture.up();
      await gesture.removePointer();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('image-cancel-tool')));
      await _until(tester, () => !key.currentState!.isSubEditorOpen);
      expect(store.writes, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: live
        ? const TargetPlatformVariant({TargetPlatform.macOS})
        : TargetPlatformVariant.desktop(),
  );
}
