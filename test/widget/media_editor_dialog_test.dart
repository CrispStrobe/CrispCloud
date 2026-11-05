import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/media_edit_session.dart';
import 'package:crisp_cloud/services/media_editor_backend.dart';
import 'package:crisp_cloud/services/media_editor_menu.dart';
import 'package:crisp_cloud/services/media_file_store.dart';
import 'package:crisp_cloud/widgets/media_editor_controls.dart';
import 'package:crisp_cloud/widgets/media_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// These doubles isolate the host's asynchronous history/save lifecycle. Native
// audio tests and the video integration test independently inspect real exports.
class _MemoryStore extends MediaFileStore {
  _MemoryStore({this.kind = MediaKind.audio});

  final MediaKind kind;
  final attempts = <(String, String)>[];
  final savedCopies = <(String, String)>[];
  final issuedPaths = <String>[];
  Completer<void>? stageGate;
  int failedStages = 0;
  int failedSaves = 0;
  int stages = 0;
  bool disposed = false;
  String? outputDirectory;

  @override
  String get displayName =>
      kind == MediaKind.audio ? 'recording.wav' : 'clip.mp4';
  @override
  String get path => '/__crisp_media_widget_test__/$displayName';
  @override
  String get documentId => 'test:$path';
  @override
  bool get isRemote => false;

  @override
  Future<String> stage() async {
    stages++;
    await stageGate?.future;
    if (failedStages > 0) {
      failedStages--;
      throw const MediaStoreException(MediaStoreFailure.accessDenied);
    }
    return path;
  }

  @override
  Future<String> createOutputPath(String extension) async {
    final output =
        '${outputDirectory ?? '/__crisp_media_widget_test__'}/output-${issuedPaths.length}.$extension';
    issuedPaths.add(output);
    return output;
  }

  @override
  Future<MediaSaveOutcome> saveCopy(
    String renderedPath,
    String fileName,
  ) async {
    attempts.add((renderedPath, fileName));
    if (failedSaves > 0) {
      failedSaves--;
      throw StateError('Simulated transfer failure');
    }
    savedCopies.add((renderedPath, fileName));
    return MediaSaveOutcome.savedCopy;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _Render {
  const _Render(this.inputPath, this.outputPath, this.edit, this.cancellation);
  final String inputPath;
  final String outputPath;
  final MediaEdit edit;
  final MediaCancellation cancellation;
}

class _Backend implements MediaEditorBackend {
  _Backend({this.kind = MediaKind.audio});

  final MediaKind kind;
  final probes = <String>[];
  final waveforms = <String>[];
  final renders = <_Render>[];
  final outputs = <String, MediaInfo>{};
  bool holdRender = false;
  bool invalidOutput = false;
  bool writeOutputFile = false;
  bool failOutputProbe = false;
  double? reportedFrameRate = 30;
  int cancellationNotifications = 0;

  MediaInfo get sourceInfo => MediaInfo(
    kind: kind,
    duration: const Duration(seconds: 10),
    sampleRate: kind == MediaKind.audio ? 48000 : null,
    channels: kind == MediaKind.audio ? 2 : null,
    width: kind == MediaKind.video ? 1920 : null,
    height: kind == MediaKind.video ? 1080 : null,
    frameRate: kind == MediaKind.video ? reportedFrameRate : null,
  );

  @override
  Future<MediaInfo> probe(String inputPath) async {
    probes.add(inputPath);
    if (failOutputProbe && outputs.containsKey(inputPath)) {
      throw const FormatException('Simulated output decoder failure');
    }
    return outputs[inputPath] ?? sourceInfo;
  }

  @override
  Future<List<double>> waveform(String inputPath, {int points = 800}) async {
    waveforms.add(inputPath);
    return const [0.1, 0.3, 0.8, 0.4, 0.2, 0.7, 0.5, 0.1];
  }

  @override
  Future<void> render({
    required String inputPath,
    required String outputPath,
    required MediaEdit edit,
    required MediaCancellation cancellation,
    void Function(double)? onProgress,
  }) async {
    renders.add(_Render(inputPath, outputPath, edit, cancellation));
    onProgress?.call(0.25);
    if (holdRender) {
      final gate = Completer<void>();
      void cancel() {
        cancellationNotifications++;
        if (!gate.isCompleted) gate.complete();
      }

      cancellation.addListener(cancel);
      try {
        await gate.future;
      } finally {
        cancellation.removeListener(cancel);
      }
    }
    cancellation.throwIfCancelled();
    var width = sourceInfo.width?.toDouble();
    var height = sourceInfo.height?.toDouble();
    if (width != null && height != null) {
      width *= edit.crop?.width ?? 1;
      height *= edit.crop?.height ?? 1;
      if (edit.quarterTurns.isOdd) (width, height) = (height, width);
      final scale = edit.maxOutputHeight == null
          ? 1.0
          : math.min(1.0, edit.maxOutputHeight! / height);
      width *= scale;
      height *= scale;
    }
    outputs[outputPath] = MediaInfo(
      kind: kind,
      duration: invalidOutput ? Duration.zero : edit.duration,
      sampleRate: sourceInfo.sampleRate,
      channels: sourceInfo.channels,
      width: width?.round(),
      height: height?.round(),
      frameRate: sourceInfo.frameRate,
    );
    if (writeOutputFile)
      await File(outputPath).writeAsBytes(List<int>.filled(64, 7));
    onProgress?.call(1);
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Finder get _close => find.byTooltip('Close editor');
Finder get _export => find.byTooltip('Export copy');
Finder get _unsaved => find.text('Export changes before closing?');

final _frameworkErrorStacks = <Object, StackTrace>{};

Future<void> _until(
  WidgetTester tester,
  bool Function() condition,
  String reason,
) async {
  for (var frame = 0; frame < 200; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    // The host may asynchronously remove a superseded render. Give filesystem
    // completion a real event turn without relying on the fake widget clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    final error = tester.takeException();
    if (error != null) {
      Error.throwWithStackTrace(
        error,
        _frameworkErrorStacks[error] ?? StackTrace.current,
      );
    }
    if (condition()) {
      await tester.pump();
      return;
    }
  }
  fail('Timed out waiting for $reason.');
}

class _Harness {
  _Harness(this.tester, {MediaKind kind = MediaKind.audio})
    : store = _MemoryStore(kind: kind),
      backend = _Backend(kind: kind);

  final WidgetTester tester;
  final _MemoryStore store;
  final _Backend backend;
  late ProviderContainer container;

  MediaEditorMenuActions? get maybeActions =>
      container.read(mediaEditorMenuProvider);
  MediaEditorMenuActions get actions => maybeActions!;
  MediaEditorControls get controls =>
      tester.widget<MediaEditorControls>(find.byType(MediaEditorControls));

  Future<void> open({bool waitForReady = true}) async {
    // Keep the framework's original stack if a helper consumes its exception;
    // otherwise a layout/semantics failure appears to originate in _until.
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.stack case final stack?)
        _frameworkErrorStacks[details.exception] = stack;
      previousErrorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => Dialog.fullscreen(
                    child: MediaEditorDialog(
                      file: FileItem(
                        name: store.displayName,
                        path: store.path,
                        isFolder: false,
                      ),
                      side: PanelSide.local,
                      storeOverride: store,
                      backendOverride: backend,
                      playbackAvailableOverride: false,
                    ),
                  ),
                ),
                child: const Text('Open media'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open media'));
    await tester.pump();
    container = ProviderScope.containerOf(
      tester.element(find.byType(MediaEditorDialog)),
      listen: false,
    );
    if (waitForReady) {
      await ready();
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> ready() => _until(
    tester,
    () => maybeActions?.ready == true && maybeActions?.busy == false,
    'staged media, decoded metadata and controls',
  );

  Future<void> value(String label, double value) async {
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is Slider &&
          (widget.semanticFormatterCallback
                  ?.call(widget.value)
                  .startsWith('$label:') ??
              false),
    );
    await tester.ensureVisible(finder);
    final slider = tester.widget<Slider>(finder);
    expect(slider.onChanged, isNotNull);
    expect(slider.onChangeEnd, isNotNull);
    // Drive the public slider callbacks, including its commit-on-release path.
    slider.onChanged!(value);
    await tester.pump();
    tester.widget<Slider>(finder).onChangeEnd!(value);
    await tester.pump();
    await tester.pump();
  }

  Future<void> time(String label, String value, {bool submit = true}) async {
    await tester.ensureVisible(_field(label));
    await tester.enterText(_field(label), value);
    if (submit) await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
  }

  Future<void> chooseExport({
    required String fileName,
    bool waitForCompletion = true,
  }) async {
    await tester.tap(_export);
    await _until(
      tester,
      () => _field('File name').evaluate().isNotEmpty,
      'export filename dialog',
    );
    expect(actions.busy, isTrue);
    expect(actions.isEnabled(MediaEditorAction.exportCopy), isFalse);
    await tester.enterText(_field('File name'), fileName);
    await tester.tap(find.widgetWithText(FilledButton, 'Create copy'));
    await tester.pump(const Duration(milliseconds: 400));
    if (waitForCompletion) {
      await _until(
        tester,
        () => maybeActions?.busy == false,
        'render and persistence result',
      );
    }
  }

  Future<void> openClosePrompt() async {
    await tester.tap(_close);
    await _until(
      tester,
      () => _unsaved.evaluate().isNotEmpty,
      'unsaved changes dialog',
    );
    expect(actions.busy, isTrue);
    for (final action in MediaEditorAction.values) {
      expect(actions.isEnabled(action), isFalse);
    }
  }

  Future<void> continueEditing() async {
    await tester.tap(find.widgetWithText(TextButton, 'Continue editing'));
    await tester.pump(const Duration(milliseconds: 400));
    await ready();
  }

  Future<void> closeCleanly() async {
    await tester.tap(_close);
    await _until(
      tester,
      () => find.byType(MediaEditorDialog).evaluate().isEmpty,
      'clean editor close',
    );
    expect(_unsaved, findsNothing);
    await _until(
      tester,
      () => store.disposed && maybeActions == null,
      'workspace disposal and menu release',
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _frameworkErrorStacks.clear();
  });

  testWidgets(
    'loading blocks commands until source metadata and waveform are ready',
    (tester) async {
      final harness = _Harness(tester);
      harness.store.stageGate = Completer<void>();
      await harness.open(waitForReady: false);
      expect(find.text('Loading media…'), findsOneWidget);
      expect(harness.backend.probes, isEmpty);
      expect(harness.actions.busy, isTrue);
      expect(harness.actions.isEnabled(MediaEditorAction.exportCopy), isFalse);
      expect(harness.actions.isEnabled(MediaEditorAction.undo), isFalse);

      harness.store.stageGate!.complete();
      await harness.ready();
      expect(harness.store.stages, 1);
      expect(harness.backend.probes, [harness.store.path]);
      expect(harness.backend.waveforms, [harness.store.path]);
      expect(harness.controls.peaks, hasLength(8));
      expect(harness.controls.edit.start, Duration.zero);
      expect(harness.controls.edit.end, const Duration(seconds: 10));
      expect(harness.actions.isEnabled(MediaEditorAction.exportCopy), isTrue);
      expect(harness.actions.isEnabled(MediaEditorAction.preview), isFalse);
      expect(
        find.text('Playback is unavailable. You can still edit and export.'),
        findsOneWidget,
      );
      await harness.closeCleanly();
    },
  );

  testWidgets(
    'precision trim, gain and fades reach export even without submitting the last field',
    (tester) async {
      final harness = _Harness(tester);
      await harness.open();
      await harness.time('Start', '0:01.250');
      await harness.value('Gain', -6);
      await harness.value('Fade in', 0.5);
      await harness.value('Fade out', 0.75);
      // Clicking Export must commit the focused end field; no Enter is sent.
      await harness.time('End', '0:08.500', submit: false);
      await harness.chooseExport(fileName: 'voice-edited.wav');

      expect(harness.backend.renders, hasLength(1));
      final render = harness.backend.renders.single;
      expect(render.inputPath, harness.store.path);
      expect(render.edit.start, const Duration(milliseconds: 1250));
      expect(render.edit.end, const Duration(milliseconds: 8500));
      expect(render.edit.gainDb, -6);
      expect(render.edit.fadeIn, const Duration(milliseconds: 500));
      expect(render.edit.fadeOut, const Duration(milliseconds: 750));
      expect(harness.backend.probes, [harness.store.path, render.outputPath]);
      expect(harness.store.savedCopies, [
        (render.outputPath, 'voice-edited.wav'),
      ]);
      expect(render.outputPath, isNot(harness.store.path));
      expect(find.text('Copy exported'), findsOneWidget);
      await harness.closeCleanly();
    },
  );

  testWidgets(
    'invalid pending precision text prevents a clean editor from closing',
    (tester) async {
      final harness = _Harness(tester);
      await harness.open();
      await harness.time('Start', '1:', submit: false);
      await tester.tap(_close);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MediaEditorDialog), findsOneWidget);
      expect(_unsaved, findsNothing);
      expect(find.text('Could not apply changes'), findsWidgets);
      expect(harness.controls.edit.start, Duration.zero);
      expect(harness.store.disposed, isFalse);
      expect(harness.backend.renders, isEmpty);

      await harness.time('Start', '0:00.000');
      await harness.closeCleanly();
    },
  );

  testWidgets(
    'failed persistence stays dirty and retry reuses the verified render',
    (tester) async {
      final harness = _Harness(tester);
      harness.store.failedSaves = 1;
      await harness.open();
      await harness.value('Gain', -12);
      await harness.chooseExport(fileName: 'retry.wav');
      expect(find.text('Could not export media'), findsOneWidget);
      expect(harness.store.savedCopies, isEmpty);
      expect(harness.store.attempts, hasLength(1));
      expect(harness.backend.renders, hasLength(1));
      expect(harness.actions.isEnabled(MediaEditorAction.undo), isTrue);

      await harness.openClosePrompt();
      await harness.continueEditing();
      expect(harness.controls.edit.gainDb, -12);
      await harness.chooseExport(fileName: 'retry.wav');
      expect(harness.store.attempts, hasLength(2));
      expect(harness.store.attempts[0].$1, harness.store.attempts[1].$1);
      expect(
        harness.backend.renders,
        hasLength(1),
        reason: 'Persistence retry must not re-encode',
      );
      expect(
        harness.backend.probes,
        hasLength(2),
        reason: 'The cached render already passed validation',
      );
      expect(harness.store.savedCopies, hasLength(1));
      expect(find.text('Copy exported'), findsOneWidget);
      await harness.closeCleanly();
    },
  );

  testWidgets(
    'cancelled export cannot save or clear edits and retry renders again',
    (tester) async {
      final harness = _Harness(tester);
      harness.backend.holdRender = true;
      await harness.open();
      await harness.time('Start', '2');
      await harness.chooseExport(
        fileName: 'cancel-test.wav',
        waitForCompletion: false,
      );
      await _until(
        tester,
        () => harness.backend.renders.isNotEmpty,
        'active render',
      );
      expect(harness.actions.busy, isTrue);
      for (final action in MediaEditorAction.values) {
        expect(harness.actions.isEnabled(action), isFalse);
      }
      harness.actions.dispatch(MediaEditorAction.exportCopy);
      expect(harness.backend.renders, hasLength(1));
      final cancel = find.widgetWithText(TextButton, 'Cancel export');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await _until(
        tester,
        () => harness.maybeActions?.busy == false,
        'cancelled export completion',
      );
      expect(harness.backend.cancellationNotifications, 1);
      expect(harness.backend.renders.single.cancellation.isCancelled, isTrue);
      expect(harness.store.attempts, isEmpty);
      expect(find.text('Export cancelled'), findsOneWidget);

      await harness.openClosePrompt();
      await harness.continueEditing();
      harness.backend.holdRender = false;
      await harness.chooseExport(fileName: 'cancel-test.wav');
      expect(harness.backend.renders, hasLength(2));
      expect(
        harness.backend.renders[0].outputPath,
        isNot(harness.backend.renders[1].outputPath),
      );
      expect(harness.store.savedCopies, hasLength(1));
      await harness.closeCleanly();
    },
  );

  testWidgets(
    'native menu undo and redo preserve history and discard releases the store',
    (tester) async {
      final harness = _Harness(tester);
      await harness.open();
      await harness.value('Gain', -6);
      await harness.value('Fade in', 0.5);
      harness.actions.dispatch(MediaEditorAction.undo);
      await tester.pump();
      await tester.pump();
      expect(harness.controls.edit.gainDb, -6);
      expect(harness.controls.edit.fadeIn, Duration.zero);
      expect(harness.actions.isEnabled(MediaEditorAction.redo), isTrue);
      harness.actions.dispatch(MediaEditorAction.redo);
      await tester.pump();
      await tester.pump();
      expect(harness.controls.edit.fadeIn, const Duration(milliseconds: 500));

      harness.actions.dispatch(MediaEditorAction.close);
      await _until(
        tester,
        () => _unsaved.evaluate().isNotEmpty,
        'native-menu close confirmation',
      );
      expect(harness.actions.busy, isTrue);
      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await _until(
        tester,
        () => find.byType(MediaEditorDialog).evaluate().isEmpty,
        'discard and close',
      );
      await _until(
        tester,
        () => harness.store.disposed && harness.maybeActions == null,
        'discard cleanup',
      );
      expect(harness.backend.renders, isEmpty);
      expect(harness.store.attempts, isEmpty);
    },
  );

  testWidgets(
    'reopening an invalid output prevents persistence and permits a new render',
    (tester) async {
      final harness = _Harness(tester);
      harness.backend.invalidOutput = true;
      await harness.open();
      await harness.value('Gain', -3);
      await harness.chooseExport(fileName: 'verified.wav');
      expect(
        find.text(
          'The exported file could not be verified. Try exporting again.',
        ),
        findsOneWidget,
      );
      expect(harness.backend.probes, hasLength(2));
      expect(harness.store.attempts, isEmpty);
      await harness.openClosePrompt();
      await harness.continueEditing();

      harness.backend.invalidOutput = false;
      await harness.chooseExport(fileName: 'verified.wav');
      expect(harness.backend.renders, hasLength(2));
      expect(harness.store.savedCopies, hasLength(1));
      await harness.closeCleanly();
    },
  );

  testWidgets(
    'a file that fails the host reopen check is removed before retry',
    (tester) async {
      final temporary = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('crisp_media_host_cleanup_'),
      ))!;
      addTearDown(() async {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final harness = _Harness(tester);
      harness.store.outputDirectory = temporary.path;
      harness.backend.writeOutputFile = true;
      harness.backend.failOutputProbe = true;
      await harness.open();
      await harness.value('Gain', -3);
      await harness.chooseExport(fileName: 'checked.wav');
      final rejectedPath = harness.store.issuedPaths.single;
      expect(await tester.runAsync(() => File(rejectedPath).exists()), isFalse);
      expect(harness.store.attempts, isEmpty);
      expect(find.text('Could not export media'), findsOneWidget);

      harness.backend.failOutputProbe = false;
      await harness.chooseExport(fileName: 'checked.wav');
      expect(harness.store.issuedPaths, hasLength(2));
      expect(harness.store.savedCopies, hasLength(1));
      expect(
        await tester.runAsync(
          () => File(harness.store.savedCopies.single.$1).exists(),
        ),
        isTrue,
        reason: 'A verified render remains available for persistence/retry.',
      );
      await harness.closeCleanly();
    },
  );

  testWidgets('a failed load shows a safe error and retry starts no renderer', (
    tester,
  ) async {
    final harness = _Harness(tester);
    harness.store.failedStages = 1;
    await harness.open(waitForReady: false);
    await _until(
      tester,
      () => find
          .text('Access to this folder was not granted.')
          .evaluate()
          .isNotEmpty,
      'safe load error',
    );
    expect(harness.backend.probes, isEmpty);
    expect(harness.actions.isEnabled(MediaEditorAction.exportCopy), isFalse);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await harness.ready();
    expect(harness.store.stages, 2);
    expect(harness.backend.renders, isEmpty);
    await harness.closeCleanly();
  });

  testWidgets('queued Retry callbacks cannot overlap the same load', (
    tester,
  ) async {
    final harness = _Harness(tester);
    harness.store.failedStages = 1;
    await harness.open(waitForReady: false);
    await _until(
      tester,
      () => find.widgetWithText(OutlinedButton, 'Retry').evaluate().isNotEmpty,
      'failed load and retry button',
    );
    harness.store.stageGate = Completer<void>();
    final retry = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Retry'))
        .onPressed!;
    // Two button callbacks queued before the loading frame replaces the button.
    retry();
    retry();
    expect(
      harness.store.stages,
      2,
      reason: 'One failed initial load and one retry.',
    );
    await tester.pump();
    expect(find.text('Loading media…'), findsOneWidget);
    harness.store.stageGate!.complete();
    await harness.ready();
    expect(harness.backend.probes, hasLength(1));
    await harness.closeCleanly();
  });

  for (final frameRate in <double>[0, double.nan, double.infinity]) {
    testWidgets(
      'video with unknown frame rate $frameRate can pass output validation',
      (tester) async {
        final harness = _Harness(tester, kind: MediaKind.video);
        harness.backend.reportedFrameRate = frameRate;
        await harness.open();
        await harness.chooseExport(fileName: 'unknown-rate.mp4');
        expect(harness.store.savedCopies, hasLength(1));
        expect(find.text('Copy exported'), findsOneWidget);
        await harness.closeCleanly();
      },
    );
  }

  testWidgets(
    'cancelling filename selection leaves edits available without rendering',
    (tester) async {
      final harness = _Harness(tester);
      await harness.open();
      await harness.value('Gain', -9);
      await tester.tap(_export);
      await _until(
        tester,
        () => _field('File name').evaluate().isNotEmpty,
        'filename selection',
      );
      final suggested = tester
          .widget<TextField>(_field('File name'))
          .controller!
          .text;
      expect(suggested, matches(r'^recording-edited-[0-9a-f]{8}\.wav$'));
      expect(harness.actions.busy, isTrue);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump(const Duration(milliseconds: 400));
      await harness.ready();
      expect(harness.backend.renders, isEmpty);
      expect(harness.store.attempts, isEmpty);
      expect(harness.controls.edit.gainDb, -9);
      await harness.openClosePrompt();
      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await _until(
        tester,
        () => find.byType(MediaEditorDialog).evaluate().isEmpty,
        'discard after naming cancellation',
      );
    },
  );

  testWidgets(
    'video controls produce crop, rotation, resize and mute in the exported recipe',
    (tester) async {
      final harness = _Harness(tester, kind: MediaKind.video);
      await harness.open();
      expect(harness.backend.waveforms, isEmpty);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Rotate clockwise'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Mute'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('media-crop-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Square').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('media-height-null')),
      );
      await tester.tap(find.byKey(const ValueKey('media-height-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p').last);
      await tester.pumpAndSettle();
      await harness.chooseExport(fileName: 'square-muted.mp4');
      final edit = harness.backend.renders.single.edit;
      expect(edit.quarterTurns, 1);
      expect(edit.muted, isTrue);
      expect(edit.maxOutputHeight, 720);
      expect(
        edit.crop,
        const MediaCrop(x: 0.21875, y: 0, width: 0.5625, height: 1),
      );
      expect(harness.store.savedCopies.single.$2, 'square-muted.mp4');
      await harness.closeCleanly();
    },
  );
}
