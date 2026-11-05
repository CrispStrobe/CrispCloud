import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_editor_menu.dart';
import 'package:crisp_cloud/services/image_file_store.dart';
import 'package:crisp_cloud/widgets/image_editor_dialog.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/image_editor_fixture.dart';
import '../support/image_editor_test_diagnostics.dart';

/// Only storage is substituted: decode, editing, capture, encoding, and host
/// command handling all use the shipped editor and Flutter rendering engine.
class _MemoryImageStore implements ImageFileStore {
  _MemoryImageStore({this.format = ImageFileFormat.png, Uint8List? input})
    : bytes = input ?? buildImageEditorFixture(format: format);

  final ImageFileFormat format;
  Uint8List bytes;
  final writes = <Uint8List>[];
  Future<ImageSaveOutcome> Function(Uint8List)? writer;
  int loads = 0;

  @override
  String get displayName =>
      format == ImageFileFormat.png ? 'sample.png' : 'sample.jpg';
  @override
  String get documentId => 'test:$displayName';
  @override
  String get path => '/$displayName';
  @override
  bool get isRemote => false;

  @override
  Future<Uint8List> load() async {
    loads++;
    return Uint8List.fromList(bytes);
  }

  @override
  Future<ImageSaveOutcome> save(Uint8List output) async {
    final snapshot = Uint8List.fromList(output);
    writes.add(snapshot);
    final outcome = writer == null
        ? ImageSaveOutcome.savedOriginal
        : await writer!(snapshot);
    if (outcome == ImageSaveOutcome.savedOriginal) bytes = snapshot;
    return outcome;
  }
}

class _RouteObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

Finder get _save => find.byKey(const ValueKey('image-save'));
Finder get _close => find.byKey(const ValueKey('image-close'));
Finder get _apply => find.byKey(const ValueKey('image-apply-tool'));
Finder get _cancelTool => find.byKey(const ValueKey('image-cancel-tool'));
Finder get _unsaved => find.byKey(const ValueKey('image-unsaved-dialog'));
Finder _command(ImageEditorAction action) =>
    find.byKey(ValueKey('image-${action.name}'));

bool _saveEnabled(WidgetTester tester) =>
    _save.evaluate().isNotEmpty &&
    tester.widget<FilledButton>(_save).onPressed != null;

/// Engine codecs, toImage(), and the browser worker complete outside the fake
/// widget-test clock. Give them real event turns while advancing bounded frames;
/// pumpAndSettle alone either returns before decode or waits on the spinner.
Future<void> _until(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    final exception = tester.takeException();
    if (exception != null) throw exception;
    if (condition()) {
      await tester.pump();
      return;
    }
  }
  fail('Timed out waiting for $reason.');
}

class _Harness {
  _Harness(this.tester, this.store);
  final WidgetTester tester;
  final _MemoryImageStore store;
  final key = GlobalKey<ProImageEditorState>();
  final observer = _RouteObserver();

  ProImageEditorState get editor => key.currentState!;
  ImageEditorMenuActions get actions => ProviderScope.containerOf(
    tester.element(find.byType(ImageEditorDialog)),
    listen: false,
  ).read(imageEditorMenuProvider)!;

  Future<void> open({bool enableIsolateGeneration = false}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          navigatorObservers: [observer],
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
                      editorKey: key,
                      enableIsolateGeneration: enableIsolateGeneration,
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
    await reopen();
  }

  Future<void> reopen() async {
    await tester.tap(find.text('Open image'));
    await _until(
      tester,
      () =>
          key.currentState != null &&
          _command(ImageEditorAction.cropRotate).evaluate().isNotEmpty &&
          tester
                  .widget<TextButton>(_command(ImageEditorAction.cropRotate))
                  .onPressed !=
              null,
      reason: 'image decode and host command availability',
    );
  }

  Future<void> addText(String value) async {
    editor.addLayer(
      TextLayer(
        text: value,
        color: Colors.red,
        background: Colors.transparent,
        colorMode: LayerBackgroundMode.onlyColor,
        fontScale: 3,
      ),
      blockSelectLayer: true,
      autoCorrectZoomOffset: false,
      autoCorrectZoomScale: false,
    );
    await _until(
      tester,
      () => _saveEnabled(tester),
      reason: 'text layer history',
    );
  }

  Future<void> rotate() async {
    await tester.tap(_command(ImageEditorAction.cropRotate));
    await _until(
      tester,
      () => editor.cropRotateEditor.currentState != null,
      reason: 'embedded crop editor',
    );
    // Finish the route entrance before rotating its crop geometry.
    await tester.pump(const Duration(milliseconds: 400));
    final crop = editor.cropRotateEditor.currentState!;
    crop.rotate();
    await _until(
      tester,
      () => crop.canUndo && !crop.rotateCtrl.isAnimating,
      reason: 'quarter-turn animation and crop history',
    );
    expect(
      _saveEnabled(tester),
      isFalse,
      reason: 'Pending tool changes must be applied first.',
    );
    await tester.ensureVisible(_apply);
    await tester.tap(_apply);
    await _until(
      tester,
      () => !editor.isSubEditorOpen && _saveEnabled(tester),
      reason: 'crop apply without closing the host',
    );
  }

  Future<void> save() async {
    final expectedWrites = store.writes.length + 1;
    await tester.tap(_save);
    await _until(
      tester,
      () =>
          store.writes.length == expectedWrites &&
          !actions.busy &&
          !_saveEnabled(tester),
      reason: 'real image capture and successful source save',
    );
  }

  Future<void> closeCleanly() async {
    await tester.tap(_close);
    await _until(
      tester,
      () => key.currentState == null,
      reason: 'host close transition',
    );
    expect(find.byType(ImageEditorDialog), findsNothing);
  }
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
    'initial clean state and undo branches use real editor history',
    (tester) async {
      final harness = _Harness(tester, _MemoryImageStore());
      await harness.open();
      expect(_saveEnabled(tester), isFalse);
      expect(harness.actions.isEnabled(ImageEditorAction.save), isFalse);
      expect(harness.actions.isEnabled(ImageEditorAction.undo), isFalse);

      await harness.addText('First');
      expect(harness.actions.isEnabled(ImageEditorAction.undo), isTrue);
      await tester.tap(_command(ImageEditorAction.undo));
      await _until(
        tester,
        () => !_saveEnabled(tester),
        reason: 'undo to opened image',
      );
      expect(harness.editor.activeLayers, isEmpty);
      expect(harness.actions.isEnabled(ImageEditorAction.redo), isTrue);

      await tester.tap(_command(ImageEditorAction.redo));
      await _until(
        tester,
        () => _saveEnabled(tester),
        reason: 'redo text edit',
      );
      expect(
        harness.editor.activeLayers.whereType<TextLayer>().single.text,
        'First',
      );
      await tester.tap(_command(ImageEditorAction.undo));
      await _until(
        tester,
        () => !_saveEnabled(tester),
        reason: 'undo before branch',
      );
      await harness.addText('Different branch');
      expect(harness.actions.isEnabled(ImageEditorAction.redo), isFalse);
      expect(
        harness.editor.activeLayers.whereType<TextLayer>().single.text,
        'Different branch',
      );
      expect(harness.store.writes, isEmpty);
    },
  );

  _desktopTestWidgets(
    'PNG rotate, repeated save, undo and reopen preserve alpha and dimensions',
    (tester) async {
      final store = _MemoryImageStore();
      final harness = _Harness(tester, store);
      await harness.open();
      await harness.rotate();
      await harness.save();
      final first = image.decodePng(store.bytes)!;
      expect((first.width, first.height), (16, 24));
      expect(
        first.any((pixel) => pixel.a < 255),
        isTrue,
        reason: 'PNG transparency must survive flattening.',
      );

      await harness.rotate();
      await harness.save();
      expect(store.writes, hasLength(2));
      final second = image.decodePng(store.bytes)!;
      expect((second.width, second.height), (24, 16));
      expect(second.any((pixel) => pixel.a < 255), isTrue);
      expect(store.writes.last, isNot(orderedEquals(store.writes.first)));

      await tester.tap(_command(ImageEditorAction.undo));
      await _until(
        tester,
        () => _saveEnabled(tester),
        reason: 'undo away from saved revision',
      );
      await tester.tap(_command(ImageEditorAction.redo));
      await _until(
        tester,
        () => !_saveEnabled(tester),
        reason: 'redo to saved revision',
      );
      await harness.closeCleanly();
      await harness.reopen();
      expect(store.loads, 2);
      expect(_saveEnabled(tester), isFalse);
      expect(harness.editor.canUndo, isFalse);
      expect(harness.editor.activeLayers, isEmpty);
      expect(
        image.decodePng(store.bytes)!.getBytes(),
        orderedEquals(second.getBytes()),
      );
    },
  );

  _desktopTestWidgets(
    'large-aspect JPEG rotate exports and reopens beyond the upstream 2000px cap',
    (tester) async {
      final store = _MemoryImageStore(
        format: ImageFileFormat.jpeg,
        input: buildImageEditorFixture(
          format: ImageFileFormat.jpeg,
          width: 2401,
          height: 32,
        ),
      );
      final harness = _Harness(tester, store);
      await harness.open();
      await harness.rotate();
      await harness.save();
      expect(store.bytes.take(2), orderedEquals([0xff, 0xd8]));
      final decoded = image.decodeJpg(store.bytes)!;
      expect((decoded.width, decoded.height), (32, 2401));
      await harness.closeCleanly();
      await harness.reopen();
      expect(store.loads, 2);
      expect(_saveEnabled(tester), isFalse);
      expect(harness.editor.canUndo, isFalse);
    },
  );

  _desktopTestWidgets(
    'failed source save retains edits and close can retry the real capture',
    (tester) async {
      final store = _MemoryImageStore();
      final original = Uint8List.fromList(store.bytes);
      var failWrite = true;
      store.writer = (_) async {
        if (failWrite) throw StateError('upload failed');
        return ImageSaveOutcome.savedOriginal;
      };
      final harness = _Harness(tester, store);
      await harness.open();
      await harness.rotate();
      await tester.tap(_save);
      await _until(
        tester,
        () => store.writes.length == 1 && !harness.actions.busy,
        reason: 'failed write returned to an editable session',
      );
      expect(_saveEnabled(tester), isTrue);
      expect(find.text('Could not save image'), findsOneWidget);
      expect(find.byType(ImageEditorDialog), findsOneWidget);
      expect(store.bytes, orderedEquals(original));
      failWrite = false;
      await tester.tap(_close);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: _unsaved, matching: find.text('Save')),
      );
      await _until(
        tester,
        () => harness.key.currentState == null,
        reason: 'retry-save before close',
      );
      expect(store.writes, hasLength(2));
      expect(
        (
          image.decodePng(store.bytes)!.width,
          image.decodePng(store.bytes)!.height,
        ),
        (16, 24),
      );
    },
  );

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    _desktopTestWidgets(
      '${modifier.keyLabel}+S saves exactly once and leaves the editor open',
      (tester) async {
        final store = _MemoryImageStore();
        final harness = _Harness(tester, store);
        await harness.open();
        await harness.addText('Saved with keyboard');
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(modifier);
        await _until(
          tester,
          () =>
              store.writes.length == 1 &&
              !harness.actions.busy &&
              !_saveEnabled(tester),
          reason: 'host keyboard save',
        );
        expect(find.byType(ImageEditorDialog), findsOneWidget);
        expect(image.decodePng(store.bytes), isNotNull);
        expect(store.bytes, isNot(orderedEquals(buildImageEditorFixture())));
      },
    );
  }

  _desktopTestWidgets(
    'nested blur Cancel and Apply preserve the host and pending save boundary',
    (tester) async {
      final harness = _Harness(tester, _MemoryImageStore());
      await harness.open();
      await tester.tap(_command(ImageEditorAction.blur));
      await _until(
        tester,
        () => harness.editor.blurEditor.currentState != null,
        reason: 'blur tool',
      );
      harness.editor.blurEditor.currentState!.setBlurFactor(5);
      expect(_saveEnabled(tester), isFalse);
      expect(harness.actions.isEnabled(ImageEditorAction.undo), isFalse);
      await tester.ensureVisible(_cancelTool);
      await tester.tap(_cancelTool);
      await _until(
        tester,
        () => !harness.editor.isSubEditorOpen,
        reason: 'blur cancellation',
      );
      expect(harness.editor.stateManager.activeBlur, 0);
      expect(harness.editor.canUndo, isFalse);
      expect(find.byType(ImageEditorDialog), findsOneWidget);

      await tester.tap(_command(ImageEditorAction.blur));
      await _until(
        tester,
        () => harness.editor.blurEditor.currentState != null,
        reason: 'second blur tool',
      );
      harness.editor.blurEditor.currentState!.setBlurFactor(5);
      await tester.ensureVisible(_apply);
      await tester.tap(_apply);
      await _until(
        tester,
        () => !harness.editor.isSubEditorOpen && _saveEnabled(tester),
        reason: 'blur apply',
      );
      expect(harness.editor.stateManager.activeBlur, 5);
      expect(harness.actions.isEnabled(ImageEditorAction.undo), isTrue);
      expect(find.byType(ImageEditorDialog), findsOneWidget);
    },
  );

  _desktopTestWidgets(
    'system Back creates one host unsaved prompt and cancel keeps edits',
    (tester) async {
      final harness = _Harness(tester, _MemoryImageStore());
      await harness.open();
      await harness.addText('Unsaved');
      final pushesBeforeBack = harness.observer.pushes;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_unsaved, findsOneWidget);
      expect(harness.observer.pushes, pushesBeforeBack + 1);
      expect(find.byType(ImageEditorDialog), findsOneWidget);
      await tester.tap(
        find.descendant(of: _unsaved, matching: find.text('Cancel')),
      );
      await tester.pumpAndSettle();
      expect(_saveEnabled(tester), isTrue);
      expect(harness.editor.activeLayers, hasLength(1));
    },
  );

  _desktopTestWidgets(
    'secondary-click layer menu uses host UI and blocks background commands',
    (tester) async {
      final harness = _Harness(tester, _MemoryImageStore());
      await harness.open();
      await harness.addText('Context menu target');
      await tester.tap(
        find.byKey(harness.editor.activeLayers.single.keyInternalSize),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(PopupMenuItem<LayerContextMenuAction>, 'Remove'),
        findsOneWidget,
      );
      expect(harness.actions.isEnabled(ImageEditorAction.save), isFalse);
      harness.actions.dispatch(ImageEditorAction.close);
      await tester.pump();
      expect(
        find.widgetWithText(PopupMenuItem<LayerContextMenuAction>, 'Remove'),
        findsOneWidget,
      );
      expect(find.byType(ImageEditorDialog), findsOneWidget);
      await tester.tap(
        find.widgetWithText(PopupMenuItem<LayerContextMenuAction>, 'Remove'),
      );
      await _until(
        tester,
        () => harness.editor.activeLayers.isEmpty,
        reason: 'host menu removes layer',
      );
      expect(find.byType(ImageEditorDialog), findsOneWidget);
    },
  );

  _desktopTestWidgets(
    'pending source write locks commands and duplicate saves',
    (tester) async {
      final upload = Completer<ImageSaveOutcome>();
      final store = _MemoryImageStore()..writer = (_) => upload.future;
      final harness = _Harness(tester, store);
      await harness.open();
      await harness.addText('One write');
      await tester.tap(_save);
      await _until(
        tester,
        () => store.writes.length == 1,
        reason: 'capture before pending upload',
      );
      expect(tester.widget<IconButton>(_close).onPressed, isNull);
      expect(harness.actions.isEnabled(ImageEditorAction.save), isFalse);
      expect(harness.actions.isEnabled(ImageEditorAction.undo), isFalse);
      harness.actions.dispatch(ImageEditorAction.save);
      harness.actions.dispatch(ImageEditorAction.close);
      await tester.pump();
      expect(store.writes, hasLength(1));
      expect(find.byType(ImageEditorDialog), findsOneWidget);
      upload.complete(ImageSaveOutcome.savedOriginal);
      await _until(
        tester,
        () => !harness.actions.busy && !_saveEnabled(tester),
        reason: 'successful upload unlock',
      );
      expect(store.writes, hasLength(1));
    },
  );

  _desktopTestWidgets(
    'browser production worker captures an edited image and reopens it',
    (tester) async {
      final store = _MemoryImageStore();
      final harness = _Harness(tester, store);
      await harness.open(enableIsolateGeneration: true);
      await harness.rotate();
      await harness.save();
      final decoded = image.decodePng(store.bytes)!;
      expect((decoded.width, decoded.height), (16, 24));
      expect(decoded.any((pixel) => pixel.a < 255), isTrue);
      await harness.closeCleanly();
      await harness.reopen();
      expect(_saveEnabled(tester), isFalse);
    },
    skip: !kIsWeb,
  );
}
