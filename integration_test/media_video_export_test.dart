// Real AVFoundation/Media3 exports, not a mocked method channel.
//
// Run on a supported native target, for example:
// flutter test integration_test/media_video_export_test.dart -d macos \
//   --dart-define=MEDIA_TEST_KEEP_OUTPUT=true
//
// MEDIA_VIDEO_EXPORT lines name retained files for an independent ffprobe /
// ffmpeg verification step on a desktop CI host. No ffmpeg runtime is shipped.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:crisp_cloud/services/media_edit_session.dart';
import 'package:crisp_cloud/services/media_editor_backend.dart';
import 'package:crisp_cloud/services/media_video_backend.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

import '../test/support/media_video_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native video: trim, crop, rotation, resize, mute, reopen, cancellation',
    () async {
      final temporary = await getTemporaryDirectory();
      await temporary.create(recursive: true);
      final workspace = await Directory(temporary.path)
          .createTemp('crispcloud_video_contract_');
      const keepOutput = bool.fromEnvironment('MEDIA_TEST_KEEP_OUTPUT');
      addTearDown(() async {
        if (!keepOutput) await workspace.delete(recursive: true);
      });
      final input = File('${workspace.path}/source.mp4');
      final sourceBytes = mediaVideoFixture();
      await input.writeAsBytes(sourceBytes, flush: true);
      _reportFile(input, isExport: false);
      final backend = MediaVideoBackend();
      final source = await backend.probe(input.path);
      expect(source.kind, MediaKind.video);
      expect(source.width, 320);
      expect(source.height, 180);
      expect(source.duration.inMilliseconds, closeTo(4000, 100));
      expect(
        await ProVideoEditor.instance.hasAudioTrack(EditorVideo.file(input)),
        isTrue,
      );

      final cropOutput = File('${workspace.path}/trim_crop_rotate_mute.mp4');
      final progress = <double>[];
      await backend.render(
        inputPath: input.path,
        outputPath: cropOutput.path,
        edit: const MediaEdit(
          start: Duration(seconds: 1),
          end: Duration(seconds: 3),
          crop: MediaCrop(x: 0, y: 0, width: 0.5, height: 1),
          quarterTurns: 1,
          maxOutputHeight: 80,
          muted: true,
        ),
        cancellation: MediaCancellation(),
        onProgress: progress.add,
      );
      _reportFile(cropOutput);
      expect(progress.last, 1);
      final cropped = await backend.probe(cropOutput.path);
      expect(cropped.width, 90);
      expect(cropped.height, 80);
      expect(cropped.duration.inMilliseconds, closeTo(2000, 100));
      expect(
        await ProVideoEditor.instance.hasAudioTrack(
          EditorVideo.file(cropOutput),
        ),
        isFalse,
      );
      final audioOutput = File('${workspace.path}/trim_resize_audio.mp4');
      await backend.render(
        inputPath: input.path,
        outputPath: audioOutput.path,
        edit: const MediaEdit(
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 3500),
          maxOutputHeight: 90,
        ),
        cancellation: MediaCancellation(),
      );
      _reportFile(audioOutput);
      final resized = await backend.probe(audioOutput.path);
      expect(resized.width, 160);
      expect(resized.height, 90);
      expect(resized.duration.inMilliseconds, closeTo(3000, 100));
      expect(
        await ProVideoEditor.instance.hasAudioTrack(
          EditorVideo.file(audioOutput),
        ),
        isTrue,
      );

      // Reopen and edit an exported file, exercising actual media persistence
      // rather than reusing the source player or cached input metadata.
      final reopenedOutput = File('${workspace.path}/reopened_trim.mp4');
      await backend.render(
        inputPath: cropOutput.path,
        outputPath: reopenedOutput.path,
        edit: const MediaEdit(
          start: Duration(milliseconds: 250),
          end: Duration(milliseconds: 1750),
        ),
        cancellation: MediaCancellation(),
      );
      _reportFile(reopenedOutput);
      final reopened = await backend.probe(reopenedOutput.path);
      expect(reopened.duration.inMilliseconds, closeTo(1500, 100));
      expect((reopened.width, reopened.height), (90, 80));

      final cancelledOutput = File('${workspace.path}/cancelled.mp4');
      final cancellation = MediaCancellation();
      var scheduledCancellation = false;
      await expectLater(
        backend.render(
          inputPath: input.path,
          outputPath: cancelledOutput.path,
          edit: const MediaEdit(
            start: Duration.zero,
            end: Duration(seconds: 4),
            quarterTurns: 1,
            muted: true,
          ),
          cancellation: cancellation,
          onProgress: (_) {
            if (scheduledCancellation) return;
            scheduledCancellation = true;
            // Cancel after renderVideoToFile has registered the task but while
            // its asynchronous dispatch/render can still be in progress.
            scheduleMicrotask(cancellation.cancel);
          },
        ),
        throwsA(isA<MediaOperationCancelled>()),
      );
      expect(await cancelledOutput.exists(), isFalse);

      // Cancellation must not poison the adapter or a later native task ID.
      final retryOutput = File('${workspace.path}/after_cancel.mp4');
      await backend.render(
        inputPath: input.path,
        outputPath: retryOutput.path,
        edit: const MediaEdit(
          start: Duration(seconds: 1),
          end: Duration(seconds: 2),
          muted: true,
        ),
        cancellation: MediaCancellation(),
      );
      _reportFile(retryOutput);
      expect(
        (await backend.probe(retryOutput.path)).duration.inMilliseconds,
        closeTo(1000, 100),
      );
      expect(await input.readAsBytes(), orderedEquals(sourceBytes));

      // Assert pixels after every independent render has completed. A thumbnail
      // failure must still leave all native outputs available to FFmpeg in CI.
      const timestamps = <Duration>[
        Duration(milliseconds: 250),
        Duration(milliseconds: 1250),
      ];
      final frames = await _frames(cropOutput.path, const Size(90, 80), timestamps);
      if (keepOutput) {
        const sourceTimes = <Duration>[
          Duration(milliseconds: 1250),
          Duration(milliseconds: 2250),
        ];
        final originals = await _frames(input.path, const Size(320, 180), sourceTimes);
        for (var index = 0; index < originals.length; index++) {
          _reportPixel(originals[index], input.path, sourceTimes[index], 80, 45);
          _reportPixel(originals[index], input.path, sourceTimes[index], 80, 135);
          _reportPixel(frames[index], cropOutput.path, timestamps[index], 20, 40);
          _reportPixel(frames[index], cropOutput.path, timestamps[index], 70, 40);
        }
      }
      // Only the original left half survives. After clockwise rotation its
      // lower blue quadrant is on the left, and its upper quadrant is on the
      // right. The right color changes green -> yellow at output t=1s, proving
      // that trim starts at source t=1s instead of silently cutting from zero.
      _expectColor(frames[0], 20, 40, 0, 0, 255,
        path: cropOutput.path, timestamp: timestamps[0]);
      _expectColor(frames[0], 70, 40, 0, 255, 0,
        path: cropOutput.path, timestamp: timestamps[0]);
      _expectColor(frames[1], 20, 40, 0, 0, 255,
        path: cropOutput.path, timestamp: timestamps[1]);
      _expectColor(frames[1], 70, 40, 255, 255, 0,
        path: cropOutput.path, timestamp: timestamps[1]);
    },
    skip: !MediaVideoBackend.supportsPlatform(defaultTargetPlatform),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<List<image.Image>> _frames(
  String path,
  Size size,
  List<Duration> timestamps,
) async {
  final bytes = await ProVideoEditor.instance.getThumbnails(
    ThumbnailConfigs(
      video: EditorVideo.file(path),
      outputSize: size,
      outputFormat: ThumbnailFormat.png,
      boxFit: ThumbnailBoxFit.contain,
      timestamps: timestamps,
      maxParallelDecoders: 1,
    ),
  );
  expect(bytes, hasLength(timestamps.length));
  final frames = <image.Image>[];
  for (var index = 0; index < bytes.length; index++) {
    final frame = bytes[index];
    if (const bool.fromEnvironment('MEDIA_TEST_KEEP_OUTPUT')) {
      final thumbnail = File('$path.thumb-${timestamps[index].inMicroseconds}.png');
      await thumbnail.writeAsBytes(frame, flush: true);
      _reportFile(thumbnail, isExport: false);
    }
    final decoded = image.decodePng(frame);
    expect(
      decoded,
      isNotNull,
      reason: 'Exported frames must decode independently.',
    );
    expect(decoded!.width, size.width.toInt());
    expect(decoded.height, size.height.toInt());
    frames.add(decoded);
  }
  return frames;
}

void _reportFile(File file, {bool isExport = true}) {
  const keepOutput = bool.fromEnvironment('MEDIA_TEST_KEEP_OUTPUT');
  if (!keepOutput) return;
  // Emit before later assertions so partial/failed runs still retain evidence.
  // ignore: avoid_print
  print('MEDIA_VIDEO_${isExport ? 'EXPORT' : 'ARTIFACT'} ${jsonEncode(file.path)}');
}

void _reportPixel(image.Image frame, String path, Duration timestamp, int x, int y) {
  final pixel = frame.getPixel(x, y);
  // ignore: avoid_print
  print('MEDIA_VIDEO_SAMPLE ${jsonEncode({
    'path': path, 'timeUs': timestamp.inMicroseconds, 'x': x, 'y': y,
    'rgb': [pixel.r, pixel.g, pixel.b],
  })}');
}

void _expectColor(image.Image frame, int x, int y, int r, int g, int b, {
  required String path,
  required Duration timestamp,
}) {
  final pixel = frame.getPixel(x, y);
  final reason = '$path at ${timestamp.inMicroseconds}us, pixel ($x,$y): '
      'RGB (${pixel.r},${pixel.g},${pixel.b}), expected ($r,$g,$b).';
  // H.264/YUV conversion and platform color management can move values by a
  // few levels. This margin still rejects a wrong quadrant or rotation.
  expect(pixel.r, closeTo(r, 45), reason: reason);
  expect(pixel.g, closeTo(g, 45), reason: reason);
  expect(pixel.b, closeTo(b, 45), reason: reason);
}
