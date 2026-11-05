import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:crisp_cloud/services/media_edit_session.dart';
import 'package:crisp_cloud/services/media_editor_backend.dart';
import 'package:crisp_cloud/services/media_video_backend.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sourceInfo = MediaInfo(
    kind: MediaKind.video,
    duration: Duration(seconds: 10),
    width: 1920,
    height: 1080,
    frameRate: 30,
  );
  const trim = MediaEdit(start: Duration(seconds: 2), end: Duration(seconds: 5));

  group('video export contract', () {
    test('trim is applied once to the source and retains frame timing', () async {
      final request = buildMediaVideoRenderData(
        inputPath: '/snapshot/movie.mp4',
        info: sourceInfo,
        edit: trim,
      );
      expect(request.videoSegments, hasLength(1));
      expect(request.videoSegments!.single.startTime, trim.start);
      expect(request.videoSegments!.single.endTime, trim.end);
      expect(request.startTime, isNull);
      expect(request.endTime, isNull);
      expect(request.preserveSourceFrameTiming, isTrue);
      expect(request.outputFormat, VideoOutputFormat.mp4);
      expect(request.shouldOptimizeForNetworkUse, isTrue);
      expect(request.enableAudio, isTrue);
    });

    test('crop uses source orientation, then rotation and resize', () {
      final request = buildMediaVideoRenderData(
        inputPath: '/snapshot/portrait.mov',
        info: const MediaInfo(
          kind: MediaKind.video,
          duration: Duration(seconds: 4),
          width: 1080,
          height: 1920,
        ),
        edit: const MediaEdit(
          start: Duration(seconds: 1),
          end: Duration(seconds: 3),
          crop: MediaCrop(x: 0.25, y: 0.125, width: 0.5, height: 0.75),
          quarterTurns: 1,
          maxOutputHeight: 270,
          muted: true,
        ),
      );
      // Displayed crop is 540×1440 at (270,240); clockwise rotation makes
      // 1440×540, then half-size output is 720×270.
      expect(request.transform!.toMap(), <String, Object?>{
        'rotateTurns': 1,
        'flipX': false,
        'flipY': false,
        'cropWidth': 540,
        'cropHeight': 1440,
        'cropX': 270,
        'cropY': 240,
        'scaleX': 0.5,
        'scaleY': 0.5,
      });
      expect(request.enableAudio, isFalse);
    });

    test('resize never upscales and rounds a codec dimension down', () {
      final small = buildMediaVideoRenderData(
        inputPath: '/snapshot/small.mp4',
        info: const MediaInfo(
          kind: MediaKind.video,
          duration: Duration(seconds: 10),
          width: 641,
          height: 360,
        ),
        edit: const MediaEdit(
          start: Duration.zero,
          end: Duration(seconds: 10),
          maxOutputHeight: 1080,
        ),
      );
      expect(small.transform!.scaleX, closeTo(640 / 641, 1e-12));
      expect(small.transform!.scaleY, isNull);
    });

    test('rejects invalid edits before invoking a native encoder', () {
      final badEdits = <MediaEdit>[
        const MediaEdit(start: Duration(seconds: -1), end: Duration(seconds: 2)),
        const MediaEdit(start: Duration.zero, end: Duration(seconds: 11)),
        const MediaEdit(start: Duration(seconds: 2), end: Duration(seconds: 2)),
        const MediaEdit(
          start: Duration.zero,
          end: Duration(seconds: 2),
          crop: MediaCrop(x: 0.9, y: 0, width: 0.2, height: 1),
        ),
        const MediaEdit(
          start: Duration.zero,
          end: Duration(seconds: 2),
          maxOutputHeight: 1,
        ),
      ];
      for (final edit in badEdits) {
        expect(
          () => buildMediaVideoRenderData(
            inputPath: '/snapshot/movie.mp4',
            info: sourceInfo,
            edit: edit,
          ),
          throwsA(isA<MediaEditException>()),
        );
      }
      expect(
        () => buildMediaVideoRenderData(
          inputPath: '/snapshot/movie.mp4',
          info: sourceInfo,
          edit: const MediaEdit(
            start: Duration.zero,
            end: Duration(seconds: 2),
            fadeIn: Duration(milliseconds: 100),
          ),
        ),
        throwsA(isA<MediaEditException>()),
      );
    });

    test('only platforms with native exports advertise support', () {
      for (final platform in TargetPlatform.values) {
        expect(
          MediaVideoBackend.supportsPlatform(platform),
          <TargetPlatform>{
            TargetPlatform.android,
            TargetPlatform.iOS,
            TargetPlatform.macOS,
          }.contains(platform),
        );
        expect(
          MediaVideoBackend.supportsPlatform(platform, isWeb: true),
          isFalse,
        );
      }
    });
  });

  group('video export lifecycle', () {
    late Directory directory;
    late File source;
    late File output;
    late _FakeVideoEditor engine;
    late MediaVideoBackend backend;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('crisp_video_contract_');
      source = File('${directory.path}/input.mp4');
      output = File('${directory.path}/export.mp4');
      await source.writeAsBytes(List<int>.filled(100, 17));
      engine = _FakeVideoEditor(source.path);
      backend = MediaVideoBackend(editor: engine, platform: TargetPlatform.macOS);
    });

    tearDown(() async {
      await engine.close();
      await directory.delete(recursive: true);
    });

    Future<void> render({MediaCancellation? cancellation, MediaEdit edit = trim}) {
      return backend.render(
        inputPath: source.path,
        outputPath: output.path,
        edit: edit,
        cancellation: cancellation ?? MediaCancellation(),
      );
    }

    test('reopens the output before reporting success', () async {
      final progress = <double>[];
      await backend.render(
        inputPath: source.path,
        outputPath: output.path,
        edit: trim,
        cancellation: MediaCancellation(),
        onProgress: progress.add,
      );
      expect(engine.metadataPaths, <String>[source.path, output.path]);
      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(await output.exists(), isTrue);
      expect(await source.readAsBytes(), everyElement(17));
    });

    test('never overwrites source or an existing output', () async {
      await output.writeAsBytes(<int>[3, 4, 5]);
      await expectLater(render(), throwsA(isA<FileSystemException>()));
      expect(await output.readAsBytes(), <int>[3, 4, 5]);
      await expectLater(
        backend.render(
          inputPath: source.path,
          outputPath: source.path,
          edit: trim,
          cancellation: MediaCancellation(),
        ),
        throwsArgumentError,
      );
      expect(engine.requests, isEmpty);
      expect(await source.readAsBytes(), everyElement(17));
    });

    test('a partial native failure is removed and export can be retried', () async {
      engine.renderAction = (path, request) async {
        await File(path).writeAsBytes(<int>[1, 2, 3]);
        throw StateError('Encoder rejected the request.');
      };
      await expectLater(render(), throwsStateError);
      expect(await output.exists(), isFalse);
      engine.renderAction = null;
      await render();
      expect(await output.length(), 100);
    });

    test('missing/truncated or ignored edits are not accepted as exports', () async {
      engine.renderAction = (path, request) async {};
      await expectLater(render(), throwsFormatException);
      expect(await output.exists(), isFalse);
      engine.renderAction = (path, request) =>
          File(path).writeAsBytes(<int>[1, 2, 3]).then((_) {});
      await expectLater(render(), throwsFormatException);
      expect(await output.exists(), isFalse);
      engine.renderAction = null;
      engine.outputDuration = const Duration(seconds: 10); // trim ignored
      await expectLater(render(), throwsFormatException);
      expect(await output.exists(), isFalse);
      engine.outputDuration = const Duration(seconds: 3);
      engine.outputSize = const Size(1280, 720); // unexpected encoder scaling
      await expectLater(render(), throwsFormatException);
      expect(await output.exists(), isFalse);
    });

    test('mute is verified against the reopened audio track', () async {
      const muted = MediaEdit(
        start: Duration(seconds: 2),
        end: Duration(seconds: 5),
        muted: true,
      );
      engine.outputHasAudio = true;
      await expectLater(render(edit: muted), throwsFormatException);
      expect(await output.exists(), isFalse);
      engine.outputHasAudio = false;
      await render(edit: muted);
      expect(await output.exists(), isTrue);
    });

    test('pre-cancelled work never reaches the renderer', () async {
      final cancellation = MediaCancellation()..cancel();
      await expectLater(
        render(cancellation: cancellation),
        throwsA(isA<MediaOperationCancelled>()),
      );
      expect(engine.requests, isEmpty);
      expect(await output.exists(), isFalse);
    });

    test('in-flight cancellation waits, removes partial output and permits retry', () async {
      final started = Completer<void>();
      final finished = Completer<void>();
      engine.renderAction = (path, request) async {
        await File(path).writeAsBytes(<int>[9, 8, 7]);
        started.complete();
        await finished.future;
      };
      engine.cancelAction = (id) async {
        finished.completeError(const RenderCanceledException());
      };
      final cancellation = MediaCancellation();
      final result = render(cancellation: cancellation);
      final checked = expectLater(result, throwsA(isA<MediaOperationCancelled>()));
      await started.future;
      cancellation.cancel();
      await checked;
      expect(engine.cancelledIds, <String>[engine.requests.single.id]);
      expect(await output.exists(), isFalse);
      engine.renderAction = null;
      await render();
      expect(await output.exists(), isTrue);
    });

    test('a late cancellation discards even a completed native render', () async {
      final cancellation = MediaCancellation();
      engine.renderAction = (path, request) async {
        await File(path).writeAsBytes(List<int>.filled(100, 42));
        cancellation.cancel();
      };
      await expectLater(
        render(cancellation: cancellation),
        throwsA(isA<MediaOperationCancelled>()),
      );
      expect(await output.exists(), isFalse);
    });

    test('overlapping exports are rejected while the first remains valid', () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      engine.renderAction = (path, request) async {
        started.complete();
        await finish.future;
        await File(path).writeAsBytes(List<int>.filled(100, 42));
      };
      final first = render();
      await started.future;
      await expectLater(render(), throwsStateError);
      finish.complete();
      await first;
      expect(engine.requests, hasLength(1));
      expect(await output.exists(), isTrue);
    });
  });
}

class _FakeVideoEditor extends ProVideoEditor {
  _FakeVideoEditor(this.inputPath);

  final String inputPath;
  final metadataPaths = <String>[];
  final requests = <VideoRenderData>[];
  final cancelledIds = <String>[];
  Duration outputDuration = const Duration(seconds: 3);
  Size outputSize = const Size(1920, 1080);
  bool outputHasAudio = true;
  Future<void> Function(String, VideoRenderData)? renderAction;
  Future<void> Function(String)? cancelAction;

  @override
  void initializeStream() {}

  @override
  Future<VideoMetadata> getMetadata(
    EditorVideo value, {
    bool checkStreamingOptimization = false,
    NativeLogLevel? nativeLogLevel,
  }) async {
    final path = (value.file as File).path;
    metadataPaths.add(path);
    final original = path == inputPath;
    return VideoMetadata(
      duration: original ? const Duration(seconds: 10) : outputDuration,
      extension: 'mp4',
      fileSize: 100,
      resolution: original ? const Size(1920, 1080) : outputSize,
      rotation: 0,
      bitrate: 1000000,
      frameRate: 30,
      audioDuration: original || outputHasAudio
          ? (original ? const Duration(seconds: 10) : outputDuration)
          : null,
    );
  }

  @override
  Future<String> renderVideoToFile(
    String filePath,
    VideoRenderData value, {
    NativeLogLevel? nativeLogLevel,
  }) async {
    requests.add(value);
    if (renderAction != null) {
      await renderAction!(filePath, value);
    } else {
      progressCtrl.add(ProgressModel(id: value.id, progress: 0.5));
      await File(filePath).writeAsBytes(List<int>.filled(100, 42));
      progressCtrl.add(ProgressModel(id: value.id, progress: 1));
    }
    return filePath;
  }

  @override
  Future<void> cancel(String taskId) async {
    cancelledIds.add(taskId);
    await cancelAction?.call(taskId);
  }

  Future<void> close() async {
    await progressCtrl.close();
    await logCtrl.close();
  }
}
