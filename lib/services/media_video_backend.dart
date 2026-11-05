import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:pro_video_editor/pro_video_editor.dart';

import 'media_edit_session.dart';
import 'media_editor_backend.dart';

bool _nativeLicensesRegistered = false;

/// Pub dependencies contribute their own LICENSE files automatically; Maven
/// dependencies do not, so add the native Android notices to Flutter's list.
void registerMediaVideoLicenses() {
  if (_nativeLicensesRegistered) return;
  _nativeLicensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(
      'packages/pro_video_editor/assets/licenses/native.txt',
    );
    yield LicenseEntryWithLineBreaks(
      const <String>['AndroidX Media3', 'AndroidX ExifInterface', 'Kotlin coroutines'],
      text,
    );
  });
}

/// File-based, single-clip editing using the platform's video codecs.
///
/// The caller owns the input snapshot and a fresh output path. Export never
/// overwrites the input or an existing destination. A native render is only
/// considered successful after its output can be reopened and inspected.
class MediaVideoBackend implements MediaEditorBackend {
  MediaVideoBackend({
    ProVideoEditor? editor,
    TargetPlatform? platform,
  }) : _editorOverride = editor,
       _platformOverride = platform;

  final ProVideoEditor? _editorOverride;
  final TargetPlatform? _platformOverride;
  bool _rendering = false;

  ProVideoEditor get _editor => _editorOverride ?? ProVideoEditor.instance;

  /// Upstream's other platforms provide metadata only, not video exports.
  static bool supportsPlatform(TargetPlatform platform, {bool isWeb = false}) =>
      !isWeb &&
      (platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS ||
          platform == TargetPlatform.macOS);

  void _requireSupportedPlatform() {
    if (!supportsPlatform(
      _platformOverride ?? defaultTargetPlatform,
      isWeb: kIsWeb,
    )) {
      throw UnsupportedError('Video editing is unavailable on this platform.');
    }
  }

  @override
  Future<MediaInfo> probe(String inputPath) async {
    _requireSupportedPlatform();
    return _mediaInfo(await _editor.getMetadata(EditorVideo.file(inputPath)));
  }

  @override
  Future<List<double>> waveform(String inputPath, {int points = 800}) async {
    _requireSupportedPlatform();
    // Audio editing has its own bounded-memory waveform backend. No waveform
    // is advertised for this single-clip video editor.
    return const <double>[];
  }

  @override
  Future<void> render({
    required String inputPath,
    required String outputPath,
    required MediaEdit edit,
    required MediaCancellation cancellation,
    void Function(double)? onProgress,
  }) async {
    _requireSupportedPlatform();
    if (_rendering) throw StateError('A video export is already running.');
    _rendering = true;
    final output = File(outputPath);
    StreamSubscription<ProgressModel>? subscription;
    void Function()? cancelListener;
    Future<void>? cancelling;
    var started = false;
    var completed = false;
    try {
      cancellation.throwIfCancelled();
      if (p.equals(p.absolute(inputPath), p.absolute(outputPath))) {
        throw ArgumentError('The export path must differ from the input.');
      }
      if (await output.exists()) {
        throw FileSystemException('The export path already exists.', outputPath);
      }

      final info = await probe(inputPath);
      final plan = _VideoExportPlan(info, edit);
      final data = buildMediaVideoRenderData(
        inputPath: inputPath,
        info: info,
        edit: edit,
      );
      cancellation.throwIfCancelled();

      subscription = _editor.progressStreamById(data.id).listen(
        (event) {
          if (!cancellation.isCancelled && event.progress.isFinite) {
            // The native encoder's completion precedes the reopen check.
            onProgress?.call(event.progress.clamp(0.0, 0.99).toDouble());
          }
        },
        // Progress is advisory. The render future is the authoritative error
        // channel; a lost progress event must not discard a valid export.
        onError: (Object error, StackTrace stack) {},
      );
      cancelListener = () {
        if (!started) return;
        cancelling ??= _editor.cancel(data.id).catchError((Object error) {
          // Completion can race a cancellation request. Still await the
          // render below and discard its result if cancellation was requested.
        });
      };
      cancellation.addListener(cancelListener);
      cancellation.throwIfCancelled();
      onProgress?.call(0);
      cancellation.throwIfCancelled();
      started = true;
      await _editor.renderVideoToFile(outputPath, data);
      if (cancelling != null) await cancelling;
      cancellation.throwIfCancelled();

      if (!await output.exists() || await output.length() < 32) {
        throw const FormatException('The encoder did not create a video.');
      }
      final metadata = await _editor.getMetadata(EditorVideo.file(outputPath));
      final rendered = _mediaInfo(metadata);
      _validateExport(rendered, metadata, plan, info, edit);
      cancellation.throwIfCancelled();
      completed = true;
      onProgress?.call(1);
    } on RenderCanceledException {
      throw const MediaOperationCancelled();
    } catch (_) {
      cancellation.throwIfCancelled();
      rethrow;
    } finally {
      if (cancelListener != null) cancellation.removeListener(cancelListener);
      try {
        try {
          await subscription?.cancel();
        } catch (_) {
          // A disconnected progress channel does not change the render result.
        }
        // Never delete a pre-existing output rejected during preflight. Native
        // completion/error/cancellation has settled before deleting its partial
        // output, so a still-running encoder cannot recreate it afterwards.
        if (started && !completed) {
          try {
            if (await output.exists()) await output.delete();
          } on FileSystemException {
            // The owning temporary workspace also cleans up on editor close.
          }
        }
      } finally {
        _rendering = false;
      }
    }
  }

  static MediaInfo _mediaInfo(VideoMetadata metadata) {
    final width = metadata.resolution.width;
    final height = metadata.resolution.height;
    if (metadata.duration <= Duration.zero ||
        !width.isFinite ||
        !height.isFinite ||
        width < 2 ||
        height < 2) {
      throw const FormatException('This file has no usable video track.');
    }
    return MediaInfo(
      kind: MediaKind.video,
      duration: metadata.duration,
      width: width.round(),
      height: height.round(),
      frameRate: metadata.frameRate,
    );
  }

  static void _validateExport(
    MediaInfo output,
    VideoMetadata metadata,
    _VideoExportPlan plan,
    MediaInfo source,
    MediaEdit edit,
  ) {
    // Native codecs may align dimensions by a pixel and clip only at frame
    // boundaries. Larger discrepancies mean an edit was not applied.
    if ((output.width! - plan.outputWidth).abs() > 2 ||
        (output.height! - plan.outputHeight).abs() > 2) {
      throw const FormatException('The export has unexpected dimensions.');
    }
    final fps = source.frameRate;
    final frameToleranceUs = fps != null && fps.isFinite && fps > 0
        ? (2000000 / fps).ceil()
        : 200000;
    final toleranceUs = math.max(100000, frameToleranceUs);
    final expectedUs = (edit.end - edit.start).inMicroseconds;
    if ((output.duration.inMicroseconds - expectedUs).abs() > toleranceUs) {
      throw const FormatException('The export has an unexpected duration.');
    }
    if (edit.muted && metadata.audioDuration != null) {
      throw const FormatException('The export still contains an audio track.');
    }
  }
}

/// Maps an immutable host edit into a native render request.
///
/// Crop coordinates are in the source's displayed orientation, before the
/// user's clockwise quarter-turns. Container rotation has already been applied
/// to [MediaInfo.width]/[MediaInfo.height] by the native metadata reader.
@visibleForTesting
VideoRenderData buildMediaVideoRenderData({
  required String inputPath,
  required MediaInfo info,
  required MediaEdit edit,
}) {
  final plan = _VideoExportPlan(info, edit);
  return VideoRenderData(
    videoSegments: <VideoSegment>[
      VideoSegment(
        video: EditorVideo.file(inputPath),
        startTime: edit.start,
        endTime: edit.end,
      ),
    ],
    transform: plan.transform,
    enableAudio: !edit.muted,
    outputFormat: VideoOutputFormat.mp4,
    // This single forward clip meets Apple's requirements for preserving the
    // original frame timestamps, including variable/fractional frame rates.
    preserveSourceFrameTiming: true,
    shouldOptimizeForNetworkUse: true,
  );
}

class _VideoExportPlan {
  _VideoExportPlan(MediaInfo info, MediaEdit edit) {
    edit.validate(info);
    final sourceWidth = info.width;
    final sourceHeight = info.height;
    if (info.kind != MediaKind.video ||
        sourceWidth == null ||
        sourceHeight == null ||
        sourceWidth < 2 ||
        sourceHeight < 2) {
      throw ArgumentError('Video dimensions must be known before export.');
    }
    final limit = edit.maxOutputHeight;

    final crop = edit.crop;
    var left = 0;
    var top = 0;
    var width = sourceWidth;
    var height = sourceHeight;
    if (crop != null) {
      left = (crop.x * sourceWidth).round();
      top = (crop.y * sourceHeight).round();
      final right = ((crop.x + crop.width) * sourceWidth)
          .round()
          .clamp(0, sourceWidth)
          .toInt();
      final bottom = ((crop.y + crop.height) * sourceHeight)
          .round()
          .clamp(0, sourceHeight)
          .toInt();
      width = right - left;
      height = bottom - top;
      if (width < 2 || height < 2) {
        throw ArgumentError('The crop must contain at least two pixels per axis.');
      }
    }

    final turns = edit.quarterTurns % 4;
    final rotatedWidth = turns.isOdd ? height : width;
    final rotatedHeight = turns.isOdd ? width : height;
    final scale = limit == null
        ? 1.0
        : math.min(1.0, limit / rotatedHeight);
    // Hardware H.264 encoders commonly require even dimensions. Round down
    // by at most one pixel per axis; this also avoids exceeding a resize cap.
    outputWidth = math.max(2, (rotatedWidth * scale / 2).floor() * 2);
    outputHeight = math.max(2, (rotatedHeight * scale / 2).floor() * 2);
    final scaleX = outputWidth / rotatedWidth;
    final scaleY = outputHeight / rotatedHeight;
    transform = ExportTransform(
      width: crop == null ? null : width,
      height: crop == null ? null : height,
      x: crop == null ? null : left,
      y: crop == null ? null : top,
      rotateTurns: turns,
      scaleX: scaleX == 1 ? null : scaleX,
      scaleY: scaleY == 1 ? null : scaleY,
    );
  }

  late final int outputWidth;
  late final int outputHeight;
  late final ExportTransform transform;
}
